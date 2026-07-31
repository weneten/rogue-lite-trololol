namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Silver Priest — blessed rounds and rites hit undead harder: PassiveValueA is a flat multiplier
/// increase (e.g. 0.5 = +50%) applied only to targets whose EnemyData.IsUndead is true
/// (see Weapon.ComputeDamageMultiplier).
/// </summary>
public partial class BonusVsUndeadPassive : PassiveAbility
{
    protected override void OnInitialize() => Stats.ApplyUndeadDamageBonus(Data.PassiveValueA);
}
