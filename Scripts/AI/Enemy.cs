using Godot;
using Nightbane.Autoloads;
using Nightbane.Combat;
using Nightbane.Core;
using Nightbane.Resources;

namespace Nightbane.AI;

/// <summary>
/// Generic enemy actor entirely driven by an injected EnemyData — there is no per-archetype
/// scene or script. WaveManager pulls one of these from an ObjectPool&lt;Enemy&gt; and calls
/// Initialize(data, pool) to (re)arm it as whatever archetype the wave rolled.
///
/// State machine (see EnemyState below): Wander (idle roam, no target in range) -> Chase
/// (closing distance) -> Attack (in range, standing/attacking) with an optional Flee state
/// for kiting ranged archetypes (EnemyBehaviorType.Flee) that back off once the player gets
/// closer than EnemyData.PreferredDistance. Attack execution itself is decoupled from the
/// movement state — an enemy can attack while in Flee (kiting) as long as it's within range.
/// </summary>
public partial class Enemy : CharacterBody2D, IPoolable
{
    private enum EnemyState
    {
        Wander,
        Chase,
        Attack,
        Flee
    }

    /// <summary>World physics layer bit (layer 1) — restored when an enemy is not a phasing unit.</summary>
    private const uint WorldCollisionMask = 1u;

    [Export] public EnemyData Data { get; set; }

    [ExportGroup("Wiring")]
    [Export] public NodePath HealthComponentPath { get; set; }
    [Export] public NodePath SpriteNodePath { get; set; }
    [Export] public NodePath CollisionShapePath { get; set; }
    /// <summary>Area2D whose overlap defines melee attack reach. Required for AttackPattern.Melee.</summary>
    [Export] public NodePath ContactHitboxPath { get; set; }
    /// <summary>Where ranged attacks spawn from (muzzle). Defaults to this node's position.</summary>
    [Export] public NodePath ProjectileSpawnPointPath { get; set; }

    [ExportGroup("Wander")]
    [Export] public float WanderSpeedScale { get; set; } = 0.4f;
    [Export] public float WanderRadius { get; set; } = 150f;
    [Export] public float WanderRepickSeconds { get; set; } = 3f;

    private HealthComponent _health;
    private Polygon2D _sprite;
    private CollisionShape2D _collisionShape;
    private Area2D _contactHitbox;
    private Node2D _projectileSpawnPoint;
    private ObjectPool<Enemy> _pool;
    private ObjectPool<Projectile> _projectilePool;

    private EnemyState _state = EnemyState.Wander;
    private Vector2 _spawnOrigin;
    private Vector2 _wanderTarget;
    private double _wanderRepickRemaining;
    private double _attackCooldownRemaining;

    /// <summary>Movement-speed multiplier from an active slow/root effect (Frost Lantern, Iron Bear
    /// Trap); 1 = unaffected, 0 = fully rooted. Decays back to 1 in _PhysicsProcess.</summary>
    private float _speedMultiplier = 1f;
    private double _speedModifierRemaining;

    // Runtime stats after wave scaling / elite buffs (Data fields stay as archetype baselines).
    private float _runtimeMoveSpeed;
    private float _runtimeAttackDamage;
    private float _runtimeExplosionDamage;
    private bool _isElite;

    // Erratic chase: periodic lateral bias so wraiths don't bee-line.
    private float _erraticStrafeSign = 1f;
    private double _erraticRepickRemaining;

    public override void _Ready()
    {
        AddToGroup("Enemy");

        _health = GetNodeOrNull<HealthComponent>(HealthComponentPath);
        _sprite = GetNodeOrNull<Polygon2D>(SpriteNodePath);
        _collisionShape = GetNodeOrNull<CollisionShape2D>(CollisionShapePath);
        _contactHitbox = GetNodeOrNull<Area2D>(ContactHitboxPath);
        _projectileSpawnPoint = GetNodeOrNull<Node2D>(ProjectileSpawnPointPath) ?? this;

        if (_health != null)
        {
            _health.Died += OnDied;
        }
        else
        {
            GD.PushWarning("[Enemy] HealthComponentPath not wired; enemy cannot die.");
        }
    }

