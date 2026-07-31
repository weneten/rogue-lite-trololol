using Godot;

namespace Nightbane.Resources;

/// <summary>What effect an upgrade choice applies on selection. Passive is a placeholder for a
/// future relic/passive-item system — LevelUpUI just logs the pick for now, no real effect yet.</summary>
public enum UpgradeType
{
    DamageBoost,
    MoveSpeedBoost,
    MaxHealthBoost,
    Passive
}

/// <summary>
/// Data-driven definition of a single level-up choice. LevelUpUI rolls a few of these from an
/// UpgradePoolData and, on selection, applies Value to PlayerStats according to UpgradeType.
/// </summary>
[GlobalClass]
public partial class UpgradeData : Resource
{
    [Export] public string Id { get; set; } = "upgrade_id";
    [Export] public string DisplayName { get; set; } = "Unnamed Upgrade";
    [Export(PropertyHint.MultilineText)] public string Description { get; set; } = "";
    [Export] public Texture2D Icon { get; set; }
    [Export] public UpgradeType UpgradeType { get; set; } = UpgradeType.DamageBoost;
    /// <summary>Magnitude applied on selection; meaning depends on UpgradeType (e.g. +0.15 damage
    /// multiplier, +20 max HP). Unused for Passive.</summary>
    [Export] public float Value { get; set; } = 0f;
    /// <summary>Relative weight in LevelUpUI's random draw.</summary>
    [Export] public float Weight { get; set; } = 1f;
}
