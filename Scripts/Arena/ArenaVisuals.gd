extends Node2D
class_name ArenaVisuals

# Builds the graveyard the fight happens in, from the pixel tile strips in
# Assets/sprites/arena.
#
# The floor is stamped once into a single texture (one draw call, no TileMap
# dependency), the wall is a ring of brick tiles, and props are scattered with
# a bias toward the edges so the middle stays readable during a fight.
# Braziers and candles get a flicker light so the arena reads as lit.

@export var arena_size: Vector2 = Vector2(1600, 1000)
@export var tile_size: int = 16
@export var border_thickness: int = 64
@export var prop_count: int = 54
@export var seed: int = 1337

const FLOOR_PATH := "res://Assets/sprites/arena/floor_tiles.png"
const WALL_PATH := "res://Assets/sprites/arena/wall_tiles.png"
const PROPS_PATH := "res://Assets/sprites/arena/props.png"

const PROP_SIZE := 32
# Prop strip order: headstone, cross, dead tree, brazier, bones, rubble,
# candles, gate. The last one is reserved for the entrance, not scattered.
const PROP_HEADSTONE := 0
const PROP_BRAZIER := 3
const PROP_CANDLES := 6
const PROP_GATE := 7
const SCATTER_PROPS := [0, 1, 2, 3, 4, 5, 6]

# Weights matched to SCATTER_PROPS — rubble and bones are filler, so they are
# common; braziers are the expensive ones, so they stay rare.
const PROP_WEIGHTS := [3.0, 2.0, 1.5, 0.8, 3.0, 3.5, 1.2]

const OUTSIDE_VOID := Color(0.035, 0.02, 0.045, 1.0)

var _flicker_lights: Array[PointLight2D] = []
var _flicker_phases: Array[float] = []
var _time: float = 0.0

func _ready() -> void:
	if OS.has_feature("web"):
		prop_count = mini(prop_count, 18)

	# Night grade — the art is drawn for a cold blue night with warm fire pools.
	var modulate_node = get_parent().get_node_or_null("CanvasModulate") as CanvasModulate
	if modulate_node != null:
		modulate_node.color = Color(0.82, 0.80, 0.94, 1.0)

	var current_scene = get_tree().current_scene
	var vignette = current_scene.get_node_or_null("UI/VignetteOverlay_TODO_ReplaceWithRadialShader") as ColorRect if current_scene != null else null
	if vignette != null:
		vignette.color = Color(0.03, 0.01, 0.04, 0.28)

	# Godot 4.7 blocks add_child on a node while its own _ready is running
	# ("Parent node is busy setting up children"). The eight add_child calls
	# below used to fail on web, so the floor/walls/props never appeared and
	# Firefox logged ELEMENT_ARRAY_BUFFER warnings for the missing geometry.
	_assemble.call_deferred()

func _assemble() -> void:
	_build_outside()
	_build_floor()
	_build_walls()
	_build_props()

func _process(delta: float) -> void:
	if _flicker_lights.is_empty():
		set_process(false)
		return

	_time += delta
	# Cheap per-light flicker: two out-of-phase sines never repeat visibly.
	for i in range(_flicker_lights.size()):
		var light = _flicker_lights[i]
		if not is_instance_valid(light):
			continue

		var phase = _flicker_phases[i]
		light.energy = 0.85 + 0.16 * sin(_time * 7.3 + phase) + 0.09 * sin(_time * 17.1 + phase * 2.0)

func _build_outside() -> void:
	var outside = Polygon2D.new()
	outside.name = "Outside"
	outside.z_index = -20
	outside.color = OUTSIDE_VOID
	outside.polygon = PackedVector2Array([
		Vector2(-arena_size.x, -arena_size.y),
		Vector2(arena_size.x, -arena_size.y),
		Vector2(arena_size.x, arena_size.y),
		Vector2(-arena_size.x, arena_size.y)
	])
	outside.scale = Vector2.ONE * 1.4
	add_child(outside)

