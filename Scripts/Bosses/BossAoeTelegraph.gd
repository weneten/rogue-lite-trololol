extends Node2D
class_name BossAoeTelegraph

# Red circular warning decal. After WindupSeconds it damages any live Player in radius, then frees.
# Spawned by Boss during attack wind-up so the player can dodge telegraphed AoEs.

var radius: float = 80.0
var windup_seconds: float = 0.8
var damage: int = 20
var instigator: Node
# When true, resolve damage on timer end. When false, only visual (caller resolves).
var deal_damage_on_complete: bool = true
# Optional callback after wind-up (before free), e.g. for custom hit logic.
var on_windup_complete: Callable

var _remaining: float
var _fill: Polygon2D
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

	# Pulse alpha so the telegraph reads as urgent.
	var t = 1.0 - (_remaining / windup_seconds) if windup_seconds > 0.0 else 1.0
	var pulse = 0.35 + 0.45 * (0.5 + 0.5 * sin(t * TAU * 4.0))
	if _fill != null:
		_fill.color = Color(0.95, 0.1, 0.12, pulse * 0.45)

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
	if player == null:
		return

	if global_position.distance_to(player.global_position) > radius:
		return

	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health == null or health.is_dead:
		return

	health.take_damage(damage, instigator)

func build_visuals() -> void:
	_fill = Polygon2D.new()
	_fill.color = Color(0.95, 0.1, 0.12, 0.35)
	_fill.polygon = _build_circle_polygon(radius, 28)
	add_child(_fill)

	_ring = Polygon2D.new()
	_ring.color = Color(1.0, 0.25, 0.2, 0.85)
	_ring.polygon = _build_ring_polygon(radius * 0.92, radius, 28)
	add_child(_ring)

static func _build_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(segments):
		var a = TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * radius)

	return points

static func _build_ring_polygon(inner: float, outer: float, segments: int) -> PackedVector2Array:
	# Triangle strip as a single polygon: outer ring then reversed inner ring.
	var points = PackedVector2Array()
	for i in range(segments):
		var a = TAU * i / segments
		var dir = Vector2(cos(a), sin(a))
		points.append(dir * outer)

	for i in range(segments):
		var a = TAU * i / segments
		var dir = Vector2(cos(a), sin(a))
		points.insert(points.size(), dir * inner)

	return points

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

	var parent = host.get_tree().current_scene if host.get_tree() else host.get_parent() if host.get_parent() else host
	parent.add_child(telegraph)
	telegraph.global_position = global_position
	return telegraph
