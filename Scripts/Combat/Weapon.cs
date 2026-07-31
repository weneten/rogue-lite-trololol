using Godot;
using Nightbane.AI;
using Nightbane.Autoloads;
using Nightbane.Core;
using Nightbane.PlayerCharacter;
using Nightbane.Resources;

namespace Nightbane.Combat;

/// <summary>
/// Auto-attacking weapon slot attachable to Player (Brotato-style: no manual aim/fire input).
/// Every frame it looks for the nearest live member of TargetGroup within WeaponData.Range;
/// once found it rotates to face it and, on cooldown expiry, either runs a melee hitbox check
/// (WeaponClass.Melee) or spawns pooled Projectile(s) aimed at the target (everything else).
/// </summary>
public partial class Weapon : Node2D
{
    [Export] public WeaponData Data { get; set; }
    [Export] public string TargetGroup { get; set; } = "Enemy";

    [ExportGroup("Wiring")]
    /// <summary>Body this weapon is mounted on; distances/origin are measured from here. Defaults to the parent node.</summary>
    [Export] public NodePath OwnerBodyPath { get; set; }
    /// <summary>Area2D whose shape defines the melee swing reach. Required for Melee-class weapons.</summary>
    [Export] public NodePath MeleeHitboxPath { get; set; }
    /// <summary>Where projectiles spawn from (muzzle). Defaults to this node's position.</summary>
    [Export] public NodePath ProjectileSpawnPointPath { get; set; }

    [ExportGroup("Pooling")]
    [Export] public int ProjectilePoolPrewarm { get; set; } = 8;

    private Node2D _ownerBody;
    private Area2D _meleeHitbox;
    private Node2D _spawnPoint;
    private ObjectPool<Projectile> _projectilePool;
    private ObjectPool<Trap> _trapPool;
    /// <summary>Optional — only present when mounted on the Player. Non-player owners (none currently exist) just get a 1x multiplier.</summary>
    private PlayerStats _ownerStats;
    private HealthComponent _ownerHealth;

    private double _cooldownRemaining;

    public override void _Ready()
    {
        _ownerBody = GetNodeOrNull<Node2D>(OwnerBodyPath) ?? GetParent<Node2D>();
        _meleeHitbox = GetNodeOrNull<Area2D>(MeleeHitboxPath);
        _spawnPoint = GetNodeOrNull<Node2D>(ProjectileSpawnPointPath) ?? this;
        _ownerStats = _ownerBody?.GetNodeOrNull<PlayerStats>("PlayerStats");
        _ownerHealth = _ownerBody?.GetNodeOrNull<HealthComponent>("HealthComponent");

        if (Data == null)
        {
            GD.PushWarning("[Weapon] No WeaponData assigned; weapon is inert.");
            return;
        }

        bool isMelee = Data.WeaponClass.HasFlag(WeaponClass.Melee);
        bool isSummon = Data.WeaponClass.HasFlag(WeaponClass.Summon);
        bool isTrap = Data.WeaponClass.HasFlag(WeaponClass.Trap);

        if (isMelee && _meleeHitbox == null)
        {
            GD.PushWarning($"[Weapon] '{Data.Name}' is Melee but MeleeHitboxPath is unwired; it will never deal damage.");
        }
        if (!isMelee && !isSummon && !isTrap && Data.ProjectileScene != null)
        {
            _projectilePool = new ObjectPool<Projectile>(Data.ProjectileScene, GetTree().CurrentScene, ProjectilePoolPrewarm);
        }
        if (isTrap && Data.TrapScene != null)
        {
            _trapPool = new ObjectPool<Trap>(Data.TrapScene, GetTree().CurrentScene, 2);
        }
        if (isSummon && Data.SummonScene != null)
        {
            SpawnFamiliar();
        }
    }

    public override void _Process(double delta)
    {
        if (Data == null || _ownerBody == null)
        {
            return;
        }

        // Summon-class weapons spawn an independent Familiar in _Ready and never attack directly
        // themselves — the Familiar tracks/fires on its own timer, so this node has nothing left to do.
        if (Data.WeaponClass.HasFlag(WeaponClass.Summon))
        {
            return;
        }

        _cooldownRemaining -= delta;

        Node2D target = FindNearestTarget();
        if (target == null)
        {
            return;
        }

        // Face the target regardless of cooldown so the weapon visibly tracks its target.
        GlobalRotation = (target.GlobalPosition - _ownerBody.GlobalPosition).Angle();

        if (_cooldownRemaining > 0)
        {
            return;
        }

        Attack(target);
        _cooldownRemaining = 1.0 / Mathf.Max(0.01f, Data.AttackSpeed * (_ownerStats?.AttackSpeedMultiplier ?? 1f));
    }

