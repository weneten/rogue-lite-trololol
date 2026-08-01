extends Node2D
class_name ArenaVisuals

# Builds a Brotato-like playfield: warm checker dirt tiles, soft border, light clutter.
# Pure procedural textures so we never depend on missing imports.

@export var arena_size: Vector2 = Vector2(1600, 1000)
@export var tile_size: int = 48
@export var border_thickness: int = 56
@export var clutter_count: int = 48
@export var seed: int = 1337

# Warm sand / clay — Brotato-ish readable floor.
const TILE_A = Color(0.72, 0.58, 0.40, 1.0)
const TILE_B = Color(0.66, 0.52, 0.36, 1.0)
const TILE_C = Color(0.76, 0.62, 0.44, 1.0)
const GROUT = Color(0.48, 0.36, 0.24, 1.0)
const BORDER_FILL = Color(0.38, 0.30, 0.22, 1.0)
const BORDER_RIM = Color(0.28, 0.22, 0.16, 1.0)
const OUTSIDE_VOID = Color(0.18, 0.16, 0.14, 1.0)

func _ready() -> void:
	# Kill any leftover dark global grade from older Arena scenes.
	var modulate_node = get_parent().get_node_or_null("CanvasModulate") as CanvasModulate
	if modulate_node != null:
		modulate_node.color = Color(1.05, 1.02, 0.96, 1.0)

	# Soft vignette only (was heavy purple fog).
	var current_scene = get_tree().current_scene
	var vignette = current_scene.get_node_or_null("UI/VignetteOverlay_TODO_ReplaceWithRadialShader") as ColorRect if current_scene != null else null
	if vignette != null:
		vignette.color = Color(0.05, 0.03, 0.02, 0.14)

	_build_outside()
	_build_floor()
	_build_border()
	_build_clutter()
	_build_corner_accents()

func _build_outside() -> void:
	# Slightly larger dark plate so the camera never shows pure black emptiness.
	var outside = Polygon2D.new()
	outside.name = "Outside"
	outside.z_index = -20
	outside.color = OUTSIDE_VOID
	outside.polygon = [
		Vector2(-arena_size.x, -arena_size.y),
		Vector2(arena_size.x, -arena_size.y),
		Vector2(arena_size.x, arena_size.y),
		Vector2(-arena_size.x, arena_size.y)
	]
	# Scale up a bit beyond walls.
	outside.scale = Vector2.ONE * 1.35
	add_child(outside)

func _build_floor() -> void:
	var half_w = int(ceilf(arena_size.x * 0.5 / tile_size) * tile_size)
	var half_h = int(ceilf(arena_size.y * 0.5 / tile_size) * tile_size)
	var tex_w = half_w * 2
	var tex_h = half_h * 2

	var image = Image.create_empty(tex_w, tex_h, false, Image.FORMAT_RGBA8)
	image.fill(TILE_A)

	var rng = RandomNumberGenerator.new()
	rng.seed = seed

	for y in range(0, tex_h, tile_size):
		for x in range(0, tex_w, tile_size):
			var tx = x / tile_size
			var ty = y / tile_size
			var checker = ((tx + ty) & 1) == 0
			var base_col = TILE_A if checker else TILE_B

			# Occasional third tone for variety (Brotato tiles aren't perfectly uniform).
			if rng.randf() < 0.12:
				base_col = TILE_C

			# Subtle per-tile brightness noise.
			var n = rng.randf_range(-0.04, 0.04)
			var fill = Color(
				clampf(base_col.r + n, 0.0, 1.0),
				clampf(base_col.g + n * 0.9, 0.0, 1.0),
				clampf(base_col.b + n * 0.7, 0.0, 1.0),
				1.0)

			_fill_rect(image, x, y, tile_size, tile_size, fill)

			# Inner highlight (top-left) + soft shadow (bottom-right) → cheap 3D tile feel.
			var hi = fill.lightened(0.08)
			var sh = fill.darkened(0.10)
			_draw_h_line(image, x + 1, x + tile_size - 2, y + 1, hi)
			_draw_v_line(image, x + 1, y + 1, y + tile_size - 2, hi)
			_draw_h_line(image, x + 2, x + tile_size - 2, y + tile_size - 2, sh)
			_draw_v_line(image, x + tile_size - 2, y + 2, y + tile_size - 2, sh)

			# Speckles / dirt grit.
			var grit = rng.randi_range(3, 8)
			for i in range(grit):
				var px = x + rng.randi_range(3, tile_size - 4)
				var py = y + rng.randi_range(3, tile_size - 4)
				var speck = fill.darkened(0.12) if rng.randf() < 0.5 else fill.lightened(0.08)
				image.set_pixel(px, py, speck)
				if rng.randf() < 0.35 and px + 1 < x + tile_size - 2:
					image.set_pixel(px + 1, py, speck)

			# Thin grout lines between tiles.
			_draw_h_line(image, x, x + tile_size - 1, y, GROUT)
			_draw_v_line(image, x, y, y + tile_size - 1, GROUT)

	# Soft center brightening so the fight area reads clearer.
	_apply_radial_lift(image, 0.07)

	var tex = ImageTexture.create_from_image(image)
	var floor = Sprite2D.new()
	floor.name = "Floor"
	floor.texture = tex
	floor.centered = true
	floor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor.z_index = -10
	floor.position = Vector2.ZERO
	add_child(floor)

