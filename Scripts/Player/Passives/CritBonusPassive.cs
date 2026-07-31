namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Witch Hunter — trained to strike the killing blow: PassiveValueA adds flat crit chance
/// (e.g. 0.15 = +15%), PassiveValueB adds flat crit damage multiplier (e.g. 0.5 = +50% on crits),
/// both applied once at run start on top of whatever the equipped weapon already rolls.
/// </summary>
public partial class CritBonusPassive : PassiveAbility
{
    protected override void OnInitialize() => Stats.ApplyExtraCrit(Data.PassiveValueA, Data.PassiveValueB);
}
