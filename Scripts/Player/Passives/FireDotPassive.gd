extends PassiveAbility
class_name FireDotPassive

# Pyromancer — every hit sets the target alight: on each weapon hit, applies (or refreshes,
# non-stacking) a burn on the target dealing PassiveValueA * hitDamage per tick, once per second,
# for PassiveValueB seconds. Ticked in _Process rather than relying on any single Weapon instance
# so the burn keeps running between attacks and across whichever weapon last tagged the target.

class Burn:
	var target: HealthComponent
	var time_remaining: float
	var tick_timer: float
	var tick_damage: int

const TICK_INTERVAL = 1.0
var _active_burns: Array[Burn] = []

func on_damage_dealt(amount: int, target: Node) -> void:
	var health = resolve_health(target)
	if health == null or health.is_dead:
		return

	var tick_damage = maxi(1, roundi(amount * data.passive_value_a))
	var duration = data.passive_value_b if data.passive_value_b > 0 else 3.0

	var existing = null
	for burn in _active_burns:
		if burn.target == health:
			existing = burn
			break

	if existing != null:
		existing.time_remaining = duration
		existing.tick_damage = tick_damage
	else:
		var new_burn = Burn.new()
		new_burn.target = health
		new_burn.time_remaining = duration
		new_burn.tick_timer = TICK_INTERVAL
		new_burn.tick_damage = tick_damage
		_active_burns.append(new_burn)

func _process(delta: float) -> void:
	for i in range(_active_burns.size() - 1, -1, -1):
		var burn = _active_burns[i]
		if burn.target == null or not is_instance_valid(burn.target) or burn.target.is_dead:
			_active_burns.remove_at(i)
			continue

		burn.time_remaining -= delta
		burn.tick_timer -= delta
		if burn.tick_timer <= 0:
			burn.target.take_damage(burn.tick_damage, owner_player)
			burn.tick_timer += TICK_INTERVAL

		if burn.time_remaining <= 0:
			_active_burns.remove_at(i)

static func resolve_health(target: Node) -> HealthComponent:
	var as_health = target as HealthComponent
	if as_health != null:
		return as_health
	return target.get_node_or_null("HealthComponent") as HealthComponent
