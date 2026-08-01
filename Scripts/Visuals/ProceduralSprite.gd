extends Node
class_name ProceduralSprite

# Procedurally-drawn character/enemy silhouettes for entities with no real sprite sheet.
# No external art dependency — pure pixel drawing, in the same spirit as ArenaVisuals'
# procedural floor/border textures. Deterministic per seed so the same character always
# renders the same silhouette.

enum Archetype { HUNTER, BEAST, UNDEAD, SWARM }

const OUTLINE = Color(0.05, 0.04, 0.06, 1.0)

static func build(archetype: Archetype, primary: Color, accent: Color, seed_value: int) -> ImageTexture:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	match archetype:
		Archetype.HUNTER:
			return _build_hunter(primary, accent, rng)
		Archetype.BEAST:
			return _build_beast(primary, accent, rng)
		Archetype.UNDEAD:
			return _build_undead(primary, accent, rng)
		Archetype.SWARM:
			return _build_swarm(primary, accent, rng)
		_:
			return _build_hunter(primary, accent, rng)

const PALETTE = [
	[Color(0.62, 0.09, 0.13, 1.0), Color(0.85, 0.7, 0.25, 1.0)],   # crimson / gold
	[Color(0.25, 0.16, 0.42, 1.0), Color(0.65, 0.5, 0.95, 1.0)],   # violet / lavender glow
	[Color(0.14, 0.32, 0.30, 1.0), Color(0.4, 0.85, 0.7, 1.0)],    # teal / mint glow
	[Color(0.35, 0.30, 0.22, 1.0), Color(0.95, 0.8, 0.4, 1.0)],    # umber / amber
	[Color(0.45, 0.10, 0.35, 1.0), Color(0.95, 0.4, 0.65, 1.0)],   # magenta / rose glow
	[Color(0.12, 0.20, 0.40, 1.0), Color(0.5, 0.75, 1.0, 1.0)],    # navy / ice glow
	[Color(0.30, 0.06, 0.06, 1.0), Color(1.0, 0.45, 0.15, 1.0)],   # blood / fire glow
	[Color(0.18, 0.18, 0.18, 1.0), Color(0.85, 0.85, 0.9, 1.0)],   # onyx / silver glow
]

# Deterministic hunter color scheme so every CharacterData gets a distinct, stable palette
# without needing a manually-authored color field.
static func palette_for_name(entity_name: String) -> Array:
	var h = hash(entity_name)
	var idx = h % PALETTE.size()
	if idx < 0:
		idx += PALETTE.size()
	return PALETTE[idx]

static func archetype_for_enemy(enemy_name: String, is_undead: bool) -> Archetype:
	var lower = enemy_name.to_lower()
	if lower.contains("rat") or lower.contains("swarm"):
		return Archetype.SWARM
	if lower.contains("corpse") or lower.contains("wolf") or lower.contains("hound"):
		return Archetype.BEAST
	if is_undead or lower.contains("wraith") or lower.contains("skeletal") or lower.contains("ghoul"):
		return Archetype.UNDEAD
	return Archetype.BEAST

# Vertical center offset so the generated image's "feet" line up near y=bottom,
# matching how the old diamond fallbacks were anchored (character origin ~ ground level).
static func anchor_y(archetype: Archetype, bottom: float) -> float:
	return bottom - size_for(archetype).y * 0.5

static func size_for(archetype: Archetype) -> Vector2:
	match archetype:
		Archetype.HUNTER:
			return Vector2(40, 56)
		Archetype.UNDEAD:
			return Vector2(34, 52)
		Archetype.BEAST:
			return Vector2(44, 38)
		Archetype.SWARM:
			return Vector2(40, 34)
		_:
			return Vector2(40, 56)

# ---------------------------------------------------------------- Hunter (player characters)

