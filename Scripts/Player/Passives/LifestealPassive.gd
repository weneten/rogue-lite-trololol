extends PassiveAbility
class_name LifestealPassive

# Bloodletter — every wound she opens feeds her own: PassiveValueA is the fraction of damage
# dealt returned as healing (e.g. 0.12 = 12% lifesteal), applied by PlayerStats.NotifyDamageDealt
# on every weapon hit (melee and ranged alike).

func on_initialize() -> void:
	stats.apply_lifesteal(data.passive_value_a)
