extends Node2D
class_name BossSonicWave

# One expanding arc of sound, fired by The Belfry Tyrant. Travels outward from
# where it was spawned, widening as it goes, and hits the player once.
#
# Hit testing is a distance-and-angle check rather than an Area2D, for the same
# reason BossAoeTelegraph does it: the shape the player sees and the shape that
# hits them are then literally the same two numbers, and a growing physics
# shape cannot drift out of sync with the drawn one.

var direction: Vector2 = Vector2.RIGHT
var arc_degrees: float = 52.0
var speed: float = 300.0
var max_distance: float = 300.0
# Half-thickness of the band. A wave you can stand inside is a wave you can
# also stand behind, which is the whole dodge.
var band: float = 16.0
var damage: int = 16
var instigator: Node

var _origin: Vector2
var _distance: float = 8.0
var _spent: bool = false
var _band: Polygon2D
var _core: Polygon2D

func _ready() -> void:
	z_index = -1
	_origin = global_position
	_build_visuals()

func _process(delta: float) -> void:
	_distance += speed * delta
	if _distance >= max_distance:
		queue_free()
		return

	# The unit arc is drawn at radius 1 and scaled, so the band thickens as it
	# spreads — which is what a sound wave losing focus actually looks like.
	var scale_now := _distance
	if _band != null:
		_band.scale = Vector2.ONE * scale_now

	if _core != null:
		_core.scale = Vector2.ONE * scale_now
		# Fades as it runs out of reach, so a wave about to expire never looks
		# like one that still bites.
		var life := 1.0 - clampf(_distance / maxf(1.0, max_distance), 0.0, 1.0)
		_core.color = Color(0.72, 0.94, 1.0, 0.25 + 0.5 * life)

	if not _spent:
		_try_hit()

func _try_hit() -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	var local := player.global_position - _origin
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
	# Unit arc: outer edge at radius 1, inner edge pulled in by the band, both
	# scaled up every frame from the spawn point.
	var thickness := band / maxf(1.0, max_distance * 0.25)
	var points := PackedVector2Array()
	var half := deg_to_rad(arc_degrees) * 0.5
	var facing := direction.angle()
	var segments := 16

	for i in range(segments + 1):
		var a := facing - half + (deg_to_rad(arc_degrees) * i / segments)
		points.append(Vector2(cos(a), sin(a)))

	for i in range(segments, -1, -1):
		var a := facing - half + (deg_to_rad(arc_degrees) * i / segments)
		points.append(Vector2(cos(a), sin(a)) * (1.0 - thickness))

	_band = Polygon2D.new()
	_band.color = Color(0.45, 0.75, 0.9, 0.28)
	_band.polygon = points
	_band.scale = Vector2.ONE * _distance
	add_child(_band)

	_core = Polygon2D.new()
	_core.color = Color(0.72, 0.94, 1.0, 0.7)
	_core.polygon = _arc_line(facing, half, segments, thickness * 0.42)
	_core.scale = Vector2.ONE * _distance
	add_child(_core)

func _arc_line(facing: float, half: float, segments: int, thickness: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var a := facing - half + (half * 2.0 * i / segments)
		points.append(Vector2(cos(a), sin(a)))

	for i in range(segments, -1, -1):
		var a := facing - half + (half * 2.0 * i / segments)
		points.append(Vector2(cos(a), sin(a)) * (1.0 - thickness))

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
