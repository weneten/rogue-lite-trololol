extends Node2D
class_name BloodPulseAura

# The Crimson Voivode's aura, as a heartbeat rather than a standing field.
#
# It used to be a circle around him that ticked damage every 0.3s for as long as
# it lasted, which gave the player nothing to react to — you were either inside
# it and bleeding or outside it and safe, and the only decision was made once.
# Now it beats: every PULSE_INTERVAL a ring of blood throws itself outward from
# him, and it hits you once, when its edge reaches you. Between beats his feet
# are safe. That turns a wall into a rhythm, and a rhythm is something you can
# step through.
#
# The ring that damages is the ring that is drawn, and not approximately. The
# sprite frame is chosen from the pulse's own progress rather than played on the
# animator's clock, and the reach for that frame is read out of PULSE_GROWTH —
# a table measured off the artwork itself. So there is exactly one number, and
# both the picture and the hit test are derived from it.
#
# Damage routes back through the boss, like BloodField's, so a phase that hits
# harder pulses harder and the drain still feeds him.

const SHEET_PATH := "res://Assets/sprites/vfx/blood_aura/blood_aura.png"
const SHEET_JSON := "res://Assets/sprites/vfx/blood_aura/blood_aura.json"

# How far the ring has actually spread on each frame, as a fraction of its full
# reach. Printed by tools/build_blood_vfx.py from the source art; it climbs for
# seven frames and then holds while the crown of spray settles. Clamped
# non-decreasing there, because a damage front that retreats is not a front.
const PULSE_GROWTH: Array[float] = [
	0.467, 0.610, 0.721, 0.817, 0.865, 0.910, 0.939, 1.000, 1.000, 1.000, 1.000, 1.000,
]

# The ring is drawn in perspective — it lies on the floor, so it is a good deal
# wider than it is deep. The hit test is the same ellipse, because a circular
# one would punish a player standing where there is visibly no blood.
const PULSE_ASPECT := 0.40

# The ring's radius as a fraction of the frame on the sheet. Kept in step with
# AURA_RADIUS_RATIO in tools/build_blood_vfx.py.
const SHEET_RING_RADIUS_RATIO := 0.45

# 12 frames at 14 fps. Held here rather than read off the sheet because it is
# the pulse's clock, not the animator's — see the note about frame choice above.
const PULSE_SECONDS := 0.857

# Gap between beats. Long enough to walk out of a ring and be somewhere else
# when the next one arrives.
const PULSE_INTERVAL := 1.15

var radius: float = 200.0
var damage: int = 7
var lifetime: float = 6.0
# Fraction of damage dealt that heals the owner. This is how he feeds.
var drain_fraction: float = 0.0
var owner_boss: Boss
# The aura rides its carrier; each beat goes off wherever he is standing.
var carrier: Node2D

var _age: float
var _next_pulse: float
var _frames: SpriteFrames
var _frame_count: int
var _sprite_scale: float = 1.0
# One entry per beat in flight: {node, age, hit}.
var _pulses: Array[Dictionary] = []

func _ready() -> void:
	z_index = -1
	_frames = SpriteSheetCache.get_frames(SHEET_PATH, SHEET_JSON)
	if _frames != null and _frames.has_animation("pulse"):
		_frame_count = _frames.get_frame_count("pulse")
		var texture := _frames.get_frame_texture("pulse", 0)
		if texture != null and texture.get_width() > 0:
			_sprite_scale = radius / (texture.get_width() * SHEET_RING_RADIUS_RATIO)
	else:
		_frames = null

	# Beat immediately: the wind-up already told the player something was coming,
	# and a first pulse a second late reads as the attack having failed.
	_emit_pulse()