static func _build_hunter(primary: Color, accent: Color, rng: RandomNumberGenerator) -> ImageTexture:
	var w = 40
	var h = 56
	var image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)

	var hood_shadow = primary.darkened(0.45)
	var skin = Color(0.85, 0.68, 0.55, 1.0)

	# Cloak body: wide trapezoid from shoulders down to hem.
	var hem_sway = rng.randf_range(-3.0, 3.0)
	var cloak = PackedVector2Array([
		Vector2(w * 0.5 - 8, 20),
		Vector2(w * 0.5 + 8, 20),
		Vector2(w * 0.5 + 13 + hem_sway, h - 4),
		Vector2(w * 0.5 - 13 - hem_sway, h - 4),
	])
	_fill_polygon(image, cloak, primary)
	_outline_polygon(image, cloak, OUTLINE)

	# Center seam / accent trim.
	_fill_polygon(image, PackedVector2Array([
		Vector2(w * 0.5 - 2, 22), Vector2(w * 0.5 + 2, 22),
		Vector2(w * 0.5 + 3, h - 5), Vector2(w * 0.5 - 3, h - 5),
	]), accent)

	# Boots.
	_fill_rect(image, int(w * 0.5 - 9), h - 6, 7, 5, hood_shadow)
	_fill_rect(image, int(w * 0.5 + 2), h - 6, 7, 5, hood_shadow)

	# Hood (head silhouette, shadowed).
	_fill_ellipse(image, w * 0.5, 14, 9, 10, hood_shadow)
	_outline_ellipse(image, w * 0.5, 14, 9, 10, OUTLINE)
	# Face shadow gap showing a hint of skin + glowing eyes.
	_fill_ellipse(image, w * 0.5, 16, 5, 5, skin.darkened(0.3))
	var eye_glow = accent.lightened(0.3)
	image.set_pixel(int(w * 0.5 - 2), 15, eye_glow)
	image.set_pixel(int(w * 0.5 + 2), 15, eye_glow)

	# Shoulder pauldrons for a bit of silhouette read.
	_fill_ellipse(image, w * 0.5 - 9, 21, 4, 3, hood_shadow)
	_fill_ellipse(image, w * 0.5 + 9, 21, 4, 3, hood_shadow)

	# Weapon hint on one side — varies per seed (staff vs blade).
	if rng.randf() < 0.5:
		_fill_rect(image, int(w * 0.5 + 13), 18, 2, 30, accent.darkened(0.1))
		_fill_ellipse(image, w * 0.5 + 14, 17, 3, 3, accent)
	else:
		_fill_polygon(image, PackedVector2Array([
			Vector2(w * 0.5 - 17, 40), Vector2(w * 0.5 - 13, 24),
			Vector2(w * 0.5 - 11, 25), Vector2(w * 0.5 - 15, 41),
		]), accent)

	return ImageTexture.create_from_image(image)

# ---------------------------------------------------------------- Beast (wolf/hound-style enemies)

static func _build_beast(primary: Color, accent: Color, rng: RandomNumberGenerator) -> ImageTexture:
	var w = 44
	var h = 38
	var image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var shade = primary.darkened(0.35)

	# Haunches + body ellipse.
	_fill_ellipse(image, w * 0.42, h * 0.58, 15, 11, primary)
	_outline_ellipse(image, w * 0.42, h * 0.58, 15, 11, OUTLINE)

	# Head.
	_fill_ellipse(image, w * 0.78, h * 0.42, 9, 7, primary)
	_outline_ellipse(image, w * 0.78, h * 0.42, 9, 7, OUTLINE)

	# Ears (count/spikiness varies per seed).
	var ear_count = rng.randi_range(2, 3)
	for i in range(ear_count):
		var ex = w * 0.72 + i * 5
		_fill_polygon(image, PackedVector2Array([
			Vector2(ex - 3, h * 0.30), Vector2(ex + 2, h * 0.30), Vector2(ex - 1, h * 0.12),
		]), shade)

	# Legs.
	for lx in [w * 0.32, w * 0.46, w * 0.62, w * 0.74]:
		_fill_rect(image, int(lx), int(h * 0.82), 4, int(h * 0.18), shade)

	# Tail.
	_fill_polygon(image, PackedVector2Array([
		Vector2(w * 0.24, h * 0.52), Vector2(w * 0.02, h * 0.30),
		Vector2(w * 0.08, h * 0.36), Vector2(w * 0.28, h * 0.60),
	]), shade)

	# Glowing eyes + fangs.
	var eye_glow = accent.lightened(0.4)
	image.set_pixel(int(w * 0.83), int(h * 0.40), eye_glow)
	image.set_pixel(int(w * 0.87), int(h * 0.42), eye_glow)
	_fill_rect(image, int(w * 0.83), int(h * 0.48), 1, 3, Color.WHITE)

	return ImageTexture.create_from_image(image)

# ---------------------------------------------------------------- Undead (skeletal/ghost enemies)

static func _build_undead(primary: Color, accent: Color, rng: RandomNumberGenerator) -> ImageTexture:
	var w = 34
	var h = 52
	var image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var bone = primary.lightened(0.1)

	# Tattered lower robe — jagged hem via seeded zig-zag.
	var hem_points := PackedVector2Array()
	hem_points.append(Vector2(w * 0.5 - 10, 22))
	hem_points.append(Vector2(w * 0.5 + 10, 22))
	var teeth = 5
	for i in range(teeth + 1):
		var tx = w * 0.5 + 10 - (20.0 * i / teeth)
		var ty = h - 4 if i % 2 == 0 else h - 4 - rng.randf_range(6.0, 12.0)
		hem_points.append(Vector2(tx, ty))
	_fill_polygon(image, hem_points, primary)
	_outline_polygon(image, hem_points, OUTLINE)

	# Ribcage accent lines.
	for ry in range(26, 40, 4):
		_fill_rect(image, int(w * 0.5 - 6), ry, 12, 1, accent.darkened(0.2))

	# Skull.
	_fill_ellipse(image, w * 0.5, 13, 7, 8, bone)
	_outline_ellipse(image, w * 0.5, 13, 7, 8, OUTLINE)
	var glow = accent.lightened(0.5)
	image.set_pixel(int(w * 0.5 - 3), 12, glow)
	image.set_pixel(int(w * 0.5 + 3), 12, glow)
	_fill_rect(image, int(w * 0.5 - 1), 17, 3, 2, OUTLINE)

	# Arms.
	_fill_rect(image, int(w * 0.5 - 12), 24, 3, 14, bone.darkened(0.1))
	_fill_rect(image, int(w * 0.5 + 9), 24, 3, 14, bone.darkened(0.1))

	return ImageTexture.create_from_image(image)