    /// <summary>(Re)arms this pooled instance as the given archetype. Called by WaveManager right after ObjectPool.Get().</summary>
    public void Initialize(EnemyData data, ObjectPool<Enemy> pool)
    {
        Data = data;
        _pool = pool;
        _spawnOrigin = GlobalPosition;
        _isElite = false;

        _runtimeMoveSpeed = data.MoveSpeed;
        _runtimeAttackDamage = data.AttackDamage;
        _runtimeExplosionDamage = data.ExplosionDamage;

        if (_health != null)
        {
            _health.MaxHealth = data.MaxHealth;
            _health.Revive(data.MaxHealth);
        }

        ApplyVisualDefaults(data);
        ApplyPhasing(data.PhasesThroughObstacles);

        _state = EnemyState.Wander;
        _wanderTarget = _spawnOrigin;
        _wanderRepickRemaining = 0;
        _attackCooldownRemaining = data.AttackCooldown;
        _speedMultiplier = 1f;
        _speedModifierRemaining = 0;
        _erraticStrafeSign = GD.Randf() < 0.5f ? -1f : 1f;
        _erraticRepickRemaining = 0;
        Velocity = Vector2.Zero;
        Scale = Vector2.One;
    }

    /// <summary>
    /// Applies wave-number HP/damage/speed multipliers and optional elite buff + recolor.
    /// Called by WaveManager immediately after Initialize at the spawn site.
    /// </summary>
    public void ApplySpawnModifiers(int waveNumber, bool isElite)
    {
        if (Data == null)
        {
            return;
        }

        float hpMul = EnemyScaling.HealthMultiplier(waveNumber);
        float dmgMul = EnemyScaling.DamageMultiplier(waveNumber);
        float spdMul = EnemyScaling.SpeedMultiplier(waveNumber);

        _isElite = isElite;
        if (isElite)
        {
            hpMul *= EnemyScaling.EliteHealthMultiplier;
            dmgMul *= EnemyScaling.EliteDamageMultiplier;
            spdMul *= EnemyScaling.EliteSpeedMultiplier;
        }

        _runtimeMoveSpeed = Data.MoveSpeed * spdMul;
        _runtimeAttackDamage = Data.AttackDamage * dmgMul;
        _runtimeExplosionDamage = Data.ExplosionDamage * dmgMul;

        if (_health != null)
        {
            int maxHp = Mathf.Max(1, Mathf.RoundToInt(Data.MaxHealth * hpMul));
            _health.MaxHealth = maxHp;
            _health.Revive(maxHp);
        }

        ApplyEliteVisual(isElite);
    }

    /// <summary>Applies a temporary movement-speed multiplier (0 = rooted, 1 = unaffected) — used by
    /// Frost Lantern's slow and Iron Bear Trap's root. Whichever effect is currently strongest wins
    /// the multiplier, while durations extend rather than stack, so re-slowing an already-rooted
    /// enemy just refreshes the root instead of making it weaker.</summary>
    public void ApplyMovementModifier(float multiplier, float durationSeconds)
    {
        multiplier = Mathf.Clamp(multiplier, 0f, 1f);
        if (_speedModifierRemaining <= 0 || multiplier <= _speedMultiplier)
        {
            _speedMultiplier = multiplier;
        }
        _speedModifierRemaining = Mathf.Max(_speedModifierRemaining, durationSeconds);
    }

    public override void _PhysicsProcess(double delta)
    {
        if (Data == null || _health == null || _health.IsDead)
        {
            Velocity = Vector2.Zero;
            MoveAndSlide();
            return;
        }

        Node2D player = GetTree().GetFirstNodeInGroup("Player") as Node2D;
        HealthComponent playerHealth = player?.GetNodeOrNull<HealthComponent>("HealthComponent");
        bool hasLiveTarget = player != null && (playerHealth == null || !playerHealth.IsDead);

        if (_speedModifierRemaining > 0)
        {
            _speedModifierRemaining -= delta;
            if (_speedModifierRemaining <= 0)
            {
                _speedModifierRemaining = 0;
                _speedMultiplier = 1f;
            }
        }

        float distanceToPlayer = hasLiveTarget
            ? GlobalPosition.DistanceTo(player.GlobalPosition)
            : float.MaxValue;
        UpdateState(hasLiveTarget, distanceToPlayer);
        Move(delta, player, distanceToPlayer);

        // Attacking is independent of movement state so kiting (Flee) archetypes can still
        // shoot while backing away — only the in-range check gates it.
        _attackCooldownRemaining -= delta;
        if (hasLiveTarget && distanceToPlayer <= Data.AttackRange && _attackCooldownRemaining <= 0)
        {
            PerformAttack(player);
            _attackCooldownRemaining = Data.AttackCooldown;
        }
    }

