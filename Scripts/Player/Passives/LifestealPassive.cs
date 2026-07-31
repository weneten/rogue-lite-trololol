namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Bloodletter — every wound she opens feeds her own: PassiveValueA is the fraction of damage
/// dealt returned as healing (e.g. 0.12 = 12% lifesteal), applied by PlayerStats.NotifyDamageDealt
/// on every weapon hit (melee and ranged alike).
/// </summary>
public partial class LifestealPassive : PassiveAbility
{
    protected override void OnInitialize() => Stats.ApplyLifesteal(Data.PassiveValueA);
}
