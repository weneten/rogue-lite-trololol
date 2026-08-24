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
# While an enemy is on camera every weapon rides that side of the Hunter and
# points at them. Each keeps a small fixed SlotOffset from that shared aim
# so a full loadout fans out instead of stacking into one sprite. When the
# screen is empty the same offsets whirl around the body as a group.
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

# How fast the ring orbits toward the fight, and how fast the blade itself
# turns to face it. Facing is snappier: a weapon that slides around the body
# is fine, one that lags its aim reads as broken.
const LEAN_SPEED := 9.0
const FACE_SPEED := 16.0

# Radians per second the whole loadout whirls when nothing is on camera.
const SPIN_SPEED := 2.8

# Hold the cluster a little behind the line of fire so the sprites sit in the
# hands rather than glued to the aim vector.
const HOLD_BIAS := -0.18

# The near half of the ring sits in front of the wielder, the far half
# behind. Both are relative to the wielder's own root, so a carried weapon still
# Y-sorts against other fighters as part of one character.
const CARRY_Z := 3
const BEHIND_Z := -1

const BOB_AMPLITUDE := 1.6
const BOB_SPEED := 3.8

# Motion-trail ghosts, in frames of lag. Four samples smear a slash into a
# readable arc without turning idle weapons into a smear.
const TRAIL_LAG := [1, 3, 5, 8]
const TRAIL_ALPHA := [0.5, 0.32, 0.18, 0.08]

# This weapon's fixed offset from the shared aim direction, in radians. Set by
# Weapon from the slot index so a six-weapon loadout fans out instead of
# stacking into one pile. It never changes on its own — that is the whole point.
var slot_offset: float = 0.0:
	set(value):
		slot_offset = value
		# A weapon that just changed slots (something was sold) belongs at its
		# new offset immediately, not sliding across the body to reach it.
		_ring_angle = (_aim + HOLD_BIAS if _has_target else _spin_phase) + value

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
var _swing_lift: float = 0.0
var _swing_lateral: float = 0.0
# Continuously advancing orbit used when nothing is on screen. Kept in sync
# with the ring while aiming so dropping into a spin never teleports.
var _spin_phase: float = PI * 0.5

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

	# Start already spinning rather than sliding into place from the origin
	# on the first frame after being bought.
	_spin_phase = PI * 0.5
	_ring_angle = _spin_phase + slot_offset
	_facing = _ring_angle
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


# Eases the ring and facing toward the fight, or whirls the loadout when the
# screen is empty. Rate-limited so a weapon never teleports when a target dies
# or a new one spawns behind the Hunter.
func _track(delta: float) -> void:
	if _has_target:
		var orbit_step := minf(1.0, LEAN_SPEED * delta)
		var face_step := minf(1.0, FACE_SPEED * delta)
		var desired_ring := _aim + HOLD_BIAS + slot_offset
		_ring_angle = lerp_angle(_ring_angle, desired_ring, orbit_step)
		_facing = lerp_angle(_facing, _aim, face_step)
		# Keep the spin phase glued to the current station so dropping into a
		# whirl continues from here instead of snapping back to a rest angle.
		_spin_phase = _ring_angle - slot_offset
	else:
		_spin_phase += SPIN_SPEED * delta
		_ring_angle = _spin_phase + slot_offset
		# Point along the orbit, with a slight lead so a whirl reads as motion
		# rather than a rigid pinwheel.
		var face_step := minf(1.0, FACE_SPEED * delta)
		_facing = lerp_angle(_facing, _ring_angle + 0.45, face_step)


# One place composes the final transform out of ring + bob + swing, so the tween
# and the idle motion can never overwrite each other.
func _apply_transform() -> void:
	var outward := Vector2(cos(_ring_angle), sin(_ring_angle))
	var aim_dir := Vector2(cos(_facing), sin(_facing))
	var side := Vector2(-aim_dir.y, aim_dir.x)

	# Reach along the aim, lateral across it (the slash sweep), lift is screen-Y
	# so a chop drops the blade rather than sliding along the orbit.
	var lunge := aim_dir * _swing_reach + side * _swing_lateral
	var bob := sin(_time * BOB_SPEED + slot_offset) * BOB_AMPLITUDE
	var radius_x := RING_RADIUS_X
	var radius_y := RING_RADIUS_Y
	if not _has_target:
		bob *= 0.45
		var flare := 1.0 + 0.05 * sin(_time * 5.2)
		radius_x *= flare
		radius_y *= flare

	_sprite.position = Vector2(outward.x * radius_x, outward.y * radius_y) \
		+ Vector2(0.0, bob + _swing_lift) + lunge
	_sprite.rotation = _facing + _swing_rotation

	# Weapons aimed left arrive upside down, so they are mirrored vertically —
	# which is what a person holding one would do.
	var flipped := absf(wrapf(_sprite.rotation, -PI, PI)) > PI * 0.5
	var magnitude := _base_scale * _swing_scale
	_sprite.scale = Vector2(magnitude, -magnitude if flipped else magnitude)

	# Front half of the ring (below the body's midline) draws over the Hunter,
	# far half behind them.
	_sprite.z_index = CARRY_Z if outward.y >= 0.0 else BEHIND_Z

	_sprite.modulate = Color(1.0, 1.0, 1.0).lerp(Color(2.35, 2.2, 1.65), _swing_flash)


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

	var swinging := _swing != null and _swing.is_running()
	var whirling := not _has_target
	for i in _ghosts.size():
		var ghost: Sprite2D = _ghosts[i]
		if not swinging and not whirling:
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
		var alpha := float(TRAIL_ALPHA[i])
		if whirling and not swinging:
			alpha *= 0.4
			ghost.modulate = Color(1.15, 1.2, 1.35, alpha)
		else:
			ghost.modulate = Color(1.45, 1.38, 1.12, alpha)


