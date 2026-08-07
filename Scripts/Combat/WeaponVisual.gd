extends Node2D
class_name WeaponVisual

# The copy of a weapon the player actually carries.
#
# These are the ONLY weapons a Hunter shows. The character sheets are drawn
# empty-handed (tools/pixelforge/cast.py), so what you see on your Hunter is
# exactly what you started with or bought — nothing decorative.
#
# Built at runtime by Weapon.gd and parented to the WIELDER, not to the Weapon
# node: the weapon's own transform is anchored at the body origin, which is the
# character's feet, so a visual hanging off it orbited their ankles. This rides
# at hand height instead.
#
# Every weapon rides the same side of the Hunter: whichever way the nearest
# enemy is. Each keeps a small fixed SlotOffset from that shared aim direction
# so a full loadout fans out instead of stacking into one sprite, but the
# cluster as a whole always faces the fight.
#
# The art is the same shape the shop card shows
# (Assets/sprites/weapons/mounted/), drawn pointing right with the grip on the
# centre pixel, so rotating the sprite turns the weapon about its grip.
#
# Everything here is cosmetic. Nothing in this file feeds damage, range or
# cooldown; if it fails to find art it simply draws nothing.

const MOUNT_DIR := "res://Assets/sprites/weapons/mounted/"

# The ring is an ellipse, not a circle: the arena is viewed at a slight angle,
# so a circular ring reads as weapons sliding up and down rather than sitting
# around the body.
#
# It is kept tight — roughly an arm's length on a 44-pixel Hunter. A wider ring
# reads as weapons orbiting a character rather than being held by one, which is
# the whole reason the Hunter sheets no longer bake a weapon into the hand.
const RING_RADIUS_X := 26.0
const RING_RADIUS_Y := 12.0

# Hand height above the body origin. The rig draws its characters standing on
# the origin with the front hand a little below chest, so everything carried has
# to be lifted to meet it.
const CARRY_HEIGHT := -22.0

# Angle the ring sits at with nothing in range: outward and slightly raised,
# the way you would hold a weapon waiting.
const REST_ANGLE := PI * 0.5

# How fast the ring and facing track their target, in radians per second.
# Snapping straight to the target angle makes the whole loadout twitch every
# time an enemy dies or a new one spawns.
const LEAN_SPEED := 7.0

# The near half of the ring sits in front of the wielder, the far half
# behind. Both are relative to the wielder's own root, so a carried weapon still
# Y-sorts against other fighters as part of one character.
const CARRY_Z := 3
const BEHIND_Z := -1

const BOB_AMPLITUDE := 1.3
const BOB_SPEED := 3.4

# Motion-trail ghosts, in frames of lag. Three samples is enough to smear a
# 0.16s swing into a readable arc; more just costs draw calls.
const TRAIL_LAG := [2, 4, 7]
const TRAIL_ALPHA := [0.42, 0.26, 0.14]

# This weapon's fixed offset from the shared aim direction, in radians. Set by
# Weapon from the slot index so a six-weapon loadout fans out instead of
# stacking into one pile. It never changes on its own — that is the whole point.
var slot_offset: float = 0.0:
	set(value):
		slot_offset = value
		# A weapon that just changed slots (something was sold) belongs at its
		# new offset immediately, not sliding across the body to reach it.
		_ring_angle = (_aim if _has_target else REST_ANGLE) + value

var _sprite: Sprite2D
var _ghosts: Array[Sprite2D] = []
var _history: Array = []
var _base_scale: float = 1.0
var _aim: float = 0.0
var _has_target: bool = false
var _time: float = 0.0
# Where the weapon currently sits on the ring, chasing the station (plus lean)
# rather than jumping to it.
var _ring_angle: float = 0.0
# Where it currently points. Also smoothed — an idle weapon snapping to face a
# newly spawned enemy across the arena reads as a glitch.
var _facing: float = 0.0
var _swing: Tween

