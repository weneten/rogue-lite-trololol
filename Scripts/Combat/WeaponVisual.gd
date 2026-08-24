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

# Attack motion is stepped in _process rather than tweened. Tweens bound to this
# node were easy to lose against the orbit, and flipping the sprite off the
# composed slash angle made a swing look like a flicker instead of a hit.
enum SwingKind { NONE, MELEE, RECOIL, THRUST, CAST, PLANT }
var _swing_kind: SwingKind = SwingKind.NONE
var _swing_time: float = 0.0
var _swing_duration: float = 0.0
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
	# painted over the blade reads as a smear rather than motion. Skip them
	# in the browser: six weapons × four extra sprites is a lot of overdraw.
	if not OS.has_feature("web"):
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
	_advance_swing(delta)
	_track(delta)
	_apply_transform()
	_update_trail()


# Eases the ring and facing toward the fight, or whirls the loadout when the
# screen is empty. Rate-limited so a weapon never teleports when a target dies
# or a new one spawns behind the Hunter.
func _track(delta: float) -> void:
	# Hold station during a swing so the slash isn't cancelled by the orbit
	# sliding the grip around the body mid-cut.
	var swinging := _swing_kind != SwingKind.NONE
	if _has_target:
		if not swinging:
			var orbit_step := minf(1.0, LEAN_SPEED * delta)
			var desired_ring := _aim + HOLD_BIAS + slot_offset
			_ring_angle = lerp_angle(_ring_angle, desired_ring, orbit_step)
			_spin_phase = _ring_angle - slot_offset
		var face_step := minf(1.0, FACE_SPEED * delta)
		_facing = lerp_angle(_facing, _aim, face_step)
	else:
		if swinging:
			return
		_spin_phase += SPIN_SPEED * delta
		_ring_angle = _spin_phase + slot_offset
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

	# Mirror off the aim, not the slash. Flipping from the composed swing
	# angle made a cut look like the sprite was flickering instead of swinging.
	var flipped := absf(wrapf(_facing, -PI, PI)) > PI * 0.5
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
	if _ghosts.is_empty():
		return

	_history.push_front({
		"position": _sprite.position,
		"rotation": _sprite.rotation,
		"scale": _sprite.scale,
	})
	var longest: int = int(TRAIL_LAG[TRAIL_LAG.size() - 1]) + 1
	while _history.size() > longest:
		_history.pop_back()

	var swinging := _swing_kind != SwingKind.NONE
	var whirling := not _has_target and not swinging
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


# Starts a new attack pose immediately. Retriggering cuts the previous swing
# short so a fast weapon still reads as hitting, not as a stalled tween.
func play_swing(weapon_class: int = 0) -> void:
	if _sprite == null:
		return

	if (weapon_class & WeaponData.WeaponClass.MELEE) != 0:
		_swing_kind = SwingKind.MELEE
		_swing_duration = 0.36
	elif (weapon_class & WeaponData.WeaponClass.TRAP) != 0:
		_swing_kind = SwingKind.PLANT
		_swing_duration = 0.30
	elif (weapon_class & WeaponData.WeaponClass.FIREARM) != 0:
		_swing_kind = SwingKind.RECOIL
		_swing_duration = 0.26
	elif (weapon_class & WeaponData.WeaponClass.MAGIC) != 0 \
			or (weapon_class & WeaponData.WeaponClass.AOE) != 0:
		_swing_kind = SwingKind.CAST
		_swing_duration = 0.34
	else:
		_swing_kind = SwingKind.THRUST
		_swing_duration = 0.30

	_swing_time = 0.0
	_eval_swing(0.0)


func _advance_swing(delta: float) -> void:
	if _swing_kind == SwingKind.NONE:
		return

	_swing_time += delta
	var u := clampf(_swing_time / maxf(_swing_duration, 0.001), 0.0, 1.0)
	_eval_swing(u)
	if u >= 1.0:
		_swing_kind = SwingKind.NONE
		_clear_swing()


func _eval_swing(u: float) -> void:
	match _swing_kind:
		SwingKind.MELEE:
			_eval_melee(u)
		SwingKind.RECOIL:
			_eval_recoil(u)
		SwingKind.THRUST:
			_eval_thrust(u)
		SwingKind.CAST:
			_eval_cast(u)
		SwingKind.PLANT:
			_eval_plant(u)
		_:
			_clear_swing()


func _eval_melee(u: float) -> void:
	# Wind-up, then a wide cut through the target, then recover. First pose is
	# already cocked so even a 1-frame attack shows the blade moving.
	if u < 0.22:
		var p := _ease_in(u / 0.22)
		_swing_rotation = lerpf(-0.4, -1.85, p)
		_swing_reach = lerpf(-4.0, -12.0, p)
		_swing_lateral = lerpf(-6.0, -16.0, p)
		_swing_lift = lerpf(-2.0, -5.0, p)
		_swing_scale = lerpf(1.0, 0.95, p)
		_swing_flash = 0.0
	elif u < 0.52:
		var p := _ease_out((u - 0.22) / 0.30)
		_swing_rotation = lerpf(-1.85, 1.75, p)
		_swing_reach = lerpf(-12.0, 22.0, p)
		_swing_lateral = lerpf(-16.0, 18.0, p)
		_swing_lift = lerpf(-5.0, 6.0, p)
		_swing_scale = lerpf(0.95, 1.55, p)
		_swing_flash = 1.0 if p < 0.45 else lerpf(1.0, 0.25, (p - 0.45) / 0.55)
	else:
		var p := _ease_out((u - 0.52) / 0.48)
		_swing_rotation = lerpf(1.75, 0.0, p)
		_swing_reach = lerpf(22.0, 0.0, p)
		_swing_lateral = lerpf(18.0, 0.0, p)
		_swing_lift = lerpf(6.0, 0.0, p)
		_swing_scale = lerpf(1.55, 1.0, p)
		_swing_flash = lerpf(0.25, 0.0, p)


