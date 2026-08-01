extends PassiveAbility
class_name TauntArmorPassive

# Bloodstained Crusader — an unmovable wall that punishes whoever dares strike it: PassiveValueA is flat
# bonus Armor applied once at run start; PassiveValueB is the fraction of every hit it takes
# reflected straight back at its source's HealthComponent (its "iron thorns"), standing in for a
# taunt since every enemy in this single-player arena already always targets the Player.

func on_initialize() -> void:
	if health != null:
		health.armor += roundi(data.passive_value_a)

func on_damage_taken(amount: int, source: Node) -> void:
	if source == null or data.passive_value_b <= 0.0:
		return

	var source_health: HealthComponent = source.get_node_or_null("HealthComponent") as HealthComponent
	if source_health != null and not source_health.is_dead:
		source_health.take_damage(roundi(amount * data.passive_value_b), owner_player)