    /// <summary>
    /// Wave-survival AI: while a live player exists, always engage (Chase/Attack/Flee).
    /// Wander only when no target — AggroRange used to strand enemies that spawned just outside it.
    /// </summary>
    private void UpdateState(bool hasLiveTarget, float distanceToPlayer)
    {
        if (!hasLiveTarget)
        {
            _state = EnemyState.Wander;
            return;
        }

        if (Data.BehaviorType == EnemyBehaviorType.Flee
            && Data.PreferredDistance > 0f
            && distanceToPlayer < Data.PreferredDistance)
        {
            _state = EnemyState.Flee;
        }
        else if (distanceToPlayer <= Data.AttackRange)
        {
            _state = EnemyState.Attack;
        }
        else
        {
            _state = EnemyState.Chase;
        }
    }

    private void Move(double delta, Node2D player, float distanceToPlayer)
    {
        switch (_state)
        {
            case EnemyState.Chase:
                Velocity = ChaseVelocity(delta, player) * _speedMultiplier;
                break;
            case EnemyState.Flee:
                Velocity = (GlobalPosition - player.GlobalPosition).Normalized() * _runtimeMoveSpeed * _speedMultiplier;
                break;
            case EnemyState.Attack:
                Velocity = Vector2.Zero;
                break;
            case EnemyState.Wander:
            default:
                Velocity = WanderMovement(delta) * _speedMultiplier;
                break;
        }

        MoveAndSlide();
    }

    /// <summary>Straight chase, or jitter-strafe when EnemyData.ErraticMovement is set (Wraith).</summary>
    private Vector2 ChaseVelocity(double delta, Node2D player)
    {
        Vector2 toward = (player.GlobalPosition - GlobalPosition).Normalized();
        if (!Data.ErraticMovement)
        {
            return toward * _runtimeMoveSpeed;
        }

        _erraticRepickRemaining -= delta;
        if (_erraticRepickRemaining <= 0)
        {
            _erraticStrafeSign = GD.Randf() < 0.5f ? -1f : 1f;
            _erraticRepickRemaining = GD.RandRange(0.35, 0.9);
        }

        Vector2 lateral = toward.Rotated(Mathf.Pi * 0.5f * _erraticStrafeSign);
        // Blend forward + lateral so path zig-zags without abandoning the player.
        Vector2 dir = (toward * 0.65f + lateral * 0.75f).Normalized();
        return dir * _runtimeMoveSpeed;
    }

    /// <summary>Idle roam: picks a random point within WanderRadius of the spawn origin and ambles toward it, repicking periodically or on arrival.</summary>
    private Vector2 WanderMovement(double delta)
    {
        _wanderRepickRemaining -= delta;
        bool reachedTarget = GlobalPosition.DistanceSquaredTo(_wanderTarget) < 16f * 16f;

        // Erratic units repick wander targets more often so idle motion stays twitchy.
        float repickSeconds = Data.ErraticMovement ? WanderRepickSeconds * 0.45f : WanderRepickSeconds;

        if (_wanderRepickRemaining <= 0 || reachedTarget)
        {
            Vector2 offset = new Vector2(WanderRadius, 0).Rotated((float)GD.RandRange(0.0, Mathf.Tau)) * (float)GD.RandRange(0.2, 1.0);
            _wanderTarget = _spawnOrigin + offset;
            _wanderRepickRemaining = repickSeconds;
        }

        return (_wanderTarget - GlobalPosition).Normalized() * _runtimeMoveSpeed * WanderSpeedScale;
    }

    private void PerformAttack(Node2D player)
    {
        if (Data.AttackPattern == EnemyAttackPattern.Melee)
        {
            PerformMeleeAttack();
        }
        else
        {
            FireProjectileAt(player);
        }
    }

