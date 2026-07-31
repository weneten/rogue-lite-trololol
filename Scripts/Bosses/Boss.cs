using Godot;
using Nightbane.AI;
using Nightbane.Autoloads;
using Nightbane.Combat;
using Nightbane.Resources;

namespace Nightbane.Bosses;

/// <summary>
/// Base boss actor: phase transitions from BossData HP thresholds, telegraphed attack
/// state machine (Chase → Windup → Recover), contact damage, and Enemy-group targeting so
/// player weapons hit. Subclasses override ExecuteAttack for boss-specific patterns.
/// </summary>
public partial class Boss : CharacterBody2D
{
    protected enum BossState
    {
        Chase,
        Windup,
        Recover,
        Dead
    }

    [Export] public BossData Data { get; set; }

    [ExportGroup("Wiring")]
    [Export] public NodePath HealthComponentPath { get; set; }
    [Export] public NodePath SpriteNodePath { get; set; }
    [Export] public NodePath CollisionShapePath { get; set; }
    [Export] public NodePath ContactHitboxPath { get; set; }

    protected HealthComponent Health;
    protected Polygon2D Sprite;
    protected CollisionShape2D CollisionShape;
    protected Area2D ContactHitbox;

    protected BossState State = BossState.Chase;
    protected int CurrentPhaseIndex;
    protected double AttackCooldownRemaining;
    protected double WindupRemaining;
    protected double RecoverRemaining;
    protected double ContactCooldownRemaining;
    protected BossAttackPatternData PendingAttack;
    protected BossAoeTelegraph ActiveTelegraph;
    protected PackedScene EnemyScene;

    /// <summary>Minions spawned this fight; freed when the boss dies.</summary>
    protected readonly System.Collections.Generic.List<Node> SpawnedMinions = new();

    public override void _Ready()
    {
        AddToGroup("Enemy");
        AddToGroup("Boss");

        Health = GetNodeOrNull<HealthComponent>(HealthComponentPath);
        Sprite = GetNodeOrNull<Polygon2D>(SpriteNodePath);
        CollisionShape = GetNodeOrNull<CollisionShape2D>(CollisionShapePath);
        ContactHitbox = GetNodeOrNull<Area2D>(ContactHitboxPath);
        EnemyScene = GD.Load<PackedScene>("res://Scenes/Enemies/Enemy.tscn");

        if (Health != null)
        {
            Health.Died += OnDied;
            Health.HealthChanged += OnHealthChanged;
        }
        else
        {
            GD.PushWarning($"[{GetType().Name}] HealthComponentPath not wired.");
        }

        if (Data != null)
        {
            ApplyData(Data);
        }
    }

    /// <summary>Called by BossManager after Instantiate, before the boss is active in-world.</summary>
    public virtual void Initialize(BossData data)
    {
        Data = data;
        ApplyData(data);
        CurrentPhaseIndex = 0;
        State = BossState.Chase;
        AttackCooldownRemaining = 1.0;
        ContactCooldownRemaining = 0;
        PendingAttack = null;
        Velocity = Vector2.Zero;
        OnPhaseEntered(0);
    }

