extends Node2D
class_name WeaponVisual

# The copy of a weapon the player actually carries.
#
# Built at runtime by Weapon.gd and parented to the WIELDER, not to the Weapon
# node: the weapon's own transform is anchored at the body origin, which is the
# character's feet, so a visual hanging off it orbited their ankles. This sits
# at chest height instead and is handed the aim angle every frame.
#
# The art is the same shape the shop card shows
# (Assets/sprites/weapons/mounted/), drawn pointing right with the grip on the
# centre pixel, so rotating the pivot turns the weapon about the grip.
#
# Everything here is cosmetic. Nothing in this file feeds damage, range or
# cooldown; if it fails to find art it simply draws nothing.

const MOUNT_DIR := "res://Assets/sprites/weapons/mounted/"

# How far from the body the grip rides. Far enough to clear the silhouette,
# close enough to still read as held rather than floating.
const ORBIT_RADIUS := 15.0

# Chest height above the body origin. The rig draws its characters standing on
# the origin, so everything carried has to be lifted to meet them.
const CARRY_HEIGHT := -24.0
const BOB_AMPLITUDE := 1.4
const BOB_SPEED := 3.4

var _pivot: Node2D
var _sprite: Sprite2D
var _time: float = 0.0
var _swing: Tween

# Cache: several weapons of the same type share one texture, and a run can
# equip six at once.
static var _textures: Dictionary = {}


func setup(data: WeaponData, scale_factor: float = 1.0) -> void:
	var texture := _texture_for(data)
	if texture == null:
		return

	position = Vector2(0.0, CARRY_HEIGHT)

	# The pivot takes the aim rotation; the sprite hangs off it at arm's
	# length. Keeping them separate means the idle bob can move the sprite
	# without disturbing where the weapon points.
	_pivot = Node2D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	_sprite = Sprite2D.new()
	_sprite.name = "Mount"
	_sprite.texture = texture
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = Vector2(ORBIT_RADIUS, 0.0)
	_sprite.scale = Vector2.ONE * scale_factor
	# Same layer as the wielder so the weapon Y-sorts with them instead of
	# floating over every other fighter on the screen.
	_sprite.z_index = 0
	_pivot.add_child(_sprite)


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
	# Only idle when no swing owns the transform, or the bob fights the tween.
	if _swing == null or not _swing.is_valid():
		_sprite.position = Vector2(ORBIT_RADIUS, sin(_time * BOB_SPEED) * BOB_AMPLITUDE)
		_sprite.rotation = sin(_time * BOB_SPEED * 0.5) * 0.06


# Melee weapons cut an arc; everything else kicks back like it fired. Both run
# off the same tween so a weapon can never be left mid-swing.
func play_swing(melee: bool) -> void:
	if _sprite == null:
		return

	if _swing != null and _swing.is_valid():
		_swing.kill()

	_swing = create_tween()
	_swing.set_trans(Tween.TRANS_CUBIC)

	if melee:
		# Wind up behind the shoulder, then cut through past the target.
		_sprite.rotation = -1.5
		_sprite.position = Vector2(ORBIT_RADIUS - 5.0, -4.0)
		_swing.set_ease(Tween.EASE_OUT)
		_swing.set_parallel(true)
		_swing.tween_property(_sprite, "rotation", 1.3, 0.16)
		_swing.tween_property(_sprite, "position", Vector2(ORBIT_RADIUS + 11.0, 3.0), 0.16)
		_swing.chain()
		_swing.set_parallel(true)
		_swing.set_ease(Tween.EASE_IN_OUT)
		_swing.tween_property(_sprite, "rotation", 0.0, 0.22)
		_swing.tween_property(_sprite, "position", Vector2(ORBIT_RADIUS, 0.0), 0.22)
	else:
		_sprite.position = Vector2(ORBIT_RADIUS + 4.0, 0.0)
		_swing.set_ease(Tween.EASE_OUT)
		_swing.tween_property(_sprite, "position", Vector2(ORBIT_RADIUS - 5.0, 0.0), 0.06)
		_swing.set_ease(Tween.EASE_OUT)
		_swing.tween_property(_sprite, "position", Vector2(ORBIT_RADIUS, 0.0), 0.20)

	# Reset the idle clock so the bob resumes from centre rather than snapping.
	_swing.finished.connect(func(): _time = 0.0)


# Points the weapon along `angle`. A weapon aimed left arrives upside down, so
# it is mirrored vertically — which is what a person holding it would do.
func set_aim(angle: float) -> void:
	if _pivot == null or _sprite == null:
		return

	_pivot.rotation = angle
	var magnitude := absf(_sprite.scale.x)
	_sprite.scale.y = -magnitude if absf(angle) > PI * 0.5 else magnitude
