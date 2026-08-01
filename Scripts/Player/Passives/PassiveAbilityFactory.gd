class_name PassiveAbilityFactory

# Maps CharacterData.PassiveId to its concrete PassiveAbility implementation. Keeping the switch
# in one place means adding a new Hunter only ever needs a new id string on the .tres plus a new
# class here — Player.cs never branches on which Hunter is selected.

static func create(passive_id: String) -> PassiveAbility:
	match passive_id:
		"hp_for_damage":
			return HpForDamageTradeoffPassive.new()
		"bonus_vs_undead":
			return BonusVsUndeadPassive.new()
		"crit_bonus":
			return CritBonusPassive.new()
		"lifesteal":
			return LifestealPassive.new()
		"taunt_armor":
			return TauntArmorPassive.new()
		"fire_dot":
			return FireDotPassive.new()
		"summon_familiars":
			return SummonFamiliarsPassive.new()
		"dual_wield_attack_speed":
			return DualWieldAttackSpeedPassive.new()
		"potion_throw_debuff":
			return PotionThrowDebuffPassive.new()
		"curse_lift_scaling":
			return CurseLiftScalingPassive.new()
		_:
			return null