func _build_border() -> void:
	var hw = arena_size.x * 0.5
	var hh = arena_size.y * 0.5
	var t = border_thickness as float

	# Four thick border slabs (darker packed earth / wood edge).
	_add_border_slab("BorderN", Rect2(-hw - t, -hh - t, arena_size.x + t * 2, t))
	_add_border_slab("BorderS", Rect2(-hw - t, hh, arena_size.x + t * 2, t))
	_add_border_slab("BorderW", Rect2(-hw - t, -hh, t, arena_size.y))
	_add_border_slab("BorderE", Rect2(hw, -hh, t, arena_size.y))

	# Inner rim line (lighter strip) so the playable edge is obvious like Brotato.
	var rim = Line2D.new()
	rim.name = "PlayableRim"
	rim.width = 3.0
	rim.default_color = Color(0.90, 0.78, 0.52, 0.85)
	rim.z_index = -5
	rim.antialiased = false
	rim.joint_mode = Line2D.LINE_JOINT_BEVEL
	rim.begin_cap_mode = Line2D.LINE_CAP_BOX
	rim.end_cap_mode = Line2D.LINE_CAP_BOX
	rim.add_point(Vector2(-hw + 2, -hh + 2))
	rim.add_point(Vector2(hw - 2, -hh + 2))
	rim.add_point(Vector2(hw - 2, hh - 2))
	rim.add_point(Vector2(-hw + 2, hh - 2))
	rim.add_point(Vector2(-hw + 2, -hh + 2))
	add_child(rim)

func _add_border_slab(name: String, rect: Rect2) -> void:
	var image = Image.create_empty(maxi(2, int(rect.size.x)), maxi(2, int(rect.size.y)), false, Image.FORMAT_RGBA8)
	image.fill(BORDER_FILL)

	var rng = RandomNumberGenerator.new()
	rng.seed = seed + hash(name)

	# Brick / plank style banding.
	var band = 14
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var dark_band = (((y / band) + (x / (band * 2))) % 2) == 0
			var c = BORDER_FILL.lightened(0.05) if not dark_band else BORDER_FILL
			var n = rng.randf_range(-0.03, 0.03)
			c = Color(
				clampf(c.r + n, 0.0, 1.0),
				clampf(c.g + n, 0.0, 1.0),
				clampf(c.b + n, 0.0, 1.0),
				1.0)
			image.set_pixel(x, y, c)

	# Outer edge darker.
	for x in range(image.get_width()):
		image.set_pixel(x, 0, BORDER_RIM)
		image.set_pixel(x, image.get_height() - 1, BORDER_RIM)

	for y in range(image.get_height()):
		image.set_pixel(0, y, BORDER_RIM)
		image.set_pixel(image.get_width() - 1, y, BORDER_RIM)

	var tex = ImageTexture.create_from_image(image)
	var sprite = Sprite2D.new()
	sprite.name = name
	sprite.texture = tex
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = -8
	sprite.position = rect.position
	add_child(sprite)

func _build_clutter() -> void:
	var root = Node2D.new()
	root.name = "Clutter"
	root.z_index = -6
	add_child(root)

	var rng = RandomNumberGenerator.new()
	rng.seed = seed + 99

	var hw = arena_size.x * 0.5 - 40.0
	var hh = arena_size.y * 0.5 - 40.0

	for i in range(clutter_count):
		# Bias clutter toward edges so center stays clear for combat readability.
		var edge_bias = rng.randf()
		var x: float
		var y: float
		if edge_bias < 0.7:
			# Near border ring.
			var side = rng.randi_range(0, 3)
			var inset = rng.randf_range(20.0, 90.0)
			match side:
				0: # N
					x = rng.randf_range(-hw, hw)
					y = -hh + inset
				1: # S
					x = rng.randf_range(-hw, hw)
					y = hh - inset
				2: # W
					x = -hw + inset
					y = rng.randf_range(-hh, hh)
				_: # E
					x = hw - inset
					y = rng.randf_range(-hh, hh)
		else:
			x = rng.randf_range(-hw * 0.7, hw * 0.7)
			y = rng.randf_range(-hh * 0.7, hh * 0.7)

		var kind = rng.randi_range(0, 3)
		var prop: Node2D
		match kind:
			0:
				prop = _make_pebble(rng)
			1:
				prop = _make_grass_tuft(rng)
			2:
				prop = _make_crack(rng)
			_:
				prop = _make_bone(rng)
		prop.position = Vector2(x, y)
		prop.rotation = rng.randf_range(0.0, TAU)
		prop.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.55, 0.9))
		root.add_child(prop)

