class_name SpriteSheetCache

# Builds and caches SpriteFrames from Nightbane sprite-sheet JSON + PNG pairs
# under Assets/sprites. Shared across all enemy instances.

static var _cache: Dictionary = {}
static var _origin_cache: Dictionary = {}

# Loads or returns cached SpriteFrames. Prefer passing an already-imported
# preloaded_texture (from EnemyData.SpriteSheet) — path-only
# GD.Load can fail with "No loader found" if import state is flaky.
static func get_frames(sheet_path: String, json_path: String = "", preloaded_texture: Texture2D = null) -> SpriteFrames:
	var cache_key = ""
	if not sheet_path.is_empty():
		cache_key = sheet_path
	elif preloaded_texture != null:
		cache_key = preloaded_texture.resource_path if not preloaded_texture.resource_path.is_empty() else str(preloaded_texture.get_instance_id())

	if cache_key.is_empty():
		return null

	if _cache.has(cache_key) and is_instance_valid(_cache[cache_key]):
		return _cache[cache_key]

	var texture = preloaded_texture
	if texture == null or not is_instance_valid(texture):
		texture = _load_texture(sheet_path)

	if texture == null:
		push_error("[SpriteSheetCache] Missing texture: %s" % sheet_path)
		return null

	var resolved_json = _resolve_json_path(sheet_path, json_path)
	if resolved_json.is_empty() or not FileAccess.file_exists(resolved_json):
		push_error("[SpriteSheetCache] Missing json: %s" % resolved_json)
		return null

	var json_text = ""
	var file = FileAccess.open(resolved_json, FileAccess.READ)
	if file == null:
		push_error("[SpriteSheetCache] Cannot open json: %s" % resolved_json)
		return null

	json_text = file.get_as_text()

	# Prefer Godot JSON — no System.Text.Json dependency / AOT issues.
	var parser = JSON.new()
	var parse_err = parser.parse(json_text)
	if parse_err != OK:
		push_error("[SpriteSheetCache] Bad json '%s': %s" % [resolved_json, parser.get_error_message()])
		return null

	if typeof(parser.data) != TYPE_DICTIONARY:
		push_error("[SpriteSheetCache] JSON root is not an object: %s" % resolved_json)
		return null

	var meta = parser.data as Dictionary
	var frame_width = _dict_int(meta, "frameWidth", "frame_width")
	var frame_height = _dict_int(meta, "frameHeight", "frame_height")
	var columns = _dict_int(meta, "columns")

	if frame_width <= 0 or frame_height <= 0:
		push_error("[SpriteSheetCache] Incomplete meta (frame size): %s" % resolved_json)
		return null

	if columns <= 0:
		columns = maxi(1, texture.get_width() / frame_width)

	if not meta.has("animations") or typeof(meta["animations"]) != TYPE_DICTIONARY:
		push_error("[SpriteSheetCache] Incomplete meta (animations): %s" % resolved_json)
		return null

	var animations = meta["animations"] as Dictionary
	var frames = SpriteFrames.new()

	# Drop engine default "default" anim so we don't flash empty.
	if frames.has_animation("default"):
		frames.remove_animation("default")

	for anim_key in animations.keys():
		var anim_name = str(anim_key)
		if anim_name.is_empty():
			continue

		var anim_var = animations[anim_key]
		if typeof(anim_var) != TYPE_DICTIONARY:
			continue

		var anim = anim_var as Dictionary
		if frames.has_animation(anim_name):
			frames.remove_animation(anim_name)

		frames.add_animation(anim_name)
		var loop = _dict_bool(anim, "loop")
		frames.set_animation_loop_mode(anim_name, SpriteFrames.LOOP_LINEAR if loop else SpriteFrames.LOOP_NONE)
		var fps = _dict_float(anim, "fps", 10.0)
		if fps <= 0.0:
			fps = 10.0

		frames.set_animation_speed(anim_name, fps)

		var indices = _read_frame_indices(anim)
		for frame_index in indices:
			var col = frame_index % columns
			var row = frame_index / columns
			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)
			atlas.filter_clip = true
			frames.add_frame(anim_name, atlas, 1.0)

	_ensure_anim(frames, "idle")
	_ensure_anim(frames, "run", "idle")
	_ensure_anim(frames, "hurt", "idle")
	_ensure_anim(frames, "death", "hurt")

	_cache[cache_key] = frames

	var ox = frame_width * 0.5
	var oy = frame_height as float
	if meta.has("origin") and typeof(meta["origin"]) == TYPE_DICTIONARY:
		var origin = meta["origin"] as Dictionary
		ox = _dict_float(origin, "x", ox)
		oy = _dict_float(origin, "y", oy)

	# Offset so pivot (feet) sits on CharacterBody2D origin when sprite is centered.
	_origin_cache[cache_key] = Vector2(frame_width * 0.5 - ox, frame_height * 0.5 - oy)

	print("[SpriteSheetCache] Loaded '%s' — %d anims, %dx%d." % [cache_key, frames.get_animation_names().size(), frame_width, frame_height])
	return frames

