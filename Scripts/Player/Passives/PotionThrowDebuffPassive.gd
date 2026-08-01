extends PassiveAbility
class_name PotionThrowDebuffPassive

# Alchemist — lobs a corrosive vial at the nearest foe on a timer: every PassiveValueB seconds
# (default 2.5s), deals PassiveValueA instant poison damage to the nearest live Enemy-group
# target in the arena, independent of and in addition to her equipped weapons' own attacks.

var _cooldown_remaining: float

func on_initialize() -> void:
	_cooldown_remaining = throw_interval()

func _process(delta: float) -> void:
	_cooldown_remaining -= delta
	if _cooldown_remaining > 0:
		return

	_cooldown_remaining = throw_interval()

	var target = find_nearest_enemy()
	var health: HealthComponent = null
	if target:
		health = target.get_node_or_null("HealthComponent") as HealthComponent
	if health != null and not health.is_dead:
		health.take_damage(roundi(data.passive_value_a), owner_player)

func throw_interval() -> float:
	return data.passive_value_b if data.passive_value_b > 0 else 2.5

# Nearest live member of the "Enemy" group to the Player, or null if the arena is empty.
func find_nearest_enemy() -> Node2D:
	if owner_player == null:
		return null

	var nearest: Node2D = null
	var nearest_dist_sq = INF
	var origin = owner_player.global_position

	for node in owner_player.get_tree().get_nodes_in_group("Enemy"):
		if not (node is Node2D):
			continue

		var candidate = node as Node2D
		var health: HealthComponent = candidate.get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.is_dead:
			continue

		var dist_sq = origin.distance_squared_to(candidate.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = candidate

	return nearest