    protected virtual void ApplyData(BossData data)
    {
        if (data == null)
        {
            return;
        }

        if (Health != null)
        {
            Health.MaxHealth = data.MaxHealth;
            Health.Revive(data.MaxHealth);
        }

        if (Sprite != null)
        {
            Sprite.Color = data.SpriteColor;
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        if (Data == null || Health == null || Health.IsDead || State == BossState.Dead)
        {
            Velocity = Vector2.Zero;
            MoveAndSlide();
            return;
        }

        UpdatePhaseFromHealth();

        Node2D player = GetTree().GetFirstNodeInGroup("Player") as Node2D;
        HealthComponent playerHealth = player?.GetNodeOrNull<HealthComponent>("HealthComponent");
        bool hasLiveTarget = player != null && (playerHealth == null || !playerHealth.IsDead);

        TickContactDamage(delta, hasLiveTarget);

        switch (State)
        {
            case BossState.Chase:
                ProcessChase(delta, player, hasLiveTarget);
                break;
            case BossState.Windup:
                ProcessWindup(delta, player, hasLiveTarget);
                break;
            case BossState.Recover:
                ProcessRecover(delta, player, hasLiveTarget);
                break;
        }

        MoveAndSlide();
    }

    protected virtual void ProcessChase(double delta, Node2D player, bool hasLiveTarget)
    {
        if (hasLiveTarget)
        {
            float speed = Data.MoveSpeed * GetPhaseMoveMultiplier();
            Velocity = (player.GlobalPosition - GlobalPosition).Normalized() * speed;
        }
        else
        {
            Velocity = Vector2.Zero;
        }

        AttackCooldownRemaining -= delta;
        if (hasLiveTarget && AttackCooldownRemaining <= 0)
        {
            TryBeginAttack(player);
        }
    }

    protected virtual void ProcessWindup(double delta, Node2D player, bool hasLiveTarget)
    {
        // Hold still while casting so telegraphs stay readable.
        Velocity = Vector2.Zero;
        WindupRemaining -= delta;
        if (WindupRemaining > 0)
        {
            return;
        }

        float recovery = PendingAttack?.RecoverySeconds ?? 0.25f;
        if (PendingAttack != null)
        {
            RememberAttackCooldown(PendingAttack);
            if (hasLiveTarget)
            {
                ExecuteAttack(PendingAttack, player);
            }
        }

        PendingAttack = null;
        ActiveTelegraph = null;
        State = BossState.Recover;
        RecoverRemaining = recovery;
    }

    protected virtual void ProcessRecover(double delta, Node2D player, bool hasLiveTarget)
    {
        Velocity = Vector2.Zero;
        RecoverRemaining -= delta;
        if (RecoverRemaining > 0)
        {
            return;
        }

        State = BossState.Chase;
        AttackCooldownRemaining = GetNextAttackCooldown();
    }

    protected virtual void TryBeginAttack(Node2D player)
    {
        BossAttackPatternData attack = PickAttack();
        if (attack == null)
        {
            AttackCooldownRemaining = 1.0;
            return;
        }

        PendingAttack = attack;
        WindupRemaining = Mathf.Max(0.05f, attack.WindupSeconds);
        State = BossState.Windup;
        Velocity = Vector2.Zero;

        BeginTelegraph(attack, player);
    }

    /// <summary>
    /// Default telegraph: red AoE on the player (or self for self-centered attacks).
    /// Subclasses may override for multi-zone / custom previews. DealDamageOnComplete is false
    /// so ExecuteAttack owns the real hit (avoids double damage).
    /// </summary>
    protected virtual void BeginTelegraph(BossAttackPatternData attack, Node2D player)
    {
        if (attack == null || player == null)
        {
            return;
        }

        string id = attack.AttackId ?? "";
        // Summons / blinks flash at boss; most AoEs telegraph on player.
        bool selfCentered = id is "bat_swarm" or "summon_ghouls" or "summon_cultists" or "blink"
            or "heavy_melee" or "blood_slash";

        Vector2 pos = selfCentered ? GlobalPosition : player.GlobalPosition;
        float radius = Mathf.Max(24f, attack.Radius);

        // Blink has a short self flash only.
        if (id == "blink")
        {
            radius = 40f;
        }

        ActiveTelegraph = BossAoeTelegraph.Spawn(
            this,
            pos,
            radius,
            attack.WindupSeconds,
            Mathf.RoundToInt(attack.Damage),
            this,
            dealDamageOnComplete: false);
    }

    /// <summary>Boss-specific attack resolution. Override in subclasses.</summary>
    protected virtual void ExecuteAttack(BossAttackPatternData attack, Node2D player)
    {
        // Generic fallback: AoE at player feet.
        if (player != null && GlobalPosition.DistanceTo(player.GlobalPosition) <= attack.Radius + 16f)
        {
            ApplyDamageToPlayer(Mathf.RoundToInt(attack.Damage), attack.HealFraction);
        }
    }

    protected void ApplyDamageToPlayer(int damage, float healFraction = 0f)
    {
        Node2D player = GetTree().GetFirstNodeInGroup("Player") as Node2D;
        if (player == null)
        {
            return;
        }

        HealthComponent health = player.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health == null || health.IsDead)
        {
            return;
        }

        health.TakeDamage(damage, this);
        if (healFraction > 0f && Health != null && !Health.IsDead)
        {
            Health.Heal(Mathf.Max(1, Mathf.RoundToInt(damage * healFraction)));
        }
    }