# Driven by the swing tween and composed into the sprite transform every frame.
# Kept separate from the sprite's own properties so the idle bob and the orbit
# can keep running underneath a swing instead of fighting it for the transform.
var _swing_rotation: float = 0.0
var _swing_reach: float = 0.0
var _swing_scale: float = 1.0
var _swing_flash: float = 0.0

# Cache: several weapons of the same type share one texture, and a run can
# equip six at once.
static var _textures: Dictionary = {}


func setup(data: WeaponData, scale_factor: float = 1.0) -> void:
	var texture := _texture_for(data)
	if texture == null:
		return

	position = Vector2(0.0, CARRY_HEIGHT)
	_base_scale = scale_factor

	# Ghosts are added first so they draw under the weapon itself — a trail
	# painted over the blade reads as a smear rather than motion.
	for i in TRAIL_LAG.size():
		var ghost := Sprite2D.new()
		ghost.name = "Trail%d" % i
		ghost.texture = texture
		ghost.centered = true
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ghost.visible = false
		ghost.z_index = CARRY_Z
		add_child(ghost)
		_ghosts.append(ghost)

	_sprite = Sprite2D.new()
	_sprite.name = "Mount"
	_sprite.texture = texture
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * _base_scale
	_sprite.z_index = CARRY_Z
	add_child(_sprite)

	# Start at rest rather than sliding into place from the origin on the
	# first frame after being bought.
	_ring_angle = REST_ANGLE + slot_offset
	_facing = _rest_facing()
	_apply_transform()


# The mounted art is named after the icon, so no extra field on WeaponData has
# to be kept in sync — a weapon with an icon automatically has a carried copy.
static func _texture_for(data: WeaponData) -> Texture2D:
	if data == null or data.icon == null:
		return null

	var ident := data.icon.resource_path.get_file()
	if ident.is_empty():
		return null

	if _textures.has(ident):
		return _textures[ident]

	var path := MOUNT_DIR + ident
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = ResourceLoader.load(path, "Texture2D") as Texture2D

	_textures[ident] = texture
	return texture


func _process(delta: float) -> void:
	if _sprite == null:
		return

	_time += delta
	_track(delta)
	_apply_transform()
	_update_trail()


# Eases the ring position and the facing toward where the fight is. Both are
# rate-limited rather than assigned, so a weapon never teleports when its target
# dies or a new one spawns behind the Hunter.
func _track(delta: float) -> void:
	var step := minf(1.0, LEAN_SPEED * delta)

	var shared_angle := _aim if _has_target else REST_ANGLE
	var desired_ring := shared_angle + slot_offset

	_ring_angle = lerp_angle(_ring_angle, desired_ring, step)
	_facing = lerp_angle(_facing, _aim if _has_target else _rest_facing(), step)


# With nothing to shoot, a weapon points away from the Hunter along the rest
# angle, offset by its own slot so idle weapons stay just as spread out.
func _rest_facing() -> float:
	return REST_ANGLE + slot_offset - 0.35


# One place composes the final transform out of ring + bob + swing, so the tween
# and the idle motion can never overwrite each other.
func _apply_transform() -> void:
	var outward := Vector2(cos(_ring_angle), sin(_ring_angle))

	# The reach pushes the weapon along the direction it points, not along the
	# ring, so a thrust reads as a thrust wherever around the body it happens.
	var lunge := Vector2(cos(_facing), sin(_facing)) * _swing_reach

	_sprite.position = Vector2(outward.x * RING_RADIUS_X, outward.y * RING_RADIUS_Y) \
		+ Vector2(0.0, sin(_time * BOB_SPEED + slot_offset) * BOB_AMPLITUDE) + lunge
	_sprite.rotation = _facing + _swing_rotation

	# Weapons aimed left arrive upside down, so they are mirrored vertically —
	# which is what a person holding one would do.
	var flipped := absf(wrapf(_sprite.rotation, -PI, PI)) > PI * 0.5
	var magnitude := _base_scale * _swing_scale
	_sprite.scale = Vector2(magnitude, -magnitude if flipped else magnitude)

	# Front half of the ring (below the body's midline) draws over the Hunter,
	# far half behind them.
	_sprite.z_index = CARRY_Z if outward.y >= 0.0 else BEHIND_Z

	_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(Color(2.2, 2.1, 1.7), _swing_flash)