func _eval_recoil(u: float) -> void:
	if u < 0.12:
		var p := u / 0.12
		_swing_rotation = lerpf(0.25, -0.85, p)
		_swing_reach = lerpf(10.0, -14.0, p)
		_swing_lateral = 0.0
		_swing_lift = lerpf(-2.0, -6.0, p)
		_swing_scale = lerpf(1.6, 1.15, p)
		_swing_flash = lerpf(1.0, 0.2, p)
	else:
		var p := _ease_out((u - 0.12) / 0.88)
		_swing_rotation = lerpf(-0.85, 0.0, p)
		_swing_reach = lerpf(-14.0, 0.0, p)
		_swing_lateral = 0.0
		_swing_lift = lerpf(-6.0, 0.0, p)
		_swing_scale = lerpf(1.15, 1.0, p)
		_swing_flash = lerpf(0.2, 0.0, p)


func _eval_thrust(u: float) -> void:
	if u < 0.28:
		var p := _ease_in(u / 0.28)
		_swing_rotation = lerpf(0.0, -0.25, p)
		_swing_reach = lerpf(0.0, -10.0, p)
		_swing_lateral = 0.0
		_swing_lift = 0.0
		_swing_scale = lerpf(1.0, 0.88, p)
		_swing_flash = 0.0
	elif u < 0.52:
		var p := _ease_out((u - 0.28) / 0.24)
		_swing_rotation = lerpf(-0.25, 0.18, p)
		_swing_reach = lerpf(-10.0, 18.0, p)
		_swing_lateral = 0.0
		_swing_lift = 0.0
		_swing_scale = lerpf(0.88, 1.42, p)
		_swing_flash = 1.0
	else:
		var p := _ease_out((u - 0.52) / 0.48)
		_swing_rotation = lerpf(0.18, 0.0, p)
		_swing_reach = lerpf(18.0, 0.0, p)
		_swing_lateral = 0.0
		_swing_lift = 0.0
		_swing_scale = lerpf(1.42, 1.0, p)
		_swing_flash = lerpf(1.0, 0.0, p)


func _eval_cast(u: float) -> void:
	if u < 0.35:
		var p := _ease_out(u / 0.35)
		_swing_rotation = lerpf(0.0, 0.7, p)
		_swing_reach = lerpf(0.0, -4.0, p)
		_swing_lateral = 0.0
		_swing_lift = lerpf(0.0, -12.0, p)
		_swing_scale = lerpf(1.0, 1.28, p)
		_swing_flash = lerpf(0.0, 0.7, p)
	elif u < 0.55:
		var p := _ease_out((u - 0.35) / 0.20)
		_swing_rotation = lerpf(0.7, -0.4, p)
		_swing_reach = lerpf(-4.0, 14.0, p)
		_swing_lateral = 0.0
		_swing_lift = lerpf(-12.0, 4.0, p)
		_swing_scale = lerpf(1.28, 1.48, p)
		_swing_flash = 1.0
	else:
		var p := _ease_out((u - 0.55) / 0.45)
		_swing_rotation = lerpf(-0.4, 0.0, p)
		_swing_reach = lerpf(14.0, 0.0, p)
		_swing_lateral = 0.0
		_swing_lift = lerpf(4.0, 0.0, p)
		_swing_scale = lerpf(1.48, 1.0, p)
		_swing_flash = lerpf(1.0, 0.0, p)


func _eval_plant(u: float) -> void:
	if u < 0.30:
		var p := _ease_out(u / 0.30)
		_swing_rotation = lerpf(0.0, 0.65, p)
		_swing_reach = 0.0
		_swing_lateral = 0.0
		_swing_lift = lerpf(0.0, -14.0, p)
		_swing_scale = lerpf(1.0, 1.12, p)
		_swing_flash = 0.0
	elif u < 0.52:
		var p := _ease_in((u - 0.30) / 0.22)
		_swing_rotation = lerpf(0.65, 0.1, p)
		_swing_reach = 0.0
		_swing_lateral = 0.0
		_swing_lift = lerpf(-14.0, 8.0, p)
		_swing_scale = lerpf(1.12, 1.32, p)
		_swing_flash = 1.0
	else:
		var p := _ease_out((u - 0.52) / 0.48)
		_swing_rotation = lerpf(0.1, 0.0, p)
		_swing_reach = 0.0
		_swing_lateral = 0.0
		_swing_lift = lerpf(8.0, 0.0, p)
		_swing_scale = lerpf(1.32, 1.0, p)
		_swing_flash = lerpf(1.0, 0.0, p)


func _clear_swing() -> void:
	_swing_rotation = 0.0
	_swing_reach = 0.0
	_swing_lateral = 0.0
	_swing_lift = 0.0
	_swing_scale = 1.0
	_swing_flash = 0.0


func _ease_in(t: float) -> float:
	return t * t

func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


# Points the weapon along `angle`. With no target the ring whirls instead of
# freezing wherever the last target happened to die.
func set_aim(angle: float, has_target: bool) -> void:
	_aim = angle
	_has_target = has_target
