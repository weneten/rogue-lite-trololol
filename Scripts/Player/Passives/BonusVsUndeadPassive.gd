extends PassiveAbility
class_name BonusVsUndeadPassive

# Silver Priest — blessed rounds and rites hit undead harder: PassiveValueA is a flat multiplier
# increase (e.g. 0.5 = +50%) applied only to targets whose EnemyData.IsUndead is true
# (see Weapon.ComputeDamageMultiplier).

func on_initialize() -> void:
	stats.apply_undead_damage_bonus(data.passive_value_a)
