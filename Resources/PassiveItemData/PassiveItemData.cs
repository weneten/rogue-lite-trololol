using Godot;

namespace Nightbane.Resources;

/// <summary>What stat a passive item permanently boosts on purchase. Mirrors UpgradeType's numeric
/// effects (no Passive/relic-placeholder case here since these ARE the relics).</summary>
public enum PassiveEffectType
{
    DamageBoost,
    MoveSpeedBoost,
    MaxHealthBoost
}

/// <summary>
/// Data-driven definition of a shop passive item (a permanent relic-style trinket, as opposed to
/// a WeaponData). ShopUI rolls these from a ShopPoolData and, on purchase, applies Value to
/// PlayerStats according to EffectType — same shape as UpgradeData/LevelUpUI but sold for
/// Grave Coin instead of offered for free on level-up.
/// </summary>
[GlobalClass]
public partial class PassiveItemData : Resource
{
    [Export] public string Id { get; set; } = "passive_id";
    [Export] public string DisplayName { get; set; } = "Unnamed Relic";
    [Export(PropertyHint.MultilineText)] public string Description { get; set; } = "";
    [Export] public Texture2D Icon { get; set; }
    [Export] public PassiveEffectType EffectType { get; set; } = PassiveEffectType.DamageBoost;
    /// <summary>Magnitude applied on purchase; meaning depends on EffectType (e.g. +0.1 damage multiplier, +15 max HP).</summary>
    [Export] public float Value { get; set; } = 0f;

    [ExportGroup("Classification")]
    [Export] public RarityTier RarityTier { get; set; } = RarityTier.Common;

    [ExportGroup("Meta")]
    /// <summary>Small designer dial (1-5), turned into an actual Grave Coin price by ShopEconomy.</summary>
    [Export(PropertyHint.Range, "1,5,1")] public int ShopCost { get; set; } = 3;
}
