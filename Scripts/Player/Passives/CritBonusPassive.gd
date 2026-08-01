extends PassiveAbility
class_name CritBonusPassive

# Witch Hunter — trained to strike the killing blow: PassiveValueA adds flat crit chance
# (e.g. 0.15 = +15%), PassiveValueB adds flat crit damage multiplier (e.g. 0.5 = +50% on crits),
# both applied once at run start on top of whatever the equipped weapon already rolls.

func on_initialize() -> void:
	stats.apply_extra_crit(data.passive_value_a, data.passive_value_b)