    /// <summary>Damages every live Player-group body currently overlapping the contact hitbox.</summary>
    private void PerformMeleeAttack()
    {
        if (_contactHitbox == null)
        {
            return;
        }

        foreach (Node2D body in _contactHitbox.GetOverlappingBodies())
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

            health.TakeDamage(Mathf.RoundToInt(_runtimeAttackDamage), this);
        }
    }

    private void FireProjectileAt(Node2D player)
    {
        if (Data.ProjectileScene == null)
        {
            return;
        }

        // Lazily built per-instance so a pooled Enemy re-armed as a different archetype
        // (different ProjectileScene) never reuses another archetype's pool.
        _projectilePool ??= new ObjectPool<Projectile>(Data.ProjectileScene, GetTree().CurrentScene ?? GetParent(), 4);

        Vector2 spawnPos = _projectileSpawnPoint.GlobalPosition;
        Vector2 direction = (player.GlobalPosition - spawnPos).Normalized();

        Projectile projectile = _projectilePool.Get();
        projectile.Launch(spawnPos, direction, _projectilePool, this, _runtimeAttackDamage, 0f, 1f, 0f, "Player");
    }

    private void OnDied(Node source)
    {
        if (Data != null && Data.ExplodeOnDeath)
        {
            DetonateDeathExplosion();
        }

        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnEnemyKilled, this, Data?.CurrencyReward ?? 0, Data?.ExperienceReward ?? 0);
        _pool?.Return(this);
    }

    /// <summary>
    /// AoE death burst (Bloated Corpse): damages every live Player/Enemy HealthComponent in radius,
    /// excluding self. Uses group scan so wall-phasing layers don't gate the blast.
    /// </summary>
    private void DetonateDeathExplosion()
    {
        float radius = Data.ExplosionRadius;
        float radiusSq = radius * radius;
        int damage = Mathf.Max(1, Mathf.RoundToInt(_runtimeExplosionDamage));

        DamageGroupInRadius("Player", radiusSq, damage);
        DamageGroupInRadius("Enemy", radiusSq, damage);
    }

    private void DamageGroupInRadius(string groupName, float radiusSq, int damage)
    {
        var tree = GetTree();
        if (tree == null)
        {
            return;
        }

        foreach (Node node in tree.GetNodesInGroup(groupName))
        {
            if (node == this || node is not Node2D body)
            {
                continue;
            }

            if (GlobalPosition.DistanceSquaredTo(body.GlobalPosition) > radiusSq)
            {
                continue;
            }

            HealthComponent health = body.GetNodeOrNull<HealthComponent>("HealthComponent");
            if (health == null || health.IsDead)
            {
                continue;
            }

            health.TakeDamage(damage, this);
        }
    }

    private void ApplyVisualDefaults(EnemyData data)
    {
        Modulate = Colors.White;
        Scale = Vector2.One;

        if (_sprite != null)
        {
            _sprite.Color = data.SpriteColor;
        }
    }

    /// <summary>Elite recolor: red-leaning tint + slight scale + bright modulate for "red eye glow".</summary>
    private void ApplyEliteVisual(bool isElite)
    {
        if (!isElite || Data == null)
        {
            ApplyVisualDefaults(Data);
            return;
        }

        Scale = Vector2.One * 1.18f;
        // Warm/reddish overall glow so elites read at a glance in a pack.
        Modulate = new Color(1.45f, 0.75f, 0.7f, 1f);

        if (_sprite != null)
        {
            Color baseColor = Data.SpriteColor;
            // Pull hue toward blood-red while preserving some archetype identity.
            _sprite.Color = baseColor.Lerp(new Color(0.95f, 0.12f, 0.08f, baseColor.A), 0.55f);
        }
    }

    /// <summary>
    /// Wraiths clear World from collision_mask so they phase through arena walls/obstacles.
    /// Non-phasers restore the default World mask for pooled reuse safety.
    /// </summary>
    private void ApplyPhasing(bool phases)
    {
        CollisionMask = phases ? 0u : WorldCollisionMask;
    }

    public void OnSpawn()
    {
        Visible = true;
        // Ensure both process modes are on — pooled nodes may have been fully frozen.
        SetPhysicsProcess(true);
        SetProcess(true);
        ProcessMode = ProcessModeEnum.Inherit;

        // Re-enable body collision so weapons/projectiles can hit (layer 3 / bit value 4).
        CollisionLayer = 4;
        if (_collisionShape != null)
        {
            _collisionShape.Disabled = false;
            _collisionShape.SetDeferred(CollisionShape2D.PropertyName.Disabled, false);
        }

        if (_contactHitbox != null)
        {
            _contactHitbox.Monitoring = true;
            _contactHitbox.Monitorable = true;
        }
    }

    public void OnDespawn()
    {
        Visible = false;
        Velocity = Vector2.Zero;
        SetPhysicsProcess(false);
        SetProcess(false);
        _isElite = false;
        Modulate = Colors.White;
        Scale = Vector2.One;
        // Reset phasing so a recycled wraith doesn't leave a non-wraith phaseable.
        CollisionMask = WorldCollisionMask;
        CollisionLayer = 4;

        if (_collisionShape != null)
        {
            _collisionShape.Disabled = true;
        }

        if (_contactHitbox != null)
        {
            _contactHitbox.Monitoring = false;
            _contactHitbox.Monitorable = false;
        }
    }
}
