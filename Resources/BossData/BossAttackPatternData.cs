using Godot;

namespace Nightbane.Resources;

/// <summary>
/// One telegraphed (or instant) boss attack definition. AttackId is resolved by the boss
/// subclass; numeric fields are shared param slots so designers can tune without code.
/// </summary>
[GlobalClass]
public partial class BossAttackPatternData : Resource
{
    /// <summary>Key looked up by boss AI (e.g. "ground_smash", "curse_bolt", "bat_swarm").</summary>
    [Export] public string AttackId { get; set; } = "melee";

    [ExportGroup("Timing")]
    /// <summary>Red AoE / cast warning duration before the hit resolves.</summary>
    [Export] public float WindupSeconds { get; set; } = 0.8f;
    /// <summary>Brief lock after the hit before the boss can pick another attack.</summary>
    [Export] public float RecoverySeconds { get; set; } = 0.25f;
    /// <summary>Base delay until this attack (or any attack) may fire again after recovery.</summary>
    [Export] public float CooldownSeconds { get; set; } = 2.5f;

    [ExportGroup("Combat Params")]
    [Export] public float Damage { get; set; } = 20f;
    /// <summary>AoE / shockwave / ritual radius in pixels.</summary>
    [Export] public float Radius { get; set; } = 80f;
    /// <summary>Preferred cast range / blink distance / bolt travel context.</summary>
    [Export] public float Range { get; set; } = 220f;
    /// <summary>Projectile / dash speed where applicable.</summary>
    [Export] public float Speed { get; set; } = 280f;
    /// <summary>How many summons, bolts, or rings this attack produces.</summary>
    [Export] public int Count { get; set; } = 1;
    /// <summary>DoT / zone lifetime / frenzy duration depending on AttackId.</summary>
    [Export] public float Duration { get; set; } = 3f;
    /// <summary>Fraction of damage healed by the boss (blood frenzy life drain). 0 = none.</summary>
    [Export] public float HealFraction { get; set; } = 0f;
}
