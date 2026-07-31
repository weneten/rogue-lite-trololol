using Godot;
using Nightbane.Resources;

namespace Nightbane.Shop;

/// <summary>
/// Pure, static Grave Coin pricing formulas for the shop phase. Isolated from ShopUI/GameManager
/// so every price/refund/reroll/bonus number in the game lives in exactly one tunable place
/// instead of being scattered as magic numbers across UI code.
/// TODO: rebalance vs kill-payouts/wave density once EnemyScaling (Enemy roster) is final — do not
/// edit EnemyScaling from here.
/// </summary>
public static class ShopEconomy
{
    /// <summary>Flat Grave Coin added on top of a rarity's base cost, indexed by RarityTier
    /// (Common..Legendary). Keeps high-tier offers expensive without per-item hardcoding.</summary>
    private static readonly int[] RarityCostBonus = { 0, 6, 14, 26, 45 };

    /// <summary>WeaponData/PassiveItemData.ShopCost (designer dial ~1-5) * this + rarity bonus
    /// → actual Grave Coin price. Sample Common ShopCost 5 weapon = 15g; Uncommon passive 3 = 18g.</summary>
    private const int WeaponCostMultiplier = 3;
    private const int PassiveCostMultiplier = 4;

    /// <summary>Fraction of a weapon's current shop price refunded when sold back.</summary>
    private const float WeaponSellRefundFraction = 0.5f;

    /// <summary>Reroll: base + growth * rerollsThisVisit (reset each shop open).
    /// First reroll costs RerollBaseCost (never free); 5→7→9… discourages infinite fishing.</summary>
    private const int RerollBaseCost = 5;
    private const int RerollGrowthPerReroll = 2;

    /// <summary>End-of-wave bonus: base + growth * (wave - 1). Wave 1 = 10g, wave 5 = 18g, etc.
    /// Stacks on top of per-kill currency so a cleared wave always pays something.</summary>
    private const int WaveEndBonusBase = 10;
    private const int WaveEndBonusGrowthPerWave = 2;

    public static int GetWeaponPrice(WeaponData data)
    {
        if (data == null)
        {
            return 0;
        }

        return Mathf.Max(1, data.ShopCost * WeaponCostMultiplier + RarityBonus(data.RarityTier));
    }

    public static int GetWeaponSellValue(WeaponData data)
    {
        return Mathf.RoundToInt(GetWeaponPrice(data) * WeaponSellRefundFraction);
    }

    public static int GetPassivePrice(PassiveItemData data)
    {
        if (data == null)
        {
            return 0;
        }

        return Mathf.Max(1, data.ShopCost * PassiveCostMultiplier + RarityBonus(data.RarityTier));
    }

    /// <param name="rerollsThisVisit">How many times the shop has already been rerolled since it opened.</param>
    public static int GetRerollCost(int rerollsThisVisit)
    {
        return RerollBaseCost + RerollGrowthPerReroll * Mathf.Max(0, rerollsThisVisit);
    }

    /// <param name="waveNumberCompleted">The wave number that just ended.</param>
    public static int GetWaveEndBonus(int waveNumberCompleted)
    {
        return WaveEndBonusBase + WaveEndBonusGrowthPerWave * Mathf.Max(0, waveNumberCompleted - 1);
    }

    private static int RarityBonus(RarityTier tier)
    {
        int index = Mathf.Clamp((int)tier, 0, RarityCostBonus.Length - 1);
        return RarityCostBonus[index];
    }
}