# A short history of where the weapon has been, replayed at a lag. Only visible
# while a swing owns the transform — a permanent trail on an idle weapon just
# looks like a rendering bug.
func _update_trail() -> void:
	_history.push_front({
		"position": _sprite.position,
		"rotation": _sprite.rotation,
		"scale": _sprite.scale,
	})
	var longest: int = int(TRAIL_LAG[TRAIL_LAG.size() - 1]) + 1
	while _history.size() > longest:
		_history.pop_back()

	var swinging := _swing != null and _swing.is_valid()
	for i in _ghosts.size():
		var ghost: Sprite2D = _ghosts[i]
		if not swinging:
			ghost.visible = false
			continue

		var lag: int = int(TRAIL_LAG[i])
		if lag >= _history.size():
			ghost.visible = false
			continue

		var sample: Dictionary = _history[lag]
		ghost.visible = true
		ghost.position = sample["position"]
		ghost.rotation = sample["rotation"]
		ghost.scale = sample["scale"]
		ghost.z_index = _sprite.z_index
		ghost.modulate = Color(1.4, 1.35, 1.15, float(TRAIL_ALPHA[i]))


# Melee weapons cut a wide arc; everything else kicks back like it fired. Both
# run off the same tween so a weapon can never be left mid-swing, and both end
# by returning every offset to neutral.
func play_swing(melee: bool) -> void:
	if _sprite == null:
		return

	if _swing != null and _swing.is_valid():
		_swing.kill()

	_swing = create_tween()
	_swing.set_trans(Tween.TRANS_CUBIC)

	if melee:
		# Wind up well behind the shoulder and cut through past the target. The
		# arc is deliberately wider than a real swing would be: at this sprite
		# size a subtle one is invisible in a crowd.
		_swing_rotation = -2.3
		_swing_reach = -7.0
		_swing_scale = 1.0
		_swing_flash = 0.0
		_swing.set_parallel(true)
		_swing.set_ease(Tween.EASE_OUT)
		_swing.tween_property(self, "_swing_rotation", 2.4, 0.17)
		_swing.tween_property(self, "_swing_reach", 16.0, 0.17)
		_swing.tween_property(self, "_swing_scale", 1.45, 0.09)
		_swing.tween_property(self, "_swing_flash", 1.0, 0.05)
		_swing.chain()
		_swing.set_parallel(true)
		_swing.set_ease(Tween.EASE_IN_OUT)
		_swing.tween_property(self, "_swing_rotation", 0.0, 0.24)
		_swing.tween_property(self, "_swing_reach", 0.0, 0.24)
		_swing.tween_property(self, "_swing_scale", 1.0, 0.24)
		_swing.tween_property(self, "_swing_flash", 0.0, 0.16)
	else:
		# Muzzle jump: snap forward and grow on the shot, then settle back.
		_swing_rotation = 0.0
		_swing_reach = 10.0
		_swing_scale = 1.4
		_swing_flash = 1.0
		_swing.set_parallel(true)
		_swing.set_ease(Tween.EASE_OUT)
		_swing.tween_property(self, "_swing_rotation", -0.5, 0.07)
		_swing.tween_property(self, "_swing_reach", -9.0, 0.07)
		_swing.tween_property(self, "_swing_flash", 0.0, 0.12)
		_swing.chain()
		_swing.set_parallel(true)
		_swing.set_ease(Tween.EASE_IN_OUT)
		_swing.tween_property(self, "_swing_rotation", 0.0, 0.22)
		_swing.tween_property(self, "_swing_reach", 0.0, 0.22)
		_swing.tween_property(self, "_swing_scale", 1.0, 0.22)


# Points the weapon along `angle`. With no target it falls back to its resting
# outward pose rather than freezing wherever the last target happened to die.
func set_aim(angle: float, has_target: bool) -> void:
	_aim = angle
	_has_target = has_target
