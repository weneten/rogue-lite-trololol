extends Node2D
class_name ArenaVisuals

# Builds the graveyard the fight happens in, from the pixel tile strips in
# Assets/sprites/arena.
#
# The world loops (see ArenaLoop), so nothing here can be built once at a fixed size:
# a 6144x4096 ground baked into one image would be a 100 MB texture, and 16x the props
# would be 16x the nodes. Both are instead built around the Hunter and follow him:
#
#   * the floor is one seamless 512px patch drawn with texture repeat, its UV origin
#     tracking his position, so a screenful of ground costs one sprite;
#   * the props live in 512px cells of the world grid. Only the cells near him exist as
#     nodes; the rest are freed. What a cell contains is derived from the world seed and
#     the cell's own coordinates, so walking away and coming back rebuilds the same
#     headstones in the same places — which is the whole reason the world is a torus
#     rather than an endless plane.
#
# WORLD_SIZE is a whole number of both, so the floor pattern and the prop grid meet
# themselves at the seam instead of showing a join.
#
# Braziers and candles get a flicker light so the arena reads as lit.

@export var tile_size: int = 16
@export var seed: int = 1337

const FLOOR_PATH := "res://Assets/sprites/arena/floor_tiles.png"
const WALL_PATH := "res://Assets/sprites/arena/wall_tiles.png"
const PROPS_PATH := "res://Assets/sprites/arena/props.png"

# Side of the repeating ground patch, and of one prop cell. Both divide WORLD_SIZE.
const FLOOR_PATCH := 512
const PROP_CELL := 512.0

# Props per cell. The old fixed arena ran about nine per cell's worth of ground; half
# that reads just as full once the camera is never near an edge, and halves the nodes.
const PROPS_PER_CELL := 4
# Cells kept alive in each direction around the Hunter. Three covers a 3072px square,
# comfortably past the corners of any viewport we ship.
const PROP_VIEW_CELLS := 3

# 2D lights are a full composite pass each. The cell grid already bounds how many can
# exist, but a dense stretch of braziers could still stack a dozen on one screen.
const MAX_FLICKER_LIGHTS := 16

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

# A fixed place in the world rather than a scattered prop: the gate is a landmark the
# Hunter can walk away from and come back to, and the hook a dungeon entrance hangs on.
const GATE_POSITION := Vector2(0.0, -640.0)

var _floor: Sprite2D
var _prop_root: Node2D
var _props_strip: Texture2D
# Live prop cells, keyed by grid coordinate. Values are Node2D holding that cell's props
# at cell-local offsets, so following the Hunter costs one move per cell, not per prop.
var _cells: Dictionary = {}
var _cell_cols: int = 1
var _cell_rows: int = 1
var _view_cells: int = PROP_VIEW_CELLS

var _flicker_lights: Array[PointLight2D] = []
var _time: float = 0.0

func _ready() -> void:
	if OS.has_feature("web"):
		# One ring of cells instead of three: a browser build cannot afford 200 sprites
		# of scenery on top of a wave.
		_view_cells = 1

	# LoopRebaser moves every entity under World into the Hunter's frame each frame.
	# This node is not an entity — it stays at the origin and places its own contents.
	add_to_group(LoopRebaser.BACKDROP_GROUP)

	# Night grade — the art is drawn for a cold blue night with warm fire pools.
	var modulate_node = get_parent().get_node_or_null("CanvasModulate") as CanvasModulate
	if modulate_node != null:
		modulate_node.color = Color(0.82, 0.80, 0.94, 1.0)

	var current_scene = get_tree().current_scene
	var vignette = current_scene.get_node_or_null("UI/VignetteOverlay_TODO_ReplaceWithRadialShader") as ColorRect if current_scene != null else null
	if vignette != null:
		vignette.color = Color(0.03, 0.01, 0.04, 0.28)

	# Godot 4.7 blocks add_child on a node while its own _ready is running
	# ("Parent node is busy setting up children"). The add_child calls below used to
	# fail on web, so the floor/props never appeared and Firefox logged
	# ELEMENT_ARRAY_BUFFER warnings for the missing geometry.
	_assemble.call_deferred()

func _assemble() -> void:
	_cell_cols = maxi(1, int(round(ArenaLoop.world_size.x / PROP_CELL)))
	_cell_rows = maxi(1, int(round(ArenaLoop.world_size.y / PROP_CELL)))
	# Asking for a wider ring than the world has cells would name the same cell twice
	# and drop props on the second pass.
	_view_cells = mini(_view_cells, mini((_cell_cols - 1) / 2, (_cell_rows - 1) / 2))

	_build_floor()
	_build_props()

func _process(delta: float) -> void:
	var anchor := _anchor()
	_update_floor(anchor)
	_update_props(anchor)

	_time += delta
	# Cheap per-light flicker: two out-of-phase sines never repeat visibly. Lights die
	# with the cell that owns them, so prune as we go.
	var live: Array[PointLight2D] = []
	for light in _flicker_lights:
		if not is_instance_valid(light):
			continue

		var phase: float = light.get_meta("flicker_phase", 0.0)
		light.energy = light.get_meta("flicker_base", 0.85) \
			+ 0.16 * sin(_time * 7.3 + phase) + 0.09 * sin(_time * 17.1 + phase * 2.0)
		live.append(light)

	_flicker_lights = live

# Where the world is currently centred. Everything under World has been folded around
# the local Hunter, so his position is the frame the scenery has to be drawn in.
func _anchor() -> Vector2:
	var camera := get_viewport().get_camera_2d() if get_viewport() != null else null
	if camera != null:
		return camera.get_screen_center_position()

	var hunter := get_tree().get_first_node_in_group("Player") as Node2D
	return hunter.global_position if hunter != null else Vector2.ZERO

