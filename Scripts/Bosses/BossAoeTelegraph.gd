extends Node2D
class_name BossAoeTelegraph

# Ground warning decal drawn under a boss wind-up. Three shapes: a circle for
# AoEs, a cone for sweeps, a lane for charges. After WindupSeconds it damages
# any live Player inside the shape, then frees.
#
# The shape is drawn twice: a dim danger zone at full size, plus a bright fill
# that grows from nothing to full over the wind-up. The growing fill is the
# actual timing signal — a decal that only pulses tells you that something is
# coming but not when, which is the difference between a dodge and a guess.

enum Shape {
	CIRCLE,
	CONE,
	LANE,
}

var shape: Shape = Shape.CIRCLE
var radius: float = 80.0

# CONE / LANE: unit vector the shape points along, plus its spread / width.
var direction: Vector2 = Vector2.RIGHT
var arc_degrees: float = 90.0
var lane_width: float = 48.0

var windup_seconds: float = 0.8
var damage: int = 20
var instigator: Node
# When true, resolve damage on timer end. When false, only visual (caller resolves).
var deal_damage_on_complete: bool = true
# Optional callback after wind-up (before free), e.g. for custom hit logic.
var on_windup_complete: Callable

var _remaining: float
var _fill: Polygon2D
var _grow: Polygon2D
var _ring: Polygon2D
var _resolved: bool = false

func _ready() -> void:
	_remaining = windup_seconds
	build_visuals()
	z_index = -1

func _process(delta: float) -> void:
	if _resolved:
		return

	_remaining -= delta

	var t = 1.0 - (_remaining / windup_seconds) if windup_seconds > 0.0 else 1.0
	t = clampf(t, 0.0, 1.0)

	# Danger zone breathes; the fill sweeps. Two separate channels so "where"
	# and "when" never get confused with each other.
	var pulse = 0.35 + 0.45 * (0.5 + 0.5 * sin(t * TAU * 4.0))
	if _fill != null:
		_fill.color = Color(0.95, 0.1, 0.12, pulse * 0.32)

	if _grow != null:
		_grow.scale = Vector2.ONE * maxf(0.001, t)
		# Whites out over the last ~12% so the hit frame is unmistakable.
		var heat = clampf((t - 0.88) / 0.12, 0.0, 1.0)
		_grow.color = Color(1.0, 0.25 + heat * 0.6, 0.2 + heat * 0.6, 0.42 + heat * 0.35)

	if _remaining > 0:
		return

	resolve()

func resolve() -> void:
	if _resolved:
		return

	_resolved = true
	if on_windup_complete:
		on_windup_complete.call()

	if deal_damage_on_complete:
		damage_players_in_radius()

	queue_free()

func damage_players_in_radius() -> void:
	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null or not contains_point(player.global_position):
		return

	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health == null or health.is_dead:
		return

	health.take_damage(damage, instigator)

# Hit test in world space, matching whatever shape is drawn.
func contains_point(point: Vector2) -> bool:
	var local = point - global_position
	match shape:
		Shape.CONE:
			if local.length() > radius:
				return false
			return absf(rad_to_deg(direction.angle_to(local))) <= arc_degrees * 0.5
		Shape.LANE:
			var along = local.dot(direction)
			if along < -lane_width * 0.5 or along > radius:
				return false
			return absf(local.dot(Vector2(-direction.y, direction.x))) <= lane_width * 0.5
		_:
			return local.length() <= radius

func build_visuals() -> void:
	var points = _build_shape_polygon()

	_fill = Polygon2D.new()
	_fill.color = Color(0.95, 0.1, 0.12, 0.3)
	_fill.polygon = points
	add_child(_fill)

	_grow = Polygon2D.new()
	_grow.color = Color(1.0, 0.25, 0.2, 0.42)
	_grow.polygon = points
	_grow.scale = Vector2.ONE * 0.001
	add_child(_grow)

	_ring = Polygon2D.new()
	_ring.color = Color(1.0, 0.3, 0.22, 0.9)
	_ring.polygon = _build_border_polygon(points, 3.0)
	add_child(_ring)

# Re-aims a telegraph that is already on the ground. The wind-up clock is
# untouched, so the growing fill keeps its progress — only where it points has
# moved. This is what lets an attack track its target while it charges up
# instead of committing to wherever the target stood when it started.
func retarget(new_origin: Vector2, new_direction: Vector2, new_length: float = -1.0) -> void:
	global_position = new_origin

	if new_direction.length_squared() > 0.0001:
		direction = new_direction.normalized()

	if new_length > 0.0:
		radius = new_length

	rebuild_shape()