    protected void ApplyDamageInRadius(Vector2 center, float radius, int damage, float healFraction = 0f)
    {
        Node2D player = GetTree().GetFirstNodeInGroup("Player") as Node2D;
        if (player == null || center.DistanceTo(player.GlobalPosition) > radius)
        {
            return;
        }

        ApplyDamageToPlayer(damage, healFraction);
    }

    protected BossAttackPatternData PickAttack()
    {
        BossPhaseData phase = GetCurrentPhase();
        if (phase?.Attacks == null || phase.Attacks.Length == 0)
        {
            return null;
        }

        int index = (int)(GD.Randi() % (uint)phase.Attacks.Length);
        return phase.Attacks[index];
    }

    protected BossPhaseData GetCurrentPhase()
    {
        if (Data?.Phases == null || Data.Phases.Length == 0)
        {
            return null;
        }

        CurrentPhaseIndex = Mathf.Clamp(CurrentPhaseIndex, 0, Data.Phases.Length - 1);
        return Data.Phases[CurrentPhaseIndex];
    }

    protected float GetPhaseMoveMultiplier()
    {
        return GetCurrentPhase()?.MoveSpeedMultiplier ?? 1f;
    }

    protected float GetPhaseCooldownMultiplier()
    {
        return GetCurrentPhase()?.AttackCooldownMultiplier ?? 1f;
    }

    private float _lastUsedCooldown = 2.5f;

    protected float GetNextAttackCooldown()
    {
        float baseCd = _lastUsedCooldown;
        BossPhaseData phase = GetCurrentPhase();
        if (phase?.Attacks is { Length: > 0 })
        {
            // Prefer the last attack's cooldown; fall back to the phase's fastest attack.
            baseCd = _lastUsedCooldown;
            float minCd = phase.Attacks[0].CooldownSeconds;
            for (int i = 1; i < phase.Attacks.Length; i++)
            {
                minCd = Mathf.Min(minCd, phase.Attacks[i].CooldownSeconds);
            }

            if (baseCd <= 0f)
            {
                baseCd = minCd;
            }
        }

        return Mathf.Max(0.35f, baseCd * GetPhaseCooldownMultiplier() * (float)GD.RandRange(0.85, 1.15));
    }

    protected void RememberAttackCooldown(BossAttackPatternData attack)
    {
        if (attack != null)
        {
            _lastUsedCooldown = attack.CooldownSeconds;
        }
    }

    protected void UpdatePhaseFromHealth()
    {
        if (Data?.Phases == null || Data.Phases.Length <= 1 || Health == null || Health.MaxHealth <= 0)
        {
            return;
        }

        float fraction = (float)Health.CurrentHealth / Health.MaxHealth;
        int newPhase = 0;
        for (int i = 0; i < Data.Phases.Length; i++)
        {
            BossPhaseData phase = Data.Phases[i];
            if (phase == null)
            {
                continue;
            }

            // Phase 0 always qualifies; later phases unlock when HP is at or below threshold.
            if (i == 0 || fraction <= phase.EnterHpFraction)
            {
                newPhase = i;
            }
        }

        if (newPhase != CurrentPhaseIndex)
        {
            int previous = CurrentPhaseIndex;
            CurrentPhaseIndex = newPhase;
            OnPhaseEntered(CurrentPhaseIndex, previous);
        }
    }