# Stamps random floor variants into one image so the whole ground is a single
# sprite rather than thousands of nodes.
func _build_floor() -> void:
	var strip = _load_image(FLOOR_PATH)
	if strip == null:
		return

	var variants = strip.get_width() / tile_size
	if variants <= 0:
		return

	var cols = int(ceil(arena_size.x / tile_size))
	var rows = int(ceil(arena_size.y / tile_size))
	var image = Image.create_empty(cols * tile_size, rows * tile_size, false, Image.FORMAT_RGBA8)

	var rng = RandomNumberGenerator.new()
	rng.seed = seed

	for y in range(rows):
		for x in range(cols):
			# Weighted toward the plain variants; the decorated ones (moss,
			# crack, blood, bones) are accents and would tile obviously.
			var variant = rng.randi_range(0, 1)
			if rng.randf() < 0.12:
				variant = rng.randi_range(0, variants - 1)

			var src = Rect2i(variant * tile_size, 0, tile_size, tile_size)
			image.blit_rect(strip, src, Vector2i(x * tile_size, y * tile_size))

	var floor_sprite = Sprite2D.new()
	floor_sprite.name = "Floor"
	floor_sprite.texture = ImageTexture.create_from_image(image)
	floor_sprite.centered = true
	floor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_sprite.z_index = -10
	add_child(floor_sprite)

func _build_walls() -> void:
	var strip = _load_image(WALL_PATH)
	if strip == null:
		return

	var hw = arena_size.x * 0.5
	var hh = arena_size.y * 0.5
	var t = float(border_thickness)

	_add_wall_slab(strip, "WallN", Rect2(-hw - t, -hh - t, arena_size.x + t * 2.0, t), true)
	_add_wall_slab(strip, "WallS", Rect2(-hw - t, hh, arena_size.x + t * 2.0, t), true)
	_add_wall_slab(strip, "WallW", Rect2(-hw - t, -hh, t, arena_size.y), false)
	_add_wall_slab(strip, "WallE", Rect2(hw, -hh, t, arena_size.y), false)

	# Line2D uses an element array buffer Firefox's WebGL 2 rejects (bindBuffer /
	# bufferSubData warnings and hitching). Skip the rim in the browser.
	if OS.has_feature("web"):
		return

	# A lit inner lip so the playable edge is unmistakable mid-fight.
	var rim = Line2D.new()
	rim.name = "PlayableRim"
	rim.width = 2.0
	rim.default_color = Color(0.72, 0.55, 0.32, 0.7)
	rim.z_index = -5
	rim.antialiased = false
	rim.joint_mode = Line2D.LINE_JOINT_BEVEL
	rim.begin_cap_mode = Line2D.LINE_CAP_BOX
	rim.end_cap_mode = Line2D.LINE_CAP_BOX
	for point in [
		Vector2(-hw + 1, -hh + 1), Vector2(hw - 1, -hh + 1),
		Vector2(hw - 1, hh - 1), Vector2(-hw + 1, hh - 1), Vector2(-hw + 1, -hh + 1)
	]:
		rim.add_point(point)
	add_child(rim)

func _add_wall_slab(strip: Image, slab_name: String, rect: Rect2, horizontal: bool) -> void:
	var w = maxi(tile_size, int(rect.size.x))
	var h = maxi(tile_size, int(rect.size.y))
	var image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)

	var rng = RandomNumberGenerator.new()
	rng.seed = seed + slab_name.hash()

	for y in range(0, h, tile_size):
		for x in range(0, w, tile_size):
			# Capstone variant along the top row so the wall has a silhouette.
			var variant = 0
			if y == 0 and horizontal:
				variant = 1
			elif rng.randf() < 0.25:
				variant = 2

			var src = Rect2i(variant * tile_size, 0, tile_size, tile_size)
			image.blit_rect(strip, src, Vector2i(x, y))

	var sprite = Sprite2D.new()
	sprite.name = slab_name
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = -8
	sprite.position = rect.position
	add_child(sprite)