# Class-aware attack motion. Every path runs off one tween so a weapon can
# never be left mid-swing, and every path returns the offsets to neutral.
func play_swing(weapon_class: int = 0) -> void:
	if _sprite == null:
		return

	if _swing != null and _swing.is_valid():
		_swing.kill()

	_swing = create_tween()

	if (weapon_class & WeaponData.WeaponClass.MELEE) != 0:
		_play_melee_slash()
	elif (weapon_class & WeaponData.WeaponClass.TRAP) != 0:
		_play_plant()
	elif (weapon_class & WeaponData.WeaponClass.FIREARM) != 0:
		_play_recoil()
	elif (weapon_class & WeaponData.WeaponClass.MAGIC) != 0 \
			or (weapon_class & WeaponData.WeaponClass.AOE) != 0:
		_play_cast()
	else:
		_play_thrust()


func _play_melee_slash() -> void:
	# Anticipation behind the shoulder, then a snap through the target that
	# actually travels sideways so the trail reads as an arc, not a spin.
	_swing_rotation = 0.0
	_swing_reach = 0.0
	_swing_scale = 1.0
	_swing_flash = 0.0
	_swing_lift = 0.0
	_swing_lateral = 0.0

	_swing.set_parallel(true)
	_swing.set_trans(Tween.TRANS_CUBIC)
	_swing.set_ease(Tween.EASE_IN)
	_swing.tween_property(self, "_swing_rotation", -2.15, 0.09)
	_swing.tween_property(self, "_swing_reach", -9.0, 0.09)
	_swing.tween_property(self, "_swing_lateral", -11.0, 0.09)
	_swing.tween_property(self, "_swing_lift", -3.0, 0.09)
	_swing.tween_property(self, "_swing_scale", 0.92, 0.09)

	_swing.chain()
	_swing.set_parallel(true)
	_swing.set_trans(Tween.TRANS_EXPO)
	_swing.set_ease(Tween.EASE_OUT)
	_swing.tween_property(self, "_swing_rotation", 2.55, 0.11)
	_swing.tween_property(self, "_swing_reach", 20.0, 0.11)
	_swing.tween_property(self, "_swing_lateral", 12.0, 0.11)
	_swing.tween_property(self, "_swing_lift", 5.0, 0.11)
	_swing.tween_property(self, "_swing_scale", 1.52, 0.08)
	_swing.tween_property(self, "_swing_flash", 1.0, 0.04)

	_swing.chain()
	_settle_swing(0.22, Tween.TRANS_BACK)


func _play_recoil() -> void:
	# Muzzle flash, then kick back and climb, then spring home.
	_swing_rotation = 0.18
	_swing_reach = 9.0
	_swing_scale = 1.55
	_swing_flash = 1.0
	_swing_lift = -2.0
	_swing_lateral = 0.0

	_swing.set_parallel(true)
	_swing.set_trans(Tween.TRANS_QUAD)
	_swing.set_ease(Tween.EASE_OUT)
	_swing.tween_property(self, "_swing_rotation", -0.72, 0.08)
	_swing.tween_property(self, "_swing_reach", -12.0, 0.08)
	_swing.tween_property(self, "_swing_lift", -5.0, 0.08)
	_swing.tween_property(self, "_swing_scale", 1.12, 0.08)
	_swing.tween_property(self, "_swing_flash", 0.0, 0.12)

	_swing.chain()
	_settle_swing(0.2, Tween.TRANS_BACK)


