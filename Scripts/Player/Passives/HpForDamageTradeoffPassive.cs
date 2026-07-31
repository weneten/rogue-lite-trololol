namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// The Reaper — wagers her own blood for a bigger scythe swing: permanently deals PassiveValueA
/// more damage but also takes PassiveValueB more damage, applied once at run start (both are
/// fractional multiplier increases, e.g. 0.3 = +30%).
/// </summary>
public partial class HpForDamageTradeoffPassive : PassiveAbility
{
    protected override void OnInitialize()
    {
        Stats.ApplyDamageUpgrade(Data.PassiveValueA);
        Stats.ApplyIncomingDamageMultiplier(Data.PassiveValueB);
    }
}
