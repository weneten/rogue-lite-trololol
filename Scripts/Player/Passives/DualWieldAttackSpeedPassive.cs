namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Moonlit Duelist — twin blades under moonlight, every strike faster than the last: PassiveValueA
/// is a flat multiplier increase to attack speed (e.g. 0.35 = +35% attacks/sec) applied to every
/// equipped weapon via PlayerStats.AttackSpeedMultiplier.
/// </summary>
public partial class DualWieldAttackSpeedPassive : PassiveAbility
{
    protected override void OnInitialize() => Stats.ApplyAttackSpeedBonus(Data.PassiveValueA);
}
