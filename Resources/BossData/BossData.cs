using Godot;

namespace Nightbane.Resources;

/// <summary>
/// Data-driven definition for a boss encounter, triggered at a specific wave by BossManager.
/// Phases + per-phase attack patterns drive the boss AI state machine; BossScene points at the
/// concrete boss scene (script + placeholder art).
/// </summary>
[GlobalClass]
public partial class BossData : Resource
{
    [Export] public string BossName { get; set; } = "The Crimson Countess";
    [Export] public PackedScene BossScene { get; set; }
    [Export] public Texture2D Portrait { get; set; }
    /// <summary>Placeholder Polygon2D tint so bosses read as visually distinct.</summary>
    [Export] public Color SpriteColor { get; set; } = new Color(0.7f, 0.15f, 0.2f, 1f);

    [ExportGroup("Combat Stats")]
    [Export] public int MaxHealth { get; set; } = 500;
    [Export] public float MoveSpeed { get; set; } = 60f;
    /// <summary>Passive contact damage when the player overlaps the boss body hitbox.</summary>
    [Export] public float ContactDamage { get; set; } = 15f;
    [Export] public float ContactDamageCooldown { get; set; } = 1.0f;

    [ExportGroup("Phases")]
    /// <summary>
    /// Ordered high→low EnterHpFraction. Index 0 is the opening phase; later entries unlock
    /// as HP falls (e.g. blood frenzy at 0.5). Empty array → single synthetic full-HP phase
    /// using AbilityIds only (legacy fallback).
    /// </summary>
    [Export] public BossPhaseData[] Phases { get; set; } = System.Array.Empty<BossPhaseData>();

    [ExportGroup("Encounter")]
    /// <summary>Wave number that triggers this boss (BossManager matches OnWaveStart).</summary>
    [Export] public int WaveTrigger { get; set; } = 10;
    [Export] public int CurrencyReward { get; set; } = 100;
    [Export] public int ExperienceReward { get; set; } = 50;
    /// <summary>Legacy ability id list; preferred path is Phases[].Attacks[].AttackId.</summary>
    [Export] public string[] AbilityIds { get; set; } = System.Array.Empty<string>();
}