func _process(delta: float) -> void:
	_age += delta

	if carrier != null:
		if not is_instance_valid(carrier):
			carrier = null
		else:
			global_position = carrier.global_position

	_next_pulse -= delta
	if _next_pulse <= 0.0 and _age < lifetime:
		_emit_pulse()

	_tick_pulses(delta)

	# Outlives its own lifetime by however long the last beat needs to finish;
	# a ring cut off mid-expansion would take its damage window with it.
	if _age >= lifetime and _pulses.is_empty():
		queue_free()

func _emit_pulse() -> void:
	_next_pulse = PULSE_INTERVAL

	var node: Node2D
	if _frames != null:
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = _frames
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.centered = true
		sprite.offset = SpriteSheetCache.get_sprite_offset(SHEET_PATH)
		sprite.animation = "pulse"
		sprite.scale = Vector2.ONE * _sprite_scale
		node = sprite
	else:
		node = _build_fallback_ring()

	add_child(node)
	_pulses.append({"node": node, "age": 0.0, "hit": false})

func _tick_pulses(delta: float) -> void:
	var survivors: Array[Dictionary] = []
	for pulse in _pulses:
		pulse["age"] = pulse["age"] + delta
		var progress: float = clampf(pulse["age"] / PULSE_SECONDS, 0.0, 1.0)

		var node: Node2D = pulse["node"]
		if not is_instance_valid(node):
			continue

		# The drawn frame and the damaging reach both come off this one index.
		var index := clampi(int(progress * PULSE_GROWTH.size()), 0, PULSE_GROWTH.size() - 1)
		var reach := radius * PULSE_GROWTH[index]

		if node is AnimatedSprite2D:
			(node as AnimatedSprite2D).frame = clampi(index, 0, maxi(0, _frame_count - 1))
		else:
			node.scale = Vector2(reach, reach * PULSE_ASPECT)
			node.modulate = Color(0.85, 0.11, 0.16, 0.75 * (1.0 - progress))

		if not pulse["hit"] and _reaches_player(reach):
			pulse["hit"] = true
			_bite()

		if pulse["age"] >= PULSE_SECONDS:
			node.queue_free()
			continue

		survivors.append(pulse)

	_pulses = survivors

# Inside the drawn ellipse, not inside a circle drawn around it.
func _reaches_player(reach: float) -> bool:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null or reach <= 0.0:
		return false

	var local := player.global_position - global_position
	var down := reach * PULSE_ASPECT
	return (local.x * local.x) / (reach * reach) + (local.y * local.y) / (down * down) <= 1.0

func _bite() -> void:
	if owner_boss != null and is_instance_valid(owner_boss):
		# Through the boss: it owns the phase damage multiplier and the drain.
		owner_boss.apply_damage_to_player(damage, drain_fraction)
		return

	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health != null and not health.is_dead:
		health.take_damage(damage, self)

# Shown only when the sheet will not load. A unit ellipse, scaled to the reach
# every frame — the same shape the hit test uses, so the fallback is wrong about
# how it looks and right about where it bites.
func _build_fallback_ring() -> Node2D:
	var ring := Polygon2D.new()
	var segments := 30
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var a := TAU * i / segments
		points.append(Vector2(cos(a), sin(a)))

	for i in range(segments, -1, -1):
		var a := TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * 0.86)

	ring.polygon = points
	ring.color = Color(0.85, 0.11, 0.16, 0.0)
	return ring

# Factory: rides `carrier`, beating until `lifetime` runs out.
static func spawn(host: Node, carrier: Node2D, radius: float, damage: int,
	lifetime: float, boss: Boss, drain_fraction: float) -> BloodPulseAura:
	var aura := BloodPulseAura.new()
	aura.radius = radius
	aura.damage = damage
	aura.lifetime = lifetime
	aura.owner_boss = boss
	aura.drain_fraction = drain_fraction
	aura.carrier = carrier

	var tree := host.get_tree()
	var parent: Node = tree.current_scene if tree != null else host.get_parent()
	if parent == null:
		parent = host

	parent.add_child(aura)
	aura.global_position = carrier.global_position
	return aura