func _build_props() -> void:
	var strip_texture = _load_texture(PROPS_PATH)
	if strip_texture == null:
		return

	var root = Node2D.new()
	root.name = "Props"
	root.y_sort_enabled = true
	root.z_index = -6
	add_child(root)

	var rng = RandomNumberGenerator.new()
	rng.seed = seed + 99

	var hw = arena_size.x * 0.5 - 48.0
	var hh = arena_size.y * 0.5 - 48.0

	var total_weight = 0.0
	for weight in PROP_WEIGHTS:
		total_weight += weight

	for i in range(prop_count):
		# Edge bias keeps the centre of the arena clear to fight in.
		var pos: Vector2
		if rng.randf() < 0.72:
			var inset = rng.randf_range(24.0, 120.0)
			match rng.randi_range(0, 3):
				0: pos = Vector2(rng.randf_range(-hw, hw), -hh + inset)
				1: pos = Vector2(rng.randf_range(-hw, hw), hh - inset)
				2: pos = Vector2(-hw + inset, rng.randf_range(-hh, hh))
				_: pos = Vector2(hw - inset, rng.randf_range(-hh, hh))
		else:
			pos = Vector2(rng.randf_range(-hw * 0.72, hw * 0.72), rng.randf_range(-hh * 0.72, hh * 0.72))

		root.add_child(_make_prop(strip_texture, _pick_prop(rng, total_weight), pos, rng))

	# Four braziers frame the arena corners and give the fight a light rig.
	for corner in [
		Vector2(-hw + 60.0, -hh + 60.0), Vector2(hw - 60.0, -hh + 60.0),
		Vector2(-hw + 60.0, hh - 60.0), Vector2(hw - 60.0, hh - 60.0)
	]:
		root.add_child(_make_prop(strip_texture, PROP_BRAZIER, corner, rng))

	# A gate at the north edge, so the arena reads as a place with a way in.
	root.add_child(_make_prop(strip_texture, PROP_GATE, Vector2(0.0, -hh - 12.0), rng, false))

static func _pick_prop(rng: RandomNumberGenerator, total_weight: float) -> int:
	var roll = rng.randf() * total_weight
	for i in range(SCATTER_PROPS.size()):
		roll -= PROP_WEIGHTS[i]
		if roll <= 0.0:
			return SCATTER_PROPS[i]

	return PROP_HEADSTONE

func _make_prop(strip: Texture2D, index: int, pos: Vector2, rng: RandomNumberGenerator,
		allow_flip: bool = true) -> Node2D:
	var holder = Node2D.new()
	holder.position = pos

	var atlas = AtlasTexture.new()
	atlas.atlas = strip
	atlas.region = Rect2(index * PROP_SIZE, 0, PROP_SIZE, PROP_SIZE)
	atlas.filter_clip = true

	var sprite = Sprite2D.new()
	sprite.texture = atlas
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * 2.0
	# Art sits on the bottom of its cell; lift so the base meets the ground.
	sprite.offset = Vector2(0, -PROP_SIZE * 0.5)
	if allow_flip and rng.randf() < 0.5:
		sprite.flip_h = true

	sprite.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.85, 1.0))
	holder.add_child(sprite)

	if index == PROP_BRAZIER or index == PROP_CANDLES:
		_attach_flicker(holder, index == PROP_BRAZIER, rng)

	return holder

func _attach_flicker(holder: Node2D, strong: bool, rng: RandomNumberGenerator) -> void:
	# 2D lights are a full extra composite pass each. Fine on desktop, fatal
	# in a single-thread browser build — skip them on web.
	if OS.has_feature("web"):
		return

	var light = PointLight2D.new()
	light.texture = _radial_light_texture()
	light.texture_scale = 3.4 if strong else 1.6
	light.color = Color(1.0, 0.62, 0.32) if strong else Color(1.0, 0.86, 0.6)
	light.energy = 0.9 if strong else 0.5
	light.position = Vector2(0, -24 if strong else -16)
	holder.add_child(light)

	_flicker_lights.append(light)
	_flicker_phases.append(rng.randf() * TAU)

# One shared soft falloff texture for every light in the arena.
static var _light_texture: Texture2D

static func _radial_light_texture() -> Texture2D:
	if _light_texture != null:
		return _light_texture

	var size = 128
	var image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center = size * 0.5
	for y in range(size):
		for x in range(size):
			var d = Vector2(x - center, y - center).length() / center
			var a = clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			image.set_pixel(x, y, Color(1, 1, 1, a))

	_light_texture = ImageTexture.create_from_image(image)
	return _light_texture

static func _load_image(path: String) -> Image:
	var texture = _load_texture(path)
	return texture.get_image() if texture != null else null

static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var texture = ResourceLoader.load(path, "Texture2D") as Texture2D
		if texture != null:
			return texture

	# Same fallback the sprite cache uses: decode the PNG ourselves when the
	# import state is not ready yet.
	if not FileAccess.file_exists(path):
		push_error("[ArenaVisuals] Missing texture: %s" % path)
		return null

	var image = Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		push_error("[ArenaVisuals] Could not decode: %s" % path)
		return null

	return ImageTexture.create_from_image(image)