# ---------------------------------------------------------------- Swarm (rats/insects, small cluster)

static func _build_swarm(primary: Color, accent: Color, rng: RandomNumberGenerator) -> ImageTexture:
	var w = 40
	var h = 34
	var image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var shade = primary.darkened(0.3)

	var clusters = [
		Vector2(w * 0.30, h * 0.60), Vector2(w * 0.55, h * 0.72), Vector2(w * 0.72, h * 0.45),
	]
	for c in clusters:
		var rx = rng.randf_range(6.0, 8.0)
		var ry = rx * 0.7
		_fill_ellipse(image, c.x, c.y, rx, ry, primary)
		_outline_ellipse(image, c.x, c.y, rx, ry, OUTLINE)
		# Ear/snout nub.
		_fill_ellipse(image, c.x + rx * 0.8, c.y - ry * 0.2, 2, 2, shade)
		# Eye glint.
		image.set_pixel(int(c.x + rx * 0.6), int(c.y - ry * 0.3), accent.lightened(0.4))
		# Tail.
		_fill_rect(image, int(c.x - rx - 4), int(c.y), 4, 1, shade)

	return ImageTexture.create_from_image(image)

# ---------------------------------------------------------------- Raster helpers

static func _fill_rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var iw = image.get_width()
	var ih = image.get_height()
	for py in range(y, y + h):
		if py < 0 or py >= ih:
			continue
		for px in range(x, x + w):
			if px < 0 or px >= iw:
				continue
			image.set_pixel(px, py, color)

static func _fill_ellipse(image: Image, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	var iw = image.get_width()
	var ih = image.get_height()
	var min_x = maxi(0, int(cx - rx) - 1)
	var max_x = mini(iw - 1, int(cx + rx) + 1)
	var min_y = maxi(0, int(cy - ry) - 1)
	var max_y = mini(ih - 1, int(cy + ry) + 1)
	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			var nx = (px + 0.5 - cx) / rx
			var ny = (py + 0.5 - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				image.set_pixel(px, py, color)

static func _outline_ellipse(image: Image, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	var steps = 48
	for i in range(steps):
		var a = TAU * i / steps
		var px = int(round(cx + cos(a) * rx))
		var py = int(round(cy + sin(a) * ry))
		if px >= 0 and px < image.get_width() and py >= 0 and py < image.get_height():
			image.set_pixel(px, py, color)

static func _fill_polygon(image: Image, points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var iw = image.get_width()
	var ih = image.get_height()
	var min_y = ih
	var max_y = 0
	for p in points:
		min_y = mini(min_y, int(floor(p.y)))
		max_y = maxi(max_y, int(ceil(p.y)))
	min_y = maxi(0, min_y)
	max_y = mini(ih - 1, max_y)

	for py in range(min_y, max_y + 1):
		var y_test = py + 0.5
		var xs: Array[float] = []
		var n = points.size()
		for i in range(n):
			var a = points[i]
			var b = points[(i + 1) % n]
			if (a.y <= y_test and b.y > y_test) or (b.y <= y_test and a.y > y_test):
				var t = (y_test - a.y) / (b.y - a.y)
				xs.append(a.x + t * (b.x - a.x))
		xs.sort()
		var i = 0
		while i + 1 < xs.size():
			var x_start = maxi(0, int(round(xs[i])))
			var x_end = mini(iw - 1, int(round(xs[i + 1])))
			for px in range(x_start, x_end + 1):
				image.set_pixel(px, py, color)
			i += 2

static func _outline_polygon(image: Image, points: PackedVector2Array, color: Color) -> void:
	var n = points.size()
	for i in range(n):
		_draw_line(image, points[i], points[(i + 1) % n], color)

static func _draw_line(image: Image, from: Vector2, to: Vector2, color: Color) -> void:
	var iw = image.get_width()
	var ih = image.get_height()
	var dist = from.distance_to(to)
	var steps = maxi(1, int(dist))
	for i in range(steps + 1):
		var p = from.lerp(to, float(i) / steps)
		var px = int(round(p.x))
		var py = int(round(p.y))
		if px >= 0 and px < iw and py >= 0 and py < ih:
			image.set_pixel(px, py, color)
