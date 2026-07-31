using Godot;

namespace Nightbane.Resources;

/// <summary>Simple data-driven container for the pool LevelUpUI draws random, non-repeating choices
/// from — mirrors WaveData.EnemyPool: one resource can serve indefinitely, add more UpgradeData
/// .tres files to the array to expand the pool without touching code.</summary>
[GlobalClass]
public partial class UpgradePoolData : Resource
{
    [Export] public UpgradeData[] Upgrades { get; set; } = System.Array.Empty<UpgradeData>();
}
