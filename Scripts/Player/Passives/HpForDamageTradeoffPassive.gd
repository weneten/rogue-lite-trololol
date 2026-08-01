extends PassiveAbility
class_name HpForDamageTradeoffPassive

# The Reaper — wagers her own blood for a bigger scythe swing: permanently deals PassiveValueA
# more damage but also takes PassiveValueB more damage, applied once at run start (both are
# fractional multiplier increases, e.g. 0.3 = +30%).

func on_initialize() -> void:
	stats.apply_damage_upgrade(data.passive_value_a)
	stats.apply_incoming_damage_multiplier(data.passive_value_b)
