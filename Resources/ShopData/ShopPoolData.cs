using System;
using Godot;

namespace Nightbane.Resources;

/// <summary>
/// Data-driven container for everything ShopUI can roll for sale — mirrors WaveData.EnemyPool /
/// UpgradePoolData.Upgrades: one resource serves indefinitely, add more WeaponData/PassiveItemData
/// .tres entries to the arrays to expand the shop without touching code.
/// </summary>
[GlobalClass]
public partial class ShopPoolData : Resource
{
    [Export] public WeaponData[] WeaponPool { get; set; } = Array.Empty<WeaponData>();
    [Export] public PassiveItemData[] PassivePool { get; set; } = Array.Empty<PassiveItemData>();
}