func rebuild_shape() -> void:
	var points := _build_shape_polygon()
	if _fill != null:
		_fill.polygon = points

	if _grow != null:
		_grow.polygon = points

	if _ring != null:
		_ring.polygon = _build_border_polygon(points, 3.0)

func _build_shape_polygon() -> PackedVector2Array:
	match shape:
		Shape.CONE:
			return _build_cone_polygon(radius, arc_degrees, direction.angle(), 20)
		Shape.LANE:
			return _build_lane_polygon(radius, lane_width, direction)
		_:
			return _build_circle_polygon(radius, 28)

# A hollow outline of `points`, built by shrinking the shape toward its own
# centroid. Works for all three shapes without a per-shape special case.
static func _build_border_polygon(points: PackedVector2Array, thickness: float) -> PackedVector2Array:
	var centroid = Vector2.ZERO
	for p in points:
		centroid += p

	if points.size() > 0:
		centroid /= points.size()

	var out = PackedVector2Array()
	for p in points:
		out.append(p)

	for i in range(points.size() - 1, -1, -1):
		var p = points[i]
		var inward = centroid - p
		var dist = inward.length()
		if dist > 0.001:
			p += inward / dist * minf(thickness, dist * 0.9)

		out.append(p)

	return out

static func _build_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments):
		var a = TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * radius)

	return points

static func _build_cone_polygon(radius: float, arc_degrees: float, facing: float, segments: int) -> PackedVector2Array:
	var half = deg_to_rad(arc_degrees) * 0.5
	var points = PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var a = facing - half + (deg_to_rad(arc_degrees) * i / segments)
		points.append(Vector2(cos(a), sin(a)) * radius)

	return points

static func _build_lane_polygon(length: float, width: float, direction: Vector2) -> PackedVector2Array:
	var forward = direction.normalized()
	var side = Vector2(-forward.y, forward.x) * width * 0.5
	var back = -forward * width * 0.5
	return PackedVector2Array([
		back + side,
		forward * length + side,
		forward * length - side,
		back - side,
	])

# Factory: parents a telegraph under the current scene at world position.
static func spawn(host: Node, global_position: Vector2, radius: float, windup_seconds: float,
	damage: int, instigator: Node, deal_damage_on_complete: bool = true, on_complete: Callable = Callable()) -> BossAoeTelegraph:
	var telegraph = BossAoeTelegraph.new()
	telegraph.radius = radius
	telegraph.windup_seconds = windup_seconds
	telegraph.damage = damage
	telegraph.instigator = instigator
	telegraph.deal_damage_on_complete = deal_damage_on_complete
	telegraph.on_windup_complete = on_complete
	_attach(host, telegraph, global_position)
	return telegraph

# Cone sweep in front of the boss. `facing` need not be normalized.
static func spawn_cone(host: Node, global_position: Vector2, facing: Vector2, radius: float,
	arc_degrees: float, windup_seconds: float, damage: int, instigator: Node,
	deal_damage_on_complete: bool = true, on_complete: Callable = Callable()) -> BossAoeTelegraph:
	var telegraph = BossAoeTelegraph.new()
	telegraph.shape = Shape.CONE
	telegraph.direction = facing.normalized() if facing.length_squared() > 0.0001 else Vector2.RIGHT
	telegraph.arc_degrees = arc_degrees
	telegraph.radius = radius
	telegraph.windup_seconds = windup_seconds
	telegraph.damage = damage
	telegraph.instigator = instigator
	telegraph.deal_damage_on_complete = deal_damage_on_complete
	telegraph.on_windup_complete = on_complete
	_attach(host, telegraph, global_position)
	return telegraph

# Charge lane running from the boss toward a destination.
static func spawn_lane(host: Node, global_position: Vector2, facing: Vector2, length: float,
	width: float, windup_seconds: float, damage: int, instigator: Node,
	deal_damage_on_complete: bool = true, on_complete: Callable = Callable()) -> BossAoeTelegraph:
	var telegraph = BossAoeTelegraph.new()
	telegraph.shape = Shape.LANE
	telegraph.direction = facing.normalized() if facing.length_squared() > 0.0001 else Vector2.RIGHT
	telegraph.lane_width = width
	telegraph.radius = length
	telegraph.windup_seconds = windup_seconds
	telegraph.damage = damage
	telegraph.instigator = instigator
	telegraph.deal_damage_on_complete = deal_damage_on_complete
	telegraph.on_windup_complete = on_complete
	_attach(host, telegraph, global_position)
	return telegraph

static func _attach(host: Node, telegraph: BossAoeTelegraph, global_position: Vector2) -> void:
	var parent = host.get_tree().current_scene if host.get_tree() else host.get_parent() if host.get_parent() else host
	parent.add_child(telegraph)
	telegraph.global_position = global_position
