extends Node2D
class_name BossRitualCircle

# Persistent purple ritual zone that ticks damage only while the player is nearly stationary
# inside it — punishes camping. Frees after DurationSeconds.

var radius: float = 90.0
var duration_seconds: float = 5.0
var tick_interval: float = 0.4
var damage_per_tick: int = 8
# Player speed below this counts as "standing still".
var still_speed_threshold: float = 30.0
var instigator: Node

var _life_remaining: float
var _tick_remaining: float
var _last_player_pos: Vector2
var _has_last_pos: bool

func _ready() -> void:
	_life_remaining = duration_seconds
	_tick_remaining = tick_interval
	z_index = -1

	var fill = Polygon2D.new()
	fill.color = Color(0.45, 0.1, 0.7, 0.35)
	fill.polygon = _build_circle(radius, 24)
	add_child(fill)

	var ring = Polygon2D.new()
	ring.color = Color(0.7, 0.25, 0.95, 0.8)
	ring.polygon = _build_ring(radius * 0.9, radius, 24)
	add_child(ring)

func _process(delta: float) -> void:
	_life_remaining -= delta
	if _life_remaining <= 0:
		queue_free()
		return

	# Slow pulse.
	modulate = Color(1.0, 1.0, 1.0, 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006))

	_tick_remaining -= delta
	if _tick_remaining > 0:
		return

	_tick_remaining = tick_interval
	_try_punish_stationary_player()

func _try_punish_stationary_player() -> void:
	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	if global_position.distance_to(player.global_position) > radius:
		_has_last_pos = false
		return

	var speed: float
	if player is CharacterBody2D:
		var body = player as CharacterBody2D
		speed = body.velocity.length()
	elif _has_last_pos:
		speed = _last_player_pos.distance_to(player.global_position) / maxf(0.001, tick_interval)
	else:
		speed = 0.0

	_last_player_pos = player.global_position
	_has_last_pos = true

	if speed > still_speed_threshold:
		return

	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health == null or health.is_dead:
		return

	health.take_damage(damage_per_tick, instigator)

static func _build_circle(radius: float, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments):
		var a = TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * radius)

	return points

static func _build_ring(inner: float, outer: float, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments):
		var a = TAU * i / segments
		var dir = Vector2(cos(a), sin(a))
		points.append(dir * outer)

	for i in range(segments):
		var a = TAU * i / segments
		var dir = Vector2(cos(a), sin(a))
		points.insert(segments + (segments - 1 - i), dir * inner)

	return points

static func spawn(host: Node, global_position: Vector2, radius: float, duration: float,
	damage_per_tick: int, instigator: Node) -> BossRitualCircle:
	var circle = BossRitualCircle.new()
	circle.radius = radius
	circle.duration_seconds = duration
	circle.damage_per_tick = damage_per_tick
	circle.instigator = instigator

	var parent = host.get_tree().current_scene if host.get_tree() else host.get_parent() if host.get_parent() else host
	parent.add_child(circle)
	circle.global_position = global_position
	return circle
