using Godot;

namespace Nightbane.Resources;

/// <summary>How an enemy delivers its damage. Drives the branch in Enemy.cs's attack execution.</summary>
public enum EnemyAttackPattern
{
    Melee,
    Ranged
}

/// <summary>
/// High-level combat approach tag consumed by Enemy.cs's state machine to decide how it
/// closes/holds distance. Chase/Attack are melee-style (walk in, stop in range, swing).
/// Wander is the idle/no-target roam state. Flee marks kiting ranged units that back off
/// once the player gets closer than PreferredDistance while still attacking in range.
/// </summary>
public enum EnemyBehaviorType
{
    Chase,
    Wander,
    Attack,
    Flee
}

/// <summary>Data-driven definition for a regular (non-boss) enemy archetype.</summary>
[GlobalClass]
public partial class EnemyData : Resource
{
    [Export] public string EnemyName { get; set; } = "Ghoul";
    /// <summary>Always the generic Enemy.tscn — one scene driven entirely by this Resource.</summary>
    [Export] public PackedScene EnemyScene { get; set; }
    /// <summary>Placeholder tint applied to the enemy's Sprite so archetypes read as visually distinct.</summary>
    [Export] public Color SpriteColor { get; set; } = new Color(0.4f, 0.55f, 0.35f, 1f);

    [ExportGroup("Combat Stats")]
    [Export] public int MaxHealth { get; set; } = 20;
    /// <summary>Feeds character passives that key off enemy type (e.g. Silver Priest's bonus vs undead).
    /// Defaults true since most current archetypes (ghouls, skeletons) already are.</summary>
    [Export] public bool IsUndead { get; set; } = true;
    [Export] public float MoveSpeed { get; set; } = 80f;
    [Export] public float AttackDamage { get; set; } = 5f;
    [Export] public EnemyAttackPattern AttackPattern { get; set; } = EnemyAttackPattern.Melee;
    [Export] public EnemyBehaviorType BehaviorType { get; set; } = EnemyBehaviorType.Chase;
    /// <summary>For Ranged enemies: pooled projectile scene fired via the shared Projectile.cs. Unused for Melee.</summary>
    [Export] public PackedScene ProjectileScene { get; set; }

    [ExportGroup("AI Ranges")]
    /// <summary>Distance at which an idle (Wander) enemy notices the player and starts chasing.</summary>
    [Export] public float AggroRange { get; set; } = 500f;
    /// <summary>Distance at which the enemy stops closing and enters its Attack state.</summary>
    [Export] public float AttackRange { get; set; } = 40f;
    /// <summary>Flee-only: if the player gets closer than this, the enemy backs away while still attacking. 0 disables fleeing.</summary>
    [Export] public float PreferredDistance { get; set; } = 0f;
    [Export] public float AttackCooldown { get; set; } = 1.0f;

    [ExportGroup("Death Effects")]
    /// <summary>When true, OnDied detonates an AoE that hits Player + other Enemies via HealthComponent.</summary>
    [Export] public bool ExplodeOnDeath { get; set; } = false;
    [Export] public float ExplosionRadius { get; set; } = 90f;
    [Export] public float ExplosionDamage { get; set; } = 18f;

    [ExportGroup("Movement Traits")]
    /// <summary>When true, collision_mask ignores World layer so the unit phases through walls/obstacles.</summary>
    [Export] public bool PhasesThroughObstacles { get; set; } = false;
    /// <summary>When true, chase path jitter-strafes instead of walking a straight line.</summary>
    [Export] public bool ErraticMovement { get; set; } = false;

    [ExportGroup("Wave Spawning")]
    [Export] public int CurrencyReward { get; set; } = 1;
    [Export] public int ExperienceReward { get; set; } = 1;
    /// <summary>Relative weight used by WaveManager's weighted random spawn table.</summary>
    [Export] public float SpawnWeight { get; set; } = 1f;
    [Export] public int MinWaveToAppear { get; set; } = 1;
}