func _build_corner_accents() -> void:
	var hw = arena_size.x * 0.5 - 30.0
	var hh = arena_size.y * 0.5 - 30.0
	var corners = [
		Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(-hw, hh), Vector2(hw, hh)
	]

	for c in corners:
		var plate = Polygon2D.new()
		plate.color = Color(0.42, 0.34, 0.24, 0.9)
		plate.polygon = [
			Vector2(-18, -10), Vector2(18, -10), Vector2(14, 12), Vector2(-14, 12)
		]
		plate.position = c
		plate.z_index = -7
		add_child(plate)

		var stud = Polygon2D.new()
		stud.color = Color(0.85, 0.72, 0.40, 0.95)
		stud.polygon = [
			Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)
		]
		stud.position = c
		stud.z_index = -6
		add_child(stud)

func _make_pebble(rng: RandomNumberGenerator) -> Node2D:
	var s = rng.randf_range(3.0, 7.0)
	var pebble = Polygon2D.new()
	pebble.color = Color(0.45, 0.40, 0.34, 1.0)
	pebble.polygon = [
		Vector2(-s, -s * 0.6),
		Vector2(s * 0.8, -s * 0.5),
		Vector2(s, s * 0.5),
		Vector2(-s * 0.7, s * 0.6)
	]
	return pebble

func _make_grass_tuft(rng: RandomNumberGenerator) -> Node2D:
	var root = Node2D.new()
	var blades = rng.randi_range(3, 5)
	for i in range(blades):
		var h = rng.randf_range(6.0, 12.0)
		var ox = rng.randf_range(-4.0, 4.0)
		var blade = Polygon2D.new()
		blade.color = Color(0.35 + rng.randf() * 0.1, 0.48, 0.28, 0.9)
		blade.polygon = [
			Vector2(ox - 1.2, 0),
			Vector2(ox + 1.2, 0),
			Vector2(ox + rng.randf_range(-2.0, 2.0), -h)
		]
		root.add_child(blade)

	return root

func _make_crack(rng: RandomNumberGenerator) -> Node2D:
	var line = Line2D.new()
	line.width = rng.randf_range(1.2, 2.2)
	line.default_color = Color(0.40, 0.30, 0.20, 0.75)
	line.antialiased = false
	var len = rng.randf_range(10.0, 22.0)
	line.add_point(Vector2.ZERO)
	line.add_point(Vector2(len * 0.4, rng.randf_range(-3.0, 3.0)))
	line.add_point(Vector2(len, rng.randf_range(-4.0, 4.0)))
	return line

func _make_bone(rng: RandomNumberGenerator) -> Node2D:
	var len = rng.randf_range(8.0, 14.0)
	var bone = Polygon2D.new()
	bone.color = Color(0.82, 0.78, 0.68, 0.85)
	bone.polygon = [
		Vector2(-len, -1.5),
		Vector2(len, -1.5),
		Vector2(len + 2.0, 0),
		Vector2(len, 1.5),
		Vector2(-len, 1.5),
		Vector2(-len - 2.0, 0)
	]
	return bone

func _fill_rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var x1 = clampi(x + w, 0, image.get_width())
	var y1 = clampi(y + h, 0, image.get_height())
	var x_start = clampi(x, 0, image.get_width())
	var y_start = clampi(y, 0, image.get_height())
	for py in range(y_start, y1):
		for px in range(x_start, x1):
			image.set_pixel(px, py, color)

func _draw_h_line(image: Image, x0: int, x1: int, y: int, color: Color) -> void:
	if y < 0 or y >= image.get_height():
		return

	var start_x = x0
	var end_x = x1
	if start_x > end_x:
		var temp = start_x
		start_x = end_x
		end_x = temp

	start_x = clampi(start_x, 0, image.get_width() - 1)
	end_x = clampi(end_x, 0, image.get_width() - 1)
	for x in range(start_x, end_x + 1):
		image.set_pixel(x, y, color)

func _draw_v_line(image: Image, x: int, y0: int, y1: int, color: Color) -> void:
	if x < 0 or x >= image.get_width():
		return

	var start_y = y0
	var end_y = y1
	if start_y > end_y:
		var temp = start_y
		start_y = end_y
		end_y = temp

	start_y = clampi(start_y, 0, image.get_height() - 1)
	end_y = clampi(end_y, 0, image.get_height() - 1)
	for y in range(start_y, end_y + 1):
		image.set_pixel(x, y, color)

func _apply_radial_lift(image: Image, amount: float) -> void:
	var w = image.get_width()
	var h = image.get_height()
	var cx = w * 0.5
	var cy = h * 0.5
	var max_r = sqrt(cx * cx + cy * cy)

	# Sample every 2px for speed — still looks smooth at game scale.
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var dx = (x - cx) / max_r
			var dy = (y - cy) / max_r
			var d = sqrt(dx * dx + dy * dy)
			var lift = (1.0 - clampf(d, 0.0, 1.0)) * amount
			if lift <= 0.001:
				continue

			for oy in range(2):
				if y + oy >= h:
					break
				for ox in range(2):
					if x + ox >= w:
						break
					var c = image.get_pixel(x + ox, y + oy)
					image.set_pixel(x + ox, y + oy, c.lightened(lift))