static func get_sprite_offset(sheet_path: String) -> Vector2:
	if not sheet_path.is_empty() and _origin_cache.has(sheet_path):
		return _origin_cache[sheet_path]

	return Vector2(0, -26)

static func _load_texture(sheet_path: String) -> Texture2D:
	if sheet_path.is_empty():
		return null

	# 1) Normal resource load (preferred when .import is healthy).
	if ResourceLoader.exists(sheet_path):
		var via_loader = ResourceLoader.load(sheet_path, "Texture2D") as Texture2D
		if via_loader != null:
			return via_loader

	var via_gd = load(sheet_path) as Texture2D
	if via_gd != null:
		return via_gd

	# 2) Fallback: decode PNG bytes ourselves (works even when importer is broken).
	if not FileAccess.file_exists(sheet_path):
		return null

	var bytes = FileAccess.get_file_as_bytes(sheet_path)
	if bytes == null or bytes.is_empty():
		return null

	var image = Image.new()
	var err = image.load_png_from_buffer(bytes)
	if err != OK:
		# Try generic image load via globalized path.
		var global = ProjectSettings.globalize_path(sheet_path)
		err = image.load(global)
		if err != OK:
			push_error("[SpriteSheetCache] Image decode failed for %s: %s" % [sheet_path, err])
			return null

	var image_tex = ImageTexture.create_from_image(image)
	push_warning("[SpriteSheetCache] Used ImageTexture fallback for %s" % sheet_path)
	return image_tex

static func _resolve_json_path(sheet_path: String, json_path: String) -> String:
	if not json_path.is_empty():
		return json_path

	if sheet_path.is_empty():
		return ""

	var dot = sheet_path.rfind('.')
	return sheet_path.substr(0, dot) + ".json" if dot > 0 else sheet_path + ".json"

static func _read_frame_indices(anim: Dictionary) -> Array:
	if anim.has("frames") and typeof(anim["frames"]) == TYPE_ARRAY:
		var arr = anim["frames"] as Array
		var list: Array[int] = []
		for v in arr:
			list.append(int(v))

		if list.size() > 0:
			return list

	var from = _dict_int(anim, "from")
	var to = _dict_int(anim, "to", from)
	if to < from:
		to = from

	var range_arr: Array[int] = []
	for i in range(to - from + 1):
		range_arr.append(from + i)

	return range_arr

static func _ensure_anim(frames: SpriteFrames, name: String, fallback: String = "") -> void:
	if frames.has_animation(name) and frames.get_frame_count(name) > 0:
		return

	var source = fallback
	if source.is_empty() or not frames.has_animation(source) or frames.get_frame_count(source) == 0:
		var names = frames.get_animation_names()
		if names == null or names.size() == 0:
			return

		source = names[0]

	if frames.has_animation(name):
		frames.remove_animation(name)

	frames.add_animation(name)
	frames.set_animation_loop_mode(name, SpriteFrames.LOOP_LINEAR if name in ["idle", "run"] else SpriteFrames.LOOP_NONE)
	frames.set_animation_speed(name, frames.get_animation_speed(source))
	var count = frames.get_frame_count(source)
	for i in range(count):
		frames.add_frame(name, frames.get_frame_texture(source, i), frames.get_frame_duration(source, i))

static func _dict_int(d: Dictionary, key: String, alt_key: String = "", fallback: int = 0) -> int:
	if d.has(key):
		return int(d[key])

	if not alt_key.is_empty() and d.has(alt_key):
		return int(d[alt_key])

	return fallback

static func _dict_float(d: Dictionary, key: String, fallback: float = 0.0) -> float:
	if not d.has(key):
		return fallback

	return float(d[key])

static func _dict_bool(d: Dictionary, key: String, fallback: bool = false) -> bool:
	if not d.has(key):
		return fallback

	return bool(d[key])
