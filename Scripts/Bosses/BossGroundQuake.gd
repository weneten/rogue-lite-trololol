extends Node2D
class_name BossGroundQuake

# The floor splitting open where something very heavy landed on it. Purely
# visual: the boss that spawned it resolves the damage, because only the boss
# knows its own phase multiplier and only it can tell an epicentre hit from a
# glancing one.
#
# The picture is three layers, and each one is answering a different question:
#
#   fissures   how far the ground broke — the outer radius, drawn as spokes
#              rather than a disc so the crater does not read as another
#              telegraph the player still has to dodge
#   crater     where standing was fatal — the epicentre, at its real radius
#   ring       the shock leaving, which is the part that says "this is over"
#
# The spokes grow outward over OPEN_SECONDS rather than appearing whole. An
# impact that is simply there on one frame reads as a decal; one that opens
# reads as force.

const OPEN_SECONDS := 0.16
const RING_SECONDS := 0.42
const RING_OVERSHOOT := 1.35

const CRACK_COLOR := Color(0.10, 0.07, 0.09, 0.92)
const CRACK_GLOW := Color(0.72, 0.24, 0.20, 0.75)
const CRATER_COLOR := Color(0.16, 0.09, 0.11, 0.85)
const RING_COLOR := Color(0.80, 0.75, 0.66, 0.55)

var radius: float = 150.0
var epicenter_radius: float = 50.0
var fissures: int = 7
# How long the scar stays on the floor before it has finished fading out.
var lifetime: float = 2.2

var _age: float = 0.0
var _spokes: Array[Polygon2D] = []
var _glows: Array[Polygon2D] = []
var _crater: Polygon2D
var _ring: Polygon2D

func _ready() -> void:
	z_index = -1
	_build_visuals()

func _process(delta: float) -> void:
	_age += delta

	var open := clampf(_age / OPEN_SECONDS, 0.0, 1.0) if OPEN_SECONDS > 0.0 else 1.0
	# Eased so the crack whips out and settles instead of sliding at one speed.
	var extend := 1.0 - pow(1.0 - open, 3.0)
	for spoke in _spokes:
		spoke.scale = Vector2(maxf(0.001, extend), maxf(0.001, extend))

	for glow in _glows:
		glow.scale = Vector2(maxf(0.001, extend), maxf(0.001, extend))
		# The heat in the crack is the impact itself, so it is gone well before
		# the crack is.
		glow.color = Color(CRACK_GLOW.r, CRACK_GLOW.g, CRACK_GLOW.b,
			CRACK_GLOW.a * (1.0 - clampf(_age / (OPEN_SECONDS * 3.0), 0.0, 1.0)))

	if _crater != null:
		_crater.scale = Vector2(maxf(0.001, extend), maxf(0.001, extend))

	if _ring != null:
		var ring_t := clampf(_age / RING_SECONDS, 0.0, 1.0)
		_ring.scale = Vector2.ONE * maxf(0.001, ring_t * RING_OVERSHOOT)
		_ring.color = Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, RING_COLOR.a * (1.0 - ring_t))

	if _age >= lifetime:
		queue_free()
		return

	# Everything fades together over the last third, so the scar leaves as one
	# object rather than in pieces.
	var fade_from := lifetime * 0.66
	if _age > fade_from:
		modulate.a = 1.0 - clampf((_age - fade_from) / maxf(0.01, lifetime - fade_from), 0.0, 1.0)

func _build_visuals() -> void:
	_crater = Polygon2D.new()
	_crater.color = CRATER_COLOR
	_crater.polygon = _circle(epicenter_radius, 20)
	add_child(_crater)

	var count := maxi(3, fissures)
	for i in range(count):
		# Jittered off the even spacing: a perfect star reads as a rune someone
		# drew, not as rock giving way.
		var angle := TAU * i / count + randf_range(-0.22, 0.22)
		var length := radius * randf_range(0.86, 1.0)
		var points := _fissure(angle, length)

		var spoke := Polygon2D.new()
		spoke.color = CRACK_COLOR
		spoke.polygon = points
		add_child(spoke)
		_spokes.append(spoke)

		var glow := Polygon2D.new()
		glow.color = CRACK_GLOW
		glow.polygon = _fissure(angle, length * 0.82, 0.45)
		add_child(glow)
		_glows.append(glow)

	_ring = Polygon2D.new()
	_ring.color = RING_COLOR
	_ring.polygon = _ring_band(radius, 0.1)
	_ring.scale = Vector2.ONE * 0.001
	add_child(_ring)

# One crack: a strip that starts wide at the epicentre and tapers to nothing,
# with its spine wandering so no two look stamped from the same mould.
func _fissure(angle: float, length: float, width_scale: float = 1.0) -> PackedVector2Array:
	var forward := Vector2(cos(angle), sin(angle))
	var side := Vector2(-forward.y, forward.x)
	var segments := 6
	var base_width := maxf(4.0, length * 0.085) * width_scale

	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var drift := 0.0
	for i in range(segments + 1):
		var t := float(i) / segments
		drift += randf_range(-1.0, 1.0) * length * 0.035
		var spine := forward * (length * t) + side * drift
		var half := base_width * (1.0 - t) * 0.5 + 0.6
		left.append(spine + side * half)
		right.append(spine - side * half)

	var points := PackedVector2Array()
	for p in left:
		points.append(p)

	for i in range(right.size() - 1, -1, -1):
		points.append(right[i])

	return points

func _ring_band(radius: float, thickness: float) -> PackedVector2Array:
	var segments := 28
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var a := TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * radius)

	for i in range(segments, -1, -1):
		var a := TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * radius * (1.0 - thickness))

	return points

static func _circle(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var a := TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * radius)

	return points

# Factory: drops a quake on the floor at a world position, alongside the
# entities rather than under the boss, so it stays put while the boss walks off.
static func spawn(host: Node, global_position: Vector2, radius: float,
	epicenter_radius: float, fissures: int = 7, lifetime: float = 2.2) -> BossGroundQuake:
	var quake := BossGroundQuake.new()
	quake.radius = radius
	quake.epicenter_radius = epicenter_radius
	quake.fissures = fissures
	quake.lifetime = lifetime

	var tree := host.get_tree()
	var parent: Node = tree.current_scene if tree != null else host.get_parent()
	if parent == null:
		parent = host

	parent.add_child(quake)
	quake.global_position = global_position
	return quake
