extends Node2D
class_name BossSonicWave

# One expanding arc of sound, fired by The Belfry Tyrant. Travels outward from
# where it was spawned, widening as it goes, and hits the player once.
#
# Hit testing is a distance-and-angle check rather than an Area2D, for the same
# reason BossAoeTelegraph does it: the shape the player sees and the shape that
# hits them are then literally the same two numbers, and a growing physics
# shape cannot drift out of sync with the drawn one.
#
# Which means the arc has to be drawn at its real radii, rebuilt as it travels.
# It used to be a unit arc scaled up by the distance travelled, and that quietly
# broke the promise above twice over: the drawn outer edge sat exactly on the
# leading edge while the hit test reached `band` px further, so the wave hit from
# outside its own picture; and the drawn thickness was a fraction of the radius,
# so it grew as the wave spread while the hit band stayed the same width.

const ARC_SEGMENTS := 40
# How much of the hit band the bright core line covers. Kept well inside 1.0 so
# the core never reads as the edge of the danger.
const CORE_FRACTION := 0.28

var direction: Vector2 = Vector2.RIGHT
var arc_degrees: float = 52.0
var speed: float = 300.0
var max_distance: float = 300.0
# Half-thickness of the band. A wave you can stand inside is a wave you can
# also stand behind, which is the whole dodge.
var band: float = 16.0
var damage: int = 16
var instigator: Node

var _distance: float = 8.0
var _spent: bool = false
var _band: Polygon2D
var _core: Polygon2D

func _ready() -> void:
	z_index = -1
	_build_visuals()

func _process(delta: float) -> void:
	_distance += speed * delta
	if _distance >= max_distance:
		queue_free()
		return

	_update_shape()

	if not _spent:
		_try_hit()

func _try_hit() -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	# global_position rather than a cached origin: the wave never moves itself, but
	# the world folds around the Hunter (see ArenaLoop), and a stored copy would be
	# left a world away the first time it did.
	var local := player.global_position - global_position
	var dist := local.length()
	if absf(dist - _distance) > band:
		return

	if absf(rad_to_deg(direction.angle_to(local))) > arc_degrees * 0.5:
		return

	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health == null or health.is_dead:
		return

	_spent = true
	health.take_damage(damage, instigator)

func _build_visuals() -> void:
	_band = Polygon2D.new()
	_band.color = Color(0.45, 0.75, 0.9, 0.28)
	add_child(_band)

	# A brighter line down the middle of the band, so the eye has something to
	# read the wave's position off without it implying an edge that is not there.
	_core = Polygon2D.new()
	_core.color = Color(0.72, 0.94, 1.0, 0.7)
	add_child(_core)

	_update_shape()

func _update_shape() -> void:
	if _band != null:
		_band.polygon = _arc_ring(_distance - band, _distance + band)

	if _core != null:
		_core.polygon = _arc_ring(_distance - band * CORE_FRACTION, _distance + band * CORE_FRACTION)
		# Fades as it runs out of reach, so a wave about to expire never looks
		# like one that still bites.
		var life := 1.0 - clampf(_distance / maxf(1.0, max_distance), 0.0, 1.0)
		_core.color = Color(0.72, 0.94, 1.0, 0.25 + 0.5 * life)

# The band between two real radii, spanning the arc. These are the same numbers
# _try_hit compares against, which is the entire point.
func _arc_ring(inner: float, outer: float) -> PackedVector2Array:
	var lo := maxf(0.0, inner)
	var hi := maxf(lo, outer)
	var points := PackedVector2Array()
	var half := deg_to_rad(arc_degrees) * 0.5
	var facing := direction.angle()

	for i in range(ARC_SEGMENTS + 1):
		var a := facing - half + (half * 2.0 * i / ARC_SEGMENTS)
		points.append(Vector2(cos(a), sin(a)) * hi)

	for i in range(ARC_SEGMENTS, -1, -1):
		var a := facing - half + (half * 2.0 * i / ARC_SEGMENTS)
		points.append(Vector2(cos(a), sin(a)) * lo)

	return points

static func spawn(host: Node, origin: Vector2, direction: Vector2, arc_degrees: float,
	speed: float, max_distance: float, damage: int, instigator: Node) -> BossSonicWave:
	var wave := BossSonicWave.new()
	wave.direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	wave.arc_degrees = arc_degrees
	wave.speed = speed
	wave.max_distance = max_distance
	wave.damage = damage
	wave.instigator = instigator

	var tree := host.get_tree()
	var parent: Node = tree.current_scene if tree != null else host.get_parent()
	if parent == null:
		parent = host

	parent.add_child(wave)
	wave.global_position = origin
	return wave