    protected virtual void OnPhaseEntered(int phaseIndex, int previousPhaseIndex = -1)
    {
        BossPhaseData phase = GetCurrentPhase();
        if (phase != null)
        {
            GD.Print($"[Boss] {Data?.BossName} entered {phase.PhaseName} (index {phaseIndex}).");
        }
    }

    protected void TickContactDamage(double delta, bool hasLiveTarget)
    {
        if (!hasLiveTarget || ContactHitbox == null || Data == null)
        {
            return;
        }

        ContactCooldownRemaining -= delta;
        if (ContactCooldownRemaining > 0)
        {
            return;
        }

        foreach (Node2D body in ContactHitbox.GetOverlappingBodies())
        {
            if (!body.IsInGroup("Player"))
            {
                continue;
            }

            HealthComponent health = body.GetNodeOrNull<HealthComponent>("HealthComponent");
            if (health == null || health.IsDead)
            {
                continue;
            }

            health.TakeDamage(Mathf.RoundToInt(Data.ContactDamage), this);
            ContactCooldownRemaining = Data.ContactDamageCooldown;
            break;
        }
    }

    /// <summary>
    /// Spawns a lightweight Enemy minion from Enemy.tscn with runtime EnemyData.
    /// Tracks it for cleanup; frees on minion death (Enemy pool is null).
    /// </summary>
    protected Enemy SpawnMinion(Vector2 globalPosition, string name, Color color, int maxHealth, float moveSpeed,
        float attackDamage, float attackCooldown = 1.0f)
    {
        if (EnemyScene == null)
        {
            return null;
        }

        var data = new EnemyData
        {
            EnemyName = name,
            SpriteColor = color,
            MaxHealth = maxHealth,
            MoveSpeed = moveSpeed,
            AttackDamage = attackDamage,
            AttackPattern = EnemyAttackPattern.Melee,
            BehaviorType = EnemyBehaviorType.Chase,
            AggroRange = 900f,
            AttackRange = 36f,
            AttackCooldown = attackCooldown,
            CurrencyReward = 1,
            ExperienceReward = 1,
            IsUndead = true
        };

        Enemy enemy = EnemyScene.Instantiate<Enemy>();
        Node parent = GetTree()?.CurrentScene ?? GetParent();
        parent.AddChild(enemy);
        enemy.GlobalPosition = globalPosition;
        enemy.Initialize(data, null);

        HealthComponent minionHealth = enemy.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (minionHealth != null)
        {
            minionHealth.Died += _ =>
            {
                if (GodotObject.IsInstanceValid(enemy))
                {
                    enemy.QueueFree();
                }

                SpawnedMinions.Remove(enemy);
            };
        }

        SpawnedMinions.Add(enemy);
        return enemy;
    }

    protected virtual void OnHealthChanged(int currentHealth, int maxHealth)
    {
        // Subclasses may react (UI hooks later).
    }

    protected virtual void OnDied(Node source)
    {
        State = BossState.Dead;
        Velocity = Vector2.Zero;
        FreeMinions();

        int currency = Data?.CurrencyReward ?? 0;
        int xp = Data?.ExperienceReward ?? 0;
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnEnemyKilled, this, currency, xp);
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnBossEncounterEnd, Data?.BossName ?? Name, true);

        // Brief death hold then free — BossManager also listens to OnBossEncounterEnd.
        // Cannot use ?. on CreateTimer().Timeout — C# events need a firm left-hand target.
        SceneTree tree = GetTree();
        if (tree != null)
        {
            tree.CreateTimer(0.6f).Timeout += () =>
            {
                if (GodotObject.IsInstanceValid(this))
                {
                    QueueFree();
                }
            };
        }
    }

    public override void _ExitTree()
    {
        FreeMinions();
        base._ExitTree();
    }

    /// <summary>Despawns adds (bats/ghouls/cultists) owned by this fight.</summary>
    public void FreeMinions()
    {
        foreach (Node minion in SpawnedMinions)
        {
            if (GodotObject.IsInstanceValid(minion))
            {
                minion.QueueFree();
            }
        }

        SpawnedMinions.Clear();
    }
}