func _play_thrust() -> void:
	# Draw back, then a linear stab along the aim — bows, thrown knives.
	_swing_rotation = 0.0
	_swing_reach = 0.0
	_swing_scale = 1.0
	_swing_flash = 0.0
	_swing_lift = 0.0
	_swing_lateral = 0.0

	_swing.set_parallel(true)
	_swing.set_trans(Tween.TRANS_CUBIC)
	_swing.set_ease(Tween.EASE_IN)
	_swing.tween_property(self, "_swing_reach", -8.0, 0.08)
	_swing.tween_property(self, "_swing_rotation", -0.18, 0.08)
	_swing.tween_property(self, "_swing_scale", 0.9, 0.08)

	_swing.chain()
	_swing.set_parallel(true)
	_swing.set_trans(Tween.TRANS_EXPO)
	_swing.set_ease(Tween.EASE_OUT)
	_swing.tween_property(self, "_swing_reach", 16.0, 0.1)
	_swing.tween_property(self, "_swing_rotation", 0.12, 0.1)
	_swing.tween_property(self, "_swing_scale", 1.38, 0.08)
	_swing.tween_property(self, "_swing_flash", 0.85, 0.04)

	_swing.chain()
	_settle_swing(0.18, Tween.TRANS_CUBIC)


func _play_cast() -> void:
	# Rise and gather, then pulse toward the target.
	_swing_rotation = 0.0
	_swing_reach = 0.0
	_swing_scale = 1.0
	_swing_flash = 0.0
	_swing_lift = 0.0
	_swing_lateral = 0.0

	_swing.set_parallel(true)
	_swing.set_trans(Tween.TRANS_CUBIC)
	_swing.set_ease(Tween.EASE_OUT)
	_swing.tween_property(self, "_swing_lift", -10.0, 0.1)
	_swing.tween_property(self, "_swing_rotation", 0.55, 0.1)
	_swing.tween_property(self, "_swing_scale", 1.22, 0.1)
	_swing.tween_property(self, "_swing_flash", 0.55, 0.1)

	_swing.chain()
	_swing.set_parallel(true)
	_swing.set_trans(Tween.TRANS_EXPO)
	_swing.set_ease(Tween.EASE_OUT)
	_swing.tween_property(self, "_swing_lift", 3.0, 0.1)
	_swing.tween_property(self, "_swing_reach", 12.0, 0.1)
	_swing.tween_property(self, "_swing_rotation", -0.35, 0.1)
	_swing.tween_property(self, "_swing_scale", 1.42, 0.08)
	_swing.tween_property(self, "_swing_flash", 1.0, 0.04)

	_swing.chain()
	_settle_swing(0.2, Tween.TRANS_BACK)


func _play_plant() -> void:
	# Raise, then stamp into the ground.
	_swing_rotation = 0.0
	_swing_reach = 0.0
	_swing_scale = 1.0
	_swing_flash = 0.0
	_swing_lift = 0.0
	_swing_lateral = 0.0

	_swing.set_parallel(true)
	_swing.set_trans(Tween.TRANS_CUBIC)
	_swing.set_ease(Tween.EASE_OUT)
	_swing.tween_property(self, "_swing_lift", -12.0, 0.08)
	_swing.tween_property(self, "_swing_rotation", 0.55, 0.08)
	_swing.tween_property(self, "_swing_scale", 1.1, 0.08)

	_swing.chain()
	_swing.set_parallel(true)
	_swing.set_trans(Tween.TRANS_EXPO)
	_swing.set_ease(Tween.EASE_IN)
	_swing.tween_property(self, "_swing_lift", 7.0, 0.09)
	_swing.tween_property(self, "_swing_rotation", 0.12, 0.09)
	_swing.tween_property(self, "_swing_scale", 1.28, 0.09)
	_swing.tween_property(self, "_swing_flash", 0.7, 0.04)

	_swing.chain()
	_settle_swing(0.16, Tween.TRANS_CUBIC)


func _settle_swing(duration: float, trans: Tween.TransitionType) -> void:
	_swing.set_parallel(true)
	_swing.set_trans(trans)
	_swing.set_ease(Tween.EASE_OUT)
	_swing.tween_property(self, "_swing_rotation", 0.0, duration)
	_swing.tween_property(self, "_swing_reach", 0.0, duration)
	_swing.tween_property(self, "_swing_lateral", 0.0, duration)
	_swing.tween_property(self, "_swing_lift", 0.0, duration)
	_swing.tween_property(self, "_swing_scale", 1.0, duration)
	_swing.tween_property(self, "_swing_flash", 0.0, duration * 0.7)


# Points the weapon along `angle`. With no target the ring whirls instead of
# freezing wherever the last target happened to die.
func set_aim(angle: float, has_target: bool) -> void:
	_aim = angle
	_has_target = has_target