    /// <summary>Nearest live TargetGroup member within Data.Range, or null if none in range.</summary>
    private Node2D FindNearestTarget()
    {
        Node2D nearest = null;
        float nearestDistSq = Data.Range * Data.Range;

        foreach (Node node in GetTree().GetNodesInGroup(TargetGroup))
        {
            if (node is not Node2D candidate)
            {
                continue;
            }

            HealthComponent health = candidate.GetNodeOrNull<HealthComponent>("HealthComponent");
            if (health != null && health.IsDead)
            {
                continue;
            }

            float distSq = _ownerBody.GlobalPosition.DistanceSquaredTo(candidate.GlobalPosition);
            if (distSq <= nearestDistSq)
            {
                nearestDistSq = distSq;
                nearest = candidate;
            }
        }

        return nearest;
    }

    private void Attack(Node2D target)
    {
        AudioManager.Instance?.PlaySfx(ResolveWeaponHitSfxId());

        // Order matters: Trap pre-empts everything (it never attacks directly), Melee handles its
        // own cleave via the hitbox overlap even when also flagged AoE (War Cleaver), and pure AoE
        // (no Melee) gets the radius-burst path; anything left over fires a projectile.
        if (Data.WeaponClass.HasFlag(WeaponClass.Trap))
        {
            PlaceTrap();
        }
        else if (Data.WeaponClass.HasFlag(WeaponClass.Melee))
        {
            PerformMeleeAttack();
        }
        else if (Data.WeaponClass.HasFlag(WeaponClass.AoE))
        {
            PerformAreaAttack(target);
        }
        else
        {
            FireProjectiles(target);
        }
    }

    /// <summary>Maps WeaponClass flags to an SFX id (first matching class wins).</summary>
    private string ResolveWeaponHitSfxId()
    {
        WeaponClass c = Data.WeaponClass;
        if (c.HasFlag(WeaponClass.Trap)) return "weapon_trap";
        if (c.HasFlag(WeaponClass.Melee)) return "weapon_melee";
        if (c.HasFlag(WeaponClass.Firearm)) return "weapon_firearm";
        if (c.HasFlag(WeaponClass.Magic)) return "weapon_magic";
        if (c.HasFlag(WeaponClass.Holy)) return "weapon_holy";
        if (c.HasFlag(WeaponClass.Cursed)) return "weapon_cursed";
        if (c.HasFlag(WeaponClass.AoE)) return "weapon_aoe";
        if (c.HasFlag(WeaponClass.Summon)) return "weapon_summon";
        if (c.HasFlag(WeaponClass.Ranged)) return "weapon_ranged";
        return "weapon_hit";
    }

    /// <summary>
    /// Brotato-style melee: damage every live TargetGroup member within WeaponData.Range.
    /// Hitbox overlap alone was too small vs Range, so weapons "swung" without landing hits.
    /// </summary>
    private void PerformMeleeAttack()
    {
        if (_ownerBody == null || Data == null)
        {
            return;
        }

        float range = Mathf.Max(8f, Data.Range);
        float rangeSq = range * range;
        Vector2 origin = _ownerBody.GlobalPosition;

        // Prefer hitbox overlaps when present (multi-target cleave geometry), then fill gaps
        // with a pure distance check so nothing inside Range is immune.
        var hitIds = new System.Collections.Generic.HashSet<ulong>();

        if (_meleeHitbox != null)
        {
            foreach (Node2D body in _meleeHitbox.GetOverlappingBodies())
            {
                if (!body.IsInGroup(TargetGroup))
                {
                    continue;
                }

                if (TryDamageTarget(body))
                {
                    hitIds.Add(body.GetInstanceId());
                }
            }
        }

        foreach (Node node in GetTree().GetNodesInGroup(TargetGroup))
        {
            if (node is not Node2D body)
            {
                continue;
            }

            if (hitIds.Contains(body.GetInstanceId()))
            {
                continue;
            }

            if (origin.DistanceSquaredTo(body.GlobalPosition) > rangeSq)
            {
                continue;
            }

            TryDamageTarget(body);
        }
    }

    /// <summary>Applies one weapon hit (crit, mults, lifesteal, knockback). Returns false if skipped.</summary>
    private bool TryDamageTarget(Node2D body)
    {
        HealthComponent health = body.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health == null || health.IsDead)
        {
            return false;
        }

