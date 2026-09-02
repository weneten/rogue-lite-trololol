extends Node2D
class_name BossWhirlAura

# The live reach of a spin attack, drawn for as long as the spin runs.
#
# A BossAoeTelegraph would have been the obvious reuse, but it says the wrong
# thing here: its fill grows to announce a hit that has not landed yet. The
# whirlwind is already hitting, and it moves — what the player needs on the
# floor is not a countdown but a boundary that follows the boss. So this is a
# spinning ring at exactly the radius the hit check uses, parented to the boss
# so the two can never drift apart.

const FADE_IN := 0.12
const FADE_OUT := 0.18
const SPIN_SPEED := 7.5

const BAND_COLOR := Color(0.86, 0.20, 0.18, 0.16)
const EDGE_COLOR := Color(1.0, 0.42, 0.22, 0.62)

var radius: float = 120.0

var _age: float = 0.0
var _closing: bool = false
var _closing_age: float = 0.0
var _band: Polygon2D
var _edge: Polygon2D
var _blades: Node2D

func _ready() -> void:
	z_index = -1
	modulate.a = 0.0
	_build_visuals()

func _process(delta: float) -> void:
	_age += delta
	if _blades != null:
		_blades.rotation += SPIN_SPEED * delta

	if _closing:
		_closing_age += delta
		modulate.a = 1.0 - clampf(_closing_age / FADE_OUT, 0.0, 1.0)
		if _closing_age >= FADE_OUT:
			queue_free()

		return

	modulate.a = clampf(_age / FADE_IN, 0.0, 1.0)

# Lets the spin end on its own beat instead of the ring blinking out of
# existence the frame the boss stops swinging.
func close() -> void:
	_closing = true

func _build_visuals() -> void:
	_band = Polygon2D.new()
	_band.color = BAND_COLOR
	_band.polygon = _disc(radius, 30)
	add_child(_band)

	_edge = Polygon2D.new()
	_edge.color = EDGE_COLOR
	_edge.polygon = _ring(radius, 3.5, 30)
	add_child(_edge)

	# Two sweeps chasing each other around the rim: the ring alone says how far
	# the bell reaches, and these say that it is moving.
	_blades = Node2D.new()
	add_child(_blades)
	for i in range(2):
		var blade := Polygon2D.new()
		blade.color = Color(1.0, 0.55, 0.3, 0.35)
		blade.polygon = _arc(radius, 62.0, PI * i, 5.0)
		_blades.add_child(blade)

static func _disc(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var a := TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * radius)

	return points

static func _ring(radius: float, thickness: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var a := TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * radius)

	for i in range(segments, -1, -1):
		var a := TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * (radius - thickness))

	return points

static func _arc(radius: float, arc_degrees: float, offset: float, thickness: float) -> PackedVector2Array:
	var segments := 12
	var span := deg_to_rad(arc_degrees)
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var a := offset + span * i / segments
		points.append(Vector2(cos(a), sin(a)) * radius)

	for i in range(segments, -1, -1):
		var a := offset + span * i / segments
		points.append(Vector2(cos(a), sin(a)) * (radius - thickness))

	return points

# Factory: rides the boss, so the ring is wherever the bell currently is.
static func attach(host: Node2D, radius: float) -> BossWhirlAura:
	var aura := BossWhirlAura.new()
	aura.radius = radius
	host.add_child(aura)
	aura.position = Vector2.ZERO
	return aura