# Stamps random floor variants into one repeating patch. Drawn with texture repeat and
# a region that tracks the camera, so any amount of ground costs a single sprite.
func _build_floor() -> void:
	var strip = _load_image(FLOOR_PATH)
	if strip == null:
		return

	var variants = strip.get_width() / tile_size
	if variants <= 0:
		return

	var tiles = FLOOR_PATCH / tile_size
	var image = Image.create_empty(FLOOR_PATCH, FLOOR_PATCH, false, Image.FORMAT_RGBA8)

	var rng = RandomNumberGenerator.new()
	rng.seed = seed

	for y in range(tiles):
		for x in range(tiles):
			# Weighted toward the plain variants; the decorated ones (moss,
			# crack, blood, bones) are accents and would tile obviously.
			var variant = rng.randi_range(0, 1)
			if rng.randf() < 0.12:
				variant = rng.randi_range(0, variants - 1)

			var src = Rect2i(variant * tile_size, 0, tile_size, tile_size)
			image.blit_rect(strip, src, Vector2i(x * tile_size, y * tile_size))

	_floor = Sprite2D.new()
	_floor.name = "Floor"
	_floor.texture = ImageTexture.create_from_image(image)
	_floor.centered = true
	_floor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_floor.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_floor.region_enabled = true
	_floor.z_index = -10
	add_child(_floor)

func _update_floor(anchor: Vector2) -> void:
	if _floor == null:
		return

	var view := get_viewport_rect().size
	var camera := get_viewport().get_camera_2d() if get_viewport() != null else null
	if camera != null and camera.zoom.x > 0.0 and camera.zoom.y > 0.0:
		view /= camera.zoom

	# A patch of slack on every side so a fast Hunter never outruns the ground.
	var span := view + Vector2.ONE * (FLOOR_PATCH * 2)
	_floor.global_position = anchor
	# The region origin is the world position, so the pattern stays pinned to the world
	# instead of sliding with the camera. WORLD_SIZE is a whole number of patches, so it
	# lines up with itself across the seam too.
	_floor.region_rect = Rect2(anchor - span * 0.5, span)

func _build_props() -> void:
	_props_strip = _load_texture(PROPS_PATH)
	if _props_strip == null:
		return

	_prop_root = Node2D.new()
	_prop_root.name = "Props"
	_prop_root.y_sort_enabled = true
	_prop_root.z_index = -6
	add_child(_prop_root)

	_update_props(_anchor())

func _update_props(anchor: Vector2) -> void:
	if _prop_root == null:
		return

	var centre := _cell_of(anchor)
	var wanted := {}
	for dy in range(-_view_cells, _view_cells + 1):
		for dx in range(-_view_cells, _view_cells + 1):
			wanted[Vector2i(
				wrapi(centre.x + dx, 0, _cell_cols),
				wrapi(centre.y + dy, 0, _cell_rows))] = true

	for key in _cells.keys():
		if wanted.has(key):
			continue

		var stale: Node2D = _cells[key]
		if is_instance_valid(stale):
			stale.queue_free()

		_cells.erase(key)

	for key in wanted:
		if not _cells.has(key):
			_cells[key] = _build_cell(key)

		var cell: Node2D = _cells[key]
		if is_instance_valid(cell):
			# One move per cell rather than per prop, and it puts the cell on whichever
			# copy of itself is nearest the Hunter.
			cell.position = ArenaLoop.rebase(anchor, _cell_centre(key))

# Everything a cell holds is derived from the world seed and the cell's own coordinates,
# so a cell rebuilt an hour later is identical to the one that was freed.
func _build_cell(key: Vector2i) -> Node2D:
	var cell := Node2D.new()
	cell.name = "Cell_%d_%d" % [key.x, key.y]
	cell.y_sort_enabled = true
	_prop_root.add_child(cell)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, seed))

	var total_weight := 0.0
	for weight in PROP_WEIGHTS:
		total_weight += weight

	var half := PROP_CELL * 0.5
	for i in range(PROPS_PER_CELL):
		var offset := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		cell.add_child(_make_prop(_props_strip, _pick_prop(rng, total_weight), offset, rng))

	# The gate belongs to whichever cell it stands in, so it is built and freed by the
	# same rule as everything else — but always in the one place.
	if _cell_of(GATE_POSITION) == key:
		cell.add_child(_make_prop(
			_props_strip, PROP_GATE, GATE_POSITION - _cell_centre(key), rng, false))

	return cell

func _cell_of(absolute: Vector2) -> Vector2i:
	var folded := ArenaLoop.wrap_point(absolute) + ArenaLoop.half_size
	return Vector2i(
		wrapi(int(floor(folded.x / PROP_CELL)), 0, _cell_cols),
		wrapi(int(floor(folded.y / PROP_CELL)), 0, _cell_rows))

func _cell_centre(key: Vector2i) -> Vector2:
	return Vector2(
		(key.x + 0.5) * PROP_CELL - ArenaLoop.half_size.x,
		(key.y + 0.5) * PROP_CELL - ArenaLoop.half_size.y)

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
	if OS.has_feature("web") or _flicker_lights.size() >= MAX_FLICKER_LIGHTS:
		return

	var light = PointLight2D.new()
	light.texture = _radial_light_texture()
	light.texture_scale = 3.4 if strong else 1.6
	light.color = Color(1.0, 0.62, 0.32) if strong else Color(1.0, 0.86, 0.6)
	light.energy = 0.9 if strong else 0.5
	light.position = Vector2(0, -24 if strong else -16)
	# Carried on the light itself, so a freed cell takes its phase with it.
	light.set_meta("flicker_phase", rng.randf() * TAU)
	light.set_meta("flicker_base", 0.9 if strong else 0.5)
	holder.add_child(light)

	_flicker_lights.append(light)

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