        float critChance = Data.CritChance + (_ownerStats?.ExtraCritChance ?? 0f);
        float critMultiplier = Data.CritMultiplier + (_ownerStats?.ExtraCritMultiplier ?? 0f);
        bool isCrit = GD.Randf() < critChance;

        float damageMultiplier = ComputeDamageMultiplier(body);
        int finalDamage = Mathf.Max(1, Mathf.RoundToInt(
            Data.Damage * damageMultiplier * (isCrit ? critMultiplier : 1f)));

        health.TakeDamage(finalDamage, _ownerBody);
        _ownerStats?.NotifyDamageDealt(finalDamage, body);
        ApplyOnHitLifesteal(finalDamage);

        if (body is TargetDummy dummy && Data.Knockback > 0f)
        {
            Vector2 pushDir = (dummy.GlobalPosition - _ownerBody.GlobalPosition).Normalized();
            dummy.ApplyKnockback(pushDir * Data.Knockback);
        }

        return true;
    }

    /// <summary>Spawns Data.ProjectileCount pooled projectiles fanned across Data.Spread degrees, aimed at target.</summary>
    private void FireProjectiles(Node2D target)
    {
        if (_projectilePool == null)
        {
            return;
        }

        Vector2 baseDirection = (target.GlobalPosition - _spawnPoint.GlobalPosition).Normalized();
        int count = Mathf.Max(1, Data.ProjectileCount);
        float spreadRad = Mathf.DegToRad(Data.Spread);

        float critChance = Data.CritChance + (_ownerStats?.ExtraCritChance ?? 0f);
        float critMultiplier = Data.CritMultiplier + (_ownerStats?.ExtraCritMultiplier ?? 0f);
        // Undead/Magic bonuses are resolved against the tracked target at fire time rather than
        // whatever the projectile actually collides with — an acceptable approximation since
        // projectiles fly straight at where the target was when fired.
        float damageMultiplier = ComputeDamageMultiplier(target);

        for (int i = 0; i < count; i++)
        {
            // Evenly fan projectiles across [-spread/2, +spread/2]; a single projectile fires straight.
            float t = count == 1 ? 0f : (float)i / (count - 1) - 0.5f;
            float angleOffset = spreadRad * t;
            Vector2 direction = baseDirection.Rotated(angleOffset);

            Projectile projectile = _projectilePool.Get();
            projectile.Launch(
                _spawnPoint.GlobalPosition,
                direction,
                _projectilePool,
                _ownerBody,
                Data.Damage * damageMultiplier,
                critChance,
                critMultiplier,
                Data.Knockback,
                TargetGroup,
                (dealt, hitBody) =>
                {
                    _ownerStats?.NotifyDamageDealt(dealt, hitBody);
                    ApplyOnHitLifesteal(dealt);
                });
        }
    }

    /// <summary>
    /// Radius burst used by pure WeaponClass.AoE weapons (Firebomb, Frost Lantern, Holy Water
    /// Flask, Bell of Judgement): damages every live TargetGroup member within AoERadius of either
    /// the current target (thrown weapons) or the wielder (self-centered pulses), and applies the
    /// weapon's slow if configured. Unlike melee cleave this isn't gated on a hitbox overlap, so it
    /// works for weapons with no travelling projectile at all.
    /// </summary>
    private void PerformAreaAttack(Node2D primaryTarget)
    {
        Vector2 origin = Data.AoECenteredOnSelf ? _ownerBody.GlobalPosition : primaryTarget.GlobalPosition;
        float radius = Data.AoERadius > 0f ? Data.AoERadius : Data.Range;
        float radiusSq = radius * radius;

        float critChance = Data.CritChance + (_ownerStats?.ExtraCritChance ?? 0f);
        float critMultiplier = Data.CritMultiplier + (_ownerStats?.ExtraCritMultiplier ?? 0f);

        foreach (Node node in GetTree().GetNodesInGroup(TargetGroup))
        {
            if (node is not Node2D body || origin.DistanceSquaredTo(body.GlobalPosition) > radiusSq)
            {
                continue;
            }

            HealthComponent health = body.GetNodeOrNull<HealthComponent>("HealthComponent");
            if (health == null || health.IsDead)
            {
                continue;
            }

            bool isCrit = GD.Randf() < critChance;
            float damageMultiplier = ComputeDamageMultiplier(body);
            int finalDamage = Mathf.RoundToInt(Data.Damage * damageMultiplier * (isCrit ? critMultiplier : 1f));
            health.TakeDamage(finalDamage, _ownerBody);
            _ownerStats?.NotifyDamageDealt(finalDamage, body);
            ApplyOnHitLifesteal(finalDamage);

            if (Data.SlowMultiplier > 0f && body is Enemy slowedEnemy)
            {
                slowedEnemy.ApplyMovementModifier(1f - Data.SlowMultiplier, Data.SlowDurationSeconds);
            }

            if (body is TargetDummy dummy && Data.Knockback > 0f)
            {
                Vector2 pushDir = (dummy.GlobalPosition - origin).Normalized();
                dummy.ApplyKnockback(pushDir * Data.Knockback);
            }
        }
    }

    /// <summary>Drops a pooled Trap at the wielder's feet (Iron Bear Trap); it sits armed until
    /// something in TargetGroup walks over it or TrapLifetimeSeconds elapses unused.</summary>
    private void PlaceTrap()
    {
        if (_trapPool == null)
        {
            return;
        }

        float critChance = Data.CritChance + (_ownerStats?.ExtraCritChance ?? 0f);
        float critMultiplier = Data.CritMultiplier + (_ownerStats?.ExtraCritMultiplier ?? 0f);
        float damageMultiplier = _ownerStats?.DamageMultiplier ?? 1f;

        Trap trap = _trapPool.Get();
        trap.Arm(
            _ownerBody.GlobalPosition,
            _trapPool,
            _ownerBody,
            Data.Damage * damageMultiplier,
            critChance,
            critMultiplier,
            TargetGroup,
            Data.TrapRootDurationSeconds,
            Data.TrapLifetimeSeconds,
            (dealt, hitBody) =>
            {
                _ownerStats?.NotifyDamageDealt(dealt, hitBody);
                ApplyOnHitLifesteal(dealt);
            });
    }

    /// <summary>Instantiates Data.SummonScene once as an independent scene-tree sibling (not a
    /// child of this Weapon, so it can roam freely) and hands it the owner/stats it needs to fight
    /// on its own. Called once from _Ready — buying a second copy of a Summon weapon spawns a
    /// second independent familiar, matching how every other weapon slot stacks.</summary>
    private void SpawnFamiliar()
    {
        Node2D familiar = Data.SummonScene.Instantiate<Node2D>();
        (GetTree().CurrentScene ?? GetParent()).AddChild(familiar);
        familiar.GlobalPosition = _ownerBody.GlobalPosition;

        if (familiar is Familiar familiarScript)
        {
            familiarScript.Setup(_ownerBody, Data, _ownerStats);
        }
    }

    /// <summary>Heals the wielder for Data.OnHitLifestealFraction of a landed hit (Vampiric Claws).
    /// Stacks additively with PlayerStats.LifestealFraction, which NotifyDamageDealt already applies.</summary>
    private void ApplyOnHitLifesteal(int damageDealt)
    {
        if (Data.OnHitLifestealFraction <= 0f)
        {
            return;
        }

        _ownerHealth?.Heal(Mathf.RoundToInt(damageDealt * Data.OnHitLifestealFraction));
    }

    /// <summary>Base DamageMultiplier plus the character-passive bonuses that only apply
    /// conditionally: MagicDamageMultiplier (+ this weapon's own MagicScalingPerPoint) for
    /// WeaponClass.Magic, CursedMissingHpScaling for WeaponClass.Cursed, and UndeadDamageMultiplier
    /// when the target is an EnemyData.IsUndead archetype.</summary>
    private float ComputeDamageMultiplier(Node2D target)
    {
        float multiplier = _ownerStats?.DamageMultiplier ?? 1f;

        if (Data.WeaponClass.HasFlag(WeaponClass.Magic))
        {
            float magicStat = _ownerStats?.MagicDamageMultiplier ?? 1f;
            multiplier *= magicStat;

            if (Data.MagicScalingPerPoint > 0f)
            {
                // Rewards magic-focused Hunters extra hard on weapons tuned for it, on top of the
                // flat MagicDamageMultiplier every Magic weapon already gets above.
                multiplier *= 1f + Data.MagicScalingPerPoint * Mathf.Max(0f, magicStat - 1f);
            }
        }

        if (Data.WeaponClass.HasFlag(WeaponClass.Cursed) && Data.CursedMissingHpScaling > 0f && _ownerHealth != null && _ownerHealth.MaxHealth > 0)
        {
            float missingHpFraction = 1f - (float)_ownerHealth.CurrentHealth / _ownerHealth.MaxHealth;
            multiplier *= 1f + Data.CursedMissingHpScaling * missingHpFraction;
        }

        if (target is Enemy enemy && enemy.Data != null && enemy.Data.IsUndead)
        {
            multiplier *= _ownerStats?.UndeadDamageMultiplier ?? 1f;
        }

        return multiplier;
    }
}
