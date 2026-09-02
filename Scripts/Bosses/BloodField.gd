extends Node2D
class_name BloodField

# A patch of ground that hurts to stand in: dropped where it lands, static,
# long-lived, and ticking damage at anyone who stands in it.
#
# This used to double as the boss's carried aura, on the argument that one class
# meant one place to fix the damage cadence. That held only while the two shared
# a cadence. The aura is a pulse now — see BloodPulseAura — and the two have
# nothing left in common but the colour.
#
# Damage is routed back through the boss rather than applied here, so a phase
# that doubles the boss's damage doubles what its pools do — including pools
# that were already on the floor when the phase changed.

const TICK_SECONDS := 0.3

const SHEET_PATH := "res://Assets/sprites/vfx/blood_pool/blood_pool.png"
const SHEET_JSON := "res://Assets/sprites/vfx/blood_pool/blood_pool.json"

# The sheet is authored so the pool body's radius is exactly this fraction of
# the frame — see tools/build_blood_pool.py, which pins the same number. It is
# what lets the blood on screen be the circle _bite() tests against instead of
# merely being about that big.
const SHEET_POOL_RADIUS_RATIO := 0.4

var radius: float = 70.0
var damage: int = 6
var lifetime: float = 8.0
# Fraction of damage dealt that heals the owner. The aura is how he feeds.
var drain_fraction: float = 0.0
var owner_boss: Boss

var _age: float
var _tick_remaining: float = TICK_SECONDS
var _sprite: AnimatedSprite2D
# Kept and shown only when the sheet will not load, the same bargain the bosses
# strike with their placeholder polygons: a hazard must never be invisible.
var _fill: Polygon2D
var _rim: Polygon2D
var _shape: PackedVector2Array

func _ready() -> void:
	z_index = -1
	_build_visuals()

func _process(delta: float) -> void:
	_age += delta

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
	# Spreading out as it arrives, the same tell the polygon gave.
	var spread := 0.86 + 0.14 * fade_in

	if _sprite != null:
		# No extra pulse on top: the artwork already boils on its own, and a
		# second rhythm over it just read as the pool breathing.
		_sprite.modulate = Color(1.0, 1.0, 1.0, life)
		_sprite.scale = Vector2.ONE * _sprite_scale() * spread
		return

	var pulse := 0.82 + 0.18 * sin(_age * 5.0)
	if _fill != null:
		_fill.color = Color(0.42, 0.03, 0.07, 0.62 * life)
		_fill.scale = Vector2.ONE * spread * pulse

	if _rim != null:
		_rim.color = Color(0.85, 0.11, 0.16, 0.85 * life)
		_rim.scale = _fill.scale if _fill != null else Vector2.ONE

func _build_visuals() -> void:
	if _build_sprite():
		return

	_shape = _blob(radius, 22)

	_fill = Polygon2D.new()
	_fill.color = Color(0.42, 0.03, 0.07, 0.0)
	_fill.polygon = _shape
	add_child(_fill)

	_rim = Polygon2D.new()
	_rim.color = Color(0.85, 0.11, 0.16, 0.0)
	_rim.polygon = _ring(_shape, 4.0)
	add_child(_rim)

# Returns whether the sheet actually loaded; the caller falls back to polygons
# when it did not.
func _build_sprite() -> bool:
	var frames := SpriteSheetCache.get_frames(SHEET_PATH, SHEET_JSON)
	if frames == null or not frames.has_animation("pool"):
		return false

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	_sprite.offset = SpriteSheetCache.get_sprite_offset(SHEET_PATH)
	_sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_sprite.scale = Vector2.ONE * _sprite_scale()
	add_child(_sprite)
	_sprite.play("pool")
	# Started somewhere random in the loop. He drops four pools at once, and in
	# lockstep they read as one animation stamped four times rather than four
	# separate puddles.
	_sprite.frame = randi() % maxi(1, frames.get_frame_count("pool"))
	return true

# Blows the frame up so the drawn pool spans `radius`. Read off the texture
# rather than hardcoded, so a re-exported sheet at a different cell size still
# lands on the hitbox.
func _sprite_scale() -> float:
	if _sprite == null or _sprite.sprite_frames == null:
		return 1.0

	var texture := _sprite.sprite_frames.get_frame_texture("pool", 0)
	if texture == null or texture.get_width() <= 0:
		return 1.0

	return radius / (texture.get_width() * SHEET_POOL_RADIUS_RATIO)

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
	var field := BloodField.new()
	field.radius = radius
	field.damage = damage
	field.lifetime = lifetime
	field.owner_boss = boss

	var tree := host.get_tree()
	var parent: Node = tree.current_scene if tree != null else host.get_parent()
	if parent == null:
		parent = host

	parent.add_child(field)
	field.global_position = position
	return field
