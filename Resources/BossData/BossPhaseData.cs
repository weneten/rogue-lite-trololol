using Godot;

namespace Nightbane.Resources;

/// <summary>
/// One boss phase: becomes active when HP fraction drops to EnterHpFraction (phase 0 is always
/// active from fight start). Carries move/attack multipliers and the attack pattern pool.
/// </summary>
[GlobalClass]
public partial class BossPhaseData : Resource
{
    [Export] public string PhaseName { get; set; } = "Phase 1";

    /// <summary>
    /// HP fraction (0–1) at or below which this phase activates. Phase 0 should use 1.0 (start).
    /// Later phases use lower values (e.g. 0.5 blood frenzy). Order phases high → low.
    /// </summary>
    [Export] public float EnterHpFraction { get; set; } = 1.0f;

    [Export] public float MoveSpeedMultiplier { get; set; } = 1.0f;
    /// <summary>Multiplies each attack's CooldownSeconds while this phase is active (&lt;1 = faster).</summary>
    [Export] public float AttackCooldownMultiplier { get; set; } = 1.0f;

    [Export] public BossAttackPatternData[] Attacks { get; set; } = System.Array.Empty<BossAttackPatternData>();
}
