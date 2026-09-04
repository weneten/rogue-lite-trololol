extends Node2D
class_name WitchfirePlume

# One column of witchfire, standing where something landed.
#
# The Magus's meteors resolve into a BossGroundQuake — dust and a shake, which
# is the ground being hit and says nothing about what hit it. This is the fire
# half: it goes up where the impact was, at the size the impact was, and burns
# out over half a second.
#
# It carries no damage of its own. The meteor has already resolved by the time
# this exists, and a decoration that hits would be a second, invisible hitbox
# living on a different clock from the one the player was warned about.

# How long it burns. Long enough to be seen through the quake it arrives with,
# short enough that eight of them from one shower never collect into a bonfire
# the arena has to be read through.
const LIFETIME := 0.55

# What the artwork's own half-width means in impact radii. A plume as wide as
# the crater would hide it; this stands in the middle of it.
const WIDTH_SHARE := 0.55

var radius: float = 60.0

var _age: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Above the floor decals, below the cast — the layer every hazard here uses.
	z_index = -1

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return

	queue_redraw()

func _draw() -> void:
	var texture := WitchfireSheet.frame(WitchfireSheet.PLUME, _age)
	if texture == null:
		return

	var cell := WitchfireSheet.cell()
	# Sized off the impact rather than off the sheet, so a finale meteor at
	# twice the radius arrives with twice the fire.
	var scale := maxf(0.4, radius * WIDTH_SHARE * 2.0 / cell)
	var fade := 1.0 - clampf((_age - LIFETIME * 0.45) / (LIFETIME * 0.55), 0.0, 1.0)
	# Sinks back into the floor as it dies rather than only thinning out: fire
	# that fades at full height reads as a texture being switched off.
	var lift := 0.82 + 0.18 * fade

	draw_texture_rect_region(texture,
		Rect2(-cell * scale * 0.5, -WitchfireSheet.floor_y() * scale * lift,
			cell * scale, cell * scale * lift),
		Rect2(Vector2.ZERO, texture.get_size()),
		Color(1.0, 1.0, 1.0, fade))

static func spawn(host: Node, position: Vector2, radius: float) -> WitchfirePlume:
	if not WitchfireSheet.ready():
		return null

	var plume := WitchfirePlume.new()
	plume.radius = radius

	var tree := host.get_tree()
	var parent: Node = tree.current_scene if tree != null else host.get_parent()
	if parent == null:
		parent = host

	parent.add_child(plume)
	plume.global_position = position
	return plume
