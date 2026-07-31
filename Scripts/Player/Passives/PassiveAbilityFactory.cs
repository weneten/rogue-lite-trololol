namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Maps CharacterData.PassiveId to its concrete PassiveAbility implementation. Keeping the switch
/// in one place means adding a new Hunter only ever needs a new id string on the .tres plus a new
/// class here — Player.cs never branches on which Hunter is selected.
/// </summary>
public static class PassiveAbilityFactory
{
    public static PassiveAbility Create(string passiveId)
    {
        return passiveId switch
        {
            "hp_for_damage" => new HpForDamageTradeoffPassive(),
            "bonus_vs_undead" => new BonusVsUndeadPassive(),
            "crit_bonus" => new CritBonusPassive(),
            "lifesteal" => new LifestealPassive(),
            "taunt_armor" => new TauntArmorPassive(),
            "fire_dot" => new FireDotPassive(),
            "summon_familiars" => new SummonFamiliarsPassive(),
            "dual_wield_attack_speed" => new DualWieldAttackSpeedPassive(),
            "potion_throw_debuff" => new PotionThrowDebuffPassive(),
            "curse_lift_scaling" => new CurseLiftScalingPassive(),
            _ => null
        };
    }
}
