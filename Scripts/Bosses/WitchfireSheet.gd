extends RefCounted
class_name WitchfireSheet

# The Witchfire Magus's fire, as artwork rather than as triangles.
#
# Three hazards draw the same fire — the arena wall, the sweeping wall and the
# eruption rings — and before this they each drew their own out of polygons and
# a sine. That was three descriptions of one thing, so the arena's flame and the
# sweep's flame licked at different rates and were different purples, and any
# change to how witchfire looks meant editing three files and hoping.
#
# This is the one description. It loads Assets/sprites/vfx/witchfire (built by
# tools/pixelforge/flames.py), cuts the sheet into per-frame textures once, and
# hands them out. Everything that burns in this fight is a rect filled with one
# of them.
#
# # Tiling
#
# The rows are authored to tile — `curtain` left to right, `ground` both ways —
# so a wall of any length is one frame repeated. Godot's own tiling
# (draw_texture_rect with tile = true) starts its pattern at the rect's own
# corner, which is wrong the moment a rect is split: the two halves of a wall
# either side of the flame wall's safe lane would each restart the pattern and
# the seam would be visible as a step. draw_tiled therefore lays the tiles out
# itself against a caller-chosen phase origin, so every piece of one hazard
# shares one grid however it is cut up.
#
# # Failure
#
# ready() is false when the sheet is missing or unreadable, and every caller
# keeps its polygons for that case. A hazard must never be invisible — the
# player is being asked to stand somewhere else because of it.

const SHEET_PATH := "res://Assets/sprites/vfx/witchfire/witchfire.png"
const SHEET_JSON := "res://Assets/sprites/vfx/witchfire/witchfire.json"

# Rows, by the names the atlas gives them.
const CURTAIN := "curtain"
const GROUND := "ground"
const PLUME := "plume"

# Loaded once for the whole run — the textures are 64x64 and there are 24 of
# them, and three hazards plus every eruption ring would otherwise each cut
# their own copy.
static var _frames: Dictionary = {}
static var _fps: Dictionary = {}
static var _cell: int = 64
static var _floor_y: float = 46.0
static var _flame_h: float = 44.0
static var _loaded: bool = false
static var _ok: bool = false

static func ready() -> bool:
	_ensure_loaded()
	return _ok

# The cell size in pixels: how big one tile is drawn at scale 1.
static func cell() -> float:
	_ensure_loaded()
	return float(_cell)

# Where the ground plane crosses a cell, measured from its top. A curtain drawn
# with its floor line on a wall puts its fire on the outward side of that wall
# and its scorch on the inward one.
static func floor_y() -> float:
	_ensure_loaded()
	return _floor_y

# How far the flame reaches above the floor line. What a caller scales against
# when its own hazard is deeper than the artwork — see FlameWall, whose sheet is
# as thick as the attack says rather than as thick as the sprite is.
static func flame_height() -> float:
	_ensure_loaded()
	return _flame_h

# The frame of `row` showing at `time` seconds. Loops on the row's own fps, out
# of the atlas, so retiming the artwork does not need a change here.
static func frame(row: String, time: float) -> Texture2D:
	_ensure_loaded()
	var list: Array = _frames.get(row, [])
	if list.is_empty():
		return null

	var fps: float = _fps.get(row, 12.0)
	return list[int(time * fps) % list.size()]

# Fills `rect` with `tex`, tiled on a grid anchored at `phase`.
#
# `phase` is what keeps a pattern still while the thing drawing it moves, and
# what keeps two pieces of one hazard on one grid. Pass the same phase for every
# piece of the same fire.
#
# `stagger` shifts every other row half a tile, the way bricks are laid. A tile
# with anything recognisable in it announces its own grid the moment it covers
# more than a few cells — the burnt ground of a sweep is nine tiles by four —
# and half of that grid is the vertical seams lining up. Worth it wherever a
# fill is large; pointless on a wall, which is one row of tiles.
static func draw_tiled(item: CanvasItem, tex: Texture2D, rect: Rect2, phase: Vector2,
	tile: float = 0.0, modulate: Color = Color.WHITE, stagger: bool = false) -> void:
	if tex == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var step := tile if tile > 0.0 else cell()
	if step <= 0.0:
		return

	# Guard rather than trust: a rect the size of the world at a one-pixel tile
	# is a frozen frame, and the arena's numbers come from a resource.
	var columns := int(ceil(rect.size.x / step)) + 1
	var rows := int(ceil(rect.size.y / step)) + 1
	if columns * rows > 4096:
		item.draw_texture_rect(tex, rect, true, modulate)
		return

	var size := tex.get_size()
	var start := Vector2(
		phase.x + floor((rect.position.x - phase.x) / step) * step,
		phase.y + floor((rect.position.y - phase.y) / step) * step)

	var y := start.y
	var row := 0
	while y < rect.end.y:
		# Half a tile left on odd rows, and one tile further left to start, so
		# the shifted row still covers the left edge of the rect.
		var shift := step * 0.5 if stagger and row % 2 else 0.0
		var x := start.x - shift - (step if shift > 0.0 else 0.0)
		while x < rect.end.x:
			var piece := Rect2(x, y, step, step).intersection(rect)
			if piece.size.x > 0.0 and piece.size.y > 0.0:
				# The tile is clipped by taking the matching corner of the
				# source, so a partial tile at the edge of a band is a partial
				# tile and not a squashed whole one.
				var src := Rect2(
					(piece.position - Vector2(x, y)) / step * size,
					piece.size / step * size)
				item.draw_texture_rect_region(tex, piece, src, modulate)

			x += step
		y += step
		row += 1

# ---------------------------------------------------------------------------
static func _ensure_loaded() -> void:
	if _loaded:
		return

	_loaded = true
	var texture := load(SHEET_PATH) as Texture2D
	if texture == null:
		push_warning("[WitchfireSheet] %s missing — hazards keep their polygons." % SHEET_PATH)
		return

	var image := texture.get_image()
	if image == null:
		push_warning("[WitchfireSheet] %s has no readable image." % SHEET_PATH)
		return

	var meta := _read_meta()
	if meta.is_empty():
		return

	_cell = int(meta.get("frameWidth", 64))
	_floor_y = float(meta.get("floorY", _cell * 0.72))
	_flame_h = float(meta.get("flameHeight", _floor_y))
	var columns := int(meta.get("columns", 8))
	var animations: Dictionary = meta.get("animations", {})

	for row_name in [CURTAIN, GROUND, PLUME]:
		if not animations.has(row_name):
			continue

		var anim: Dictionary = animations[row_name]
		var list: Array[Texture2D] = []
		for index in anim.get("frames", []):
			var i := int(index)
			var region := Rect2i((i % columns) * _cell, (i / columns) * _cell, _cell, _cell)
			list.append(ImageTexture.create_from_image(image.get_region(region)))

		if list.is_empty():
			continue

		_frames[row_name] = list
		_fps[row_name] = float(anim.get("fps", 12))

	_ok = not _frames.is_empty()

static func _read_meta() -> Dictionary:
	if not FileAccess.file_exists(SHEET_JSON):
		push_warning("[WitchfireSheet] %s missing." % SHEET_JSON)
		return {}

	var text := FileAccess.get_file_as_string(SHEET_JSON)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[WitchfireSheet] %s is not an atlas." % SHEET_JSON)
		return {}

	return parsed
