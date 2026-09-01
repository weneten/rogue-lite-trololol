extends Node2D
class_name BloodField

# A patch of ground that hurts to stand in. Two uses, one class:
#
#   a pool  left on the floor, static, long-lived
#   an aura carried by the boss, short-lived, follows him
#
# The only difference is whether `follow` is set, so both share the tick, the
# hit test and the look. Splitting them would have meant two places to fix the
# next time the damage cadence changes.
#
# Damage is routed back through the boss rather than applied here, so a phase
# that doubles the boss's damage doubles what its pools do — including pools
# that were already on the floor when the phase changed.

const TICK_SECONDS := 0.3

var radius: float = 70.0
var damage: int = 6
var lifetime: float = 8.0
# Fraction of damage dealt that heals the owner. The aura is how he feeds.
var drain_fraction: float = 0.0
var owner_boss: Boss
# When set, the field rides along with this node instead of staying put.
var follow: Node2D

var _age: float
var _tick_remaining: float = TICK_SECONDS
var _fill: Polygon2D
var _rim: Polygon2D
var _shape: PackedVector2Array

func _ready() -> void:
	z_index = -1
	_build_visuals()

func _process(delta: float) -> void:
	_age += delta

	if follow != null:
		if not is_instance_valid(follow):
			queue_free()
			return

		global_position = follow.global_position

	if _age >= lifetime:
		queue_free()
		return

	_animate()

	_tick_remaining -= delta
	if _tick_remaining > 0.0:
		return

	# Add rather than assign: resetting to a flat 0.3 throws away the overshoot
	# and the cadence drifts to whatever the frame time rounds up to.
	_tick_remaining += TICK_SECONDS
	_bite()

func _bite() -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null or global_position.distance_to(player.global_position) > radius:
		return

	if owner_boss != null and is_instance_valid(owner_boss):
		# Through the boss: it owns the phase damage multiplier and the drain.
		owner_boss.apply_damage_to_player(damage, drain_fraction)
		return

	# Owner gone: a pool he already spilled still burns, but it stops growing
	# stronger and it stops feeding him.

	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health != null and not health.is_dead:
		health.take_damage(damage, self)

func _animate() -> void:
	# Wells up, holds, then drains away. A hazard that pops out of existence at
	# full strength reads as a bug; one that thins out tells you it is ending.
	var fade_in := clampf(_age / 0.28, 0.0, 1.0)
	var fade_out := clampf((lifetime - _age) / 0.6, 0.0, 1.0)
	var life := fade_in * fade_out
	var pulse := 0.82 + 0.18 * sin(_age * 5.0)

	if _fill != null:
		_fill.color = Color(0.42, 0.03, 0.07, 0.62 * life)
		_fill.scale = Vector2.ONE * (0.86 + 0.14 * fade_in) * pulse

	if _rim != null:
		_rim.color = Color(0.85, 0.11, 0.16, 0.85 * life)
		_rim.scale = _fill.scale if _fill != null else Vector2.ONE

func _build_visuals() -> void:
	_shape = _blob(radius, 22)

	_fill = Polygon2D.new()
	_fill.color = Color(0.42, 0.03, 0.07, 0.0)
	_fill.polygon = _shape
	add_child(_fill)

	_rim = Polygon2D.new()
	_rim.color = Color(0.85, 0.11, 0.16, 0.0)
	_rim.polygon = _ring(_shape, 4.0)
	add_child(_rim)

# An irregular outline rather than a circle: a perfect disc reads as a UI
# decal, a lopsided one reads as spilled blood.
static func _blob(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var seed_angle := randf() * TAU
	for i in range(segments):
		var a := TAU * i / segments
		var wobble := 0.86 + 0.16 * sin(a * 3.0 + seed_angle) + 0.06 * sin(a * 7.0 - seed_angle)
		points.append(Vector2(cos(a), sin(a)) * radius * wobble)

	return points

static func _ring(shape: PackedVector2Array, thickness: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in shape:
		out.append(p)

	for i in range(shape.size() - 1, -1, -1):
		var p: Vector2 = shape[i]
		var length := p.length()
		out.append(p * ((length - thickness) / length) if length > thickness else Vector2.ZERO)

	return out

# Static pool left on the floor.
static func spawn_pool(host: Node, position: Vector2, radius: float, damage: int,
	lifetime: float, boss: Boss) -> BloodField:
	return _spawn(host, position, radius, damage, lifetime, boss, 0.0, null)

# Aura carried by its owner.
static func spawn_aura(host: Node, carrier: Node2D, radius: float, damage: int,
	lifetime: float, boss: Boss, drain_fraction: float) -> BloodField:
	return _spawn(host, carrier.global_position, radius, damage, lifetime, boss,
		drain_fraction, carrier)

static func _spawn(host: Node, position: Vector2, radius: float, damage: int, lifetime: float,
	boss: Boss, drain_fraction: float, follow: Node2D) -> BloodField:
	var field := BloodField.new()
	field.radius = radius
	field.damage = damage
	field.lifetime = lifetime
	field.owner_boss = boss
	field.drain_fraction = drain_fraction
	field.follow = follow

	var tree := host.get_tree()
	var parent: Node = tree.current_scene if tree != null else host.get_parent()
	if parent == null:
		parent = host

	parent.add_child(field)
	field.global_position = position
	return field
