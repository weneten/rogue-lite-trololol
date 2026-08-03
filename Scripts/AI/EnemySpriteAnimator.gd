extends Node
class_name EnemySpriteAnimator

# Drives an AnimatedSprite2D from Nightbane sprite sheets. Owns facing, locomotion
# (idle/run), one-shot hurt/attack/death, and scale/modulate from EnemyData.

@export var sprite_path: NodePath

var _sprite: AnimatedSprite2D
var _sheet_path: String = ""
var _attack_anim: String = "attack_slash"
var _current_locomotion: String = "idle"
var _one_shot_playing: bool = false
var _dead: bool = false
var _base_scale: float = 1.0

# Every living entity — player included — must sit on the SAME z layer, because
# z_index outranks Y-sorting: a body one layer up draws over everything below it
# no matter where its feet are. Zero is that shared layer, and it goes on the
# CharacterBody2D root, because Y-sort draws each root as one unit — a z set on
# the child sprite can only order visuals *inside* one entity, never across two.
# Corpses drop the root below every living unit, still above floor and props.
const LIVING_Z := 0
const SPRITE_Z := 2
const CORPSE_Z := -1

func get_is_death_playing() -> bool:
	return _dead and _one_shot_playing

func get_has_frames() -> bool:
	return _sprite != null and _sprite.sprite_frames != null and _sprite.sprite_frames.get_animation_names().size() > 0

func get_sprite() -> AnimatedSprite2D:
	return _sprite

func _ready() -> void:
	_resolve_sprite()
	if _sprite != null:
		# Sheets are hand-sized pixel art; filtering them destroys the edges.
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.centered = true
		_sprite.animation_finished.connect(_on_animation_finished)

func _exit_tree() -> void:
	if _sprite != null:
		_sprite.animation_finished.disconnect(_on_animation_finished)

# Swap sheet / attack anim / scale / tint for a pooled enemy re-arm.
# Returns true when frames were applied successfully.
func configure(sheet_path: String, json_path: String, attack_anim_name: String, scale: float, modulate: Color, preloaded_texture: Texture2D = null) -> bool:
	_resolve_sprite()

	_dead = false
	_one_shot_playing = false
	_base_scale = scale if scale > 0.0 else 1.0
	_attack_anim = attack_anim_name if not attack_anim_name.is_empty() else "attack_slash"
	_sheet_path = sheet_path

	if _sprite == null:
		push_error("[EnemySpriteAnimator] No AnimatedSprite2D found (Sprite child missing).")
		return false

	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	_sprite.z_index = SPRITE_Z
	_set_host_z(LIVING_Z)

	var loaded = false
	if not sheet_path.is_empty() or preloaded_texture != null:
		var frames = SpriteSheetCache.get_frames(sheet_path, json_path, preloaded_texture)
		if frames != null:
			_sprite.sprite_frames = frames
			_sprite.offset = SpriteSheetCache.get_sprite_offset(sheet_path)
			loaded = true

	# Avoid harsh full-tint washes that can hide pixel art; keep mild color keys.
	var tint = modulate
	if modulate.a <= 0.001:
		tint = Color.WHITE
	# Soften extreme multiplies so sprites stay readable under CanvasModulate.
	tint = Color(
		clampf(tint.r, 0.55, 1.35),
		clampf(tint.g, 0.55, 1.35),
		clampf(tint.b, 0.55, 1.35),
		clampf(tint.a, 0.7, 1.0))
	_sprite.modulate = tint
	_sprite.scale = Vector2.ONE * _base_scale
	_sprite.flip_h = false
	_sprite.visible = loaded

	if loaded:
		_attack_anim = _resolve_attack_anim(_attack_anim)
		_play_locomotion("idle", true)

	return loaded

func reset_visual() -> void:
	_dead = false
	_one_shot_playing = false
	_set_host_z(LIVING_Z)
	if _sprite != null:
		_sprite.z_index = SPRITE_Z
		_sprite.visible = get_has_frames()
		_sprite.modulate = Color.WHITE
		_sprite.scale = Vector2.ONE * _base_scale
		_sprite.flip_h = false

	if get_has_frames():
		_play_locomotion("idle", true)

# Face movement / target. Positive dirX → face right (sheet default).
func set_facing(dir_x: float) -> void:
	if _sprite == null or absf(dir_x) < 0.05:
		return

	# Sheets face right; FlipH when moving/aiming left.
	_sprite.flip_h = dir_x < 0.0

func update_locomotion(moving: bool) -> void:
	if _dead or _one_shot_playing:
		return

	_play_locomotion("run" if moving else "idle")

func play_hurt() -> void:
	if _dead or _sprite == null:
		return

	_play_one_shot("hurt")

func play_attack() -> void:
	if _dead or _sprite == null:
		return

	_play_one_shot(_attack_anim)

# Plays death and returns when finished (or immediately if no sprite/anim).
func play_death_async() -> void:
	_dead = true
	# Drop host root below every living entity. Child sprite z_index alone
	# cannot interleave with the player — y-sort draws each CharacterBody2D
	# as a unit, so a body south of the player would still draw over them.
	_set_host_z(CORPSE_Z)
	if _sprite != null:
		_sprite.z_index = CORPSE_Z
	if _sprite == null or _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation("death"):
		return

	_one_shot_playing = true
	_sprite.play("death")

	var timeout = 1.2
	if _sprite.sprite_frames.has_animation("death"):
		var count = _sprite.sprite_frames.get_frame_count("death")
		var speed = _sprite.sprite_frames.get_animation_speed("death")
		if speed > 0.01:
			timeout = maxf(0.35, count / speed + 0.15)

	var timer = get_tree().create_timer(timeout)
	await timer.timeout
	_one_shot_playing = false

func _resolve_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return

	if sprite_path != null and not sprite_path.is_empty():
		_sprite = get_node_or_null(sprite_path) as AnimatedSprite2D

	# Sibling under Enemy root — most reliable.
	if _sprite == null and get_parent() != null:
		_sprite = get_parent().get_node_or_null("Sprite") as AnimatedSprite2D

	if _sprite == null:
		_sprite = get_parent().find_child("Sprite", true, false) as AnimatedSprite2D

# z_index must live on the CharacterBody2D root (sibling of Player under World)
# for corpse layering; child-only z never crosses entity boundaries.
func _set_host_z(z: int) -> void:
	var host := get_parent() as CanvasItem
	if host != null:
		host.z_index = z

func _play_locomotion(name: String, force: bool = false) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return

	if not force and _current_locomotion == name and _sprite.is_playing():
		return

	if not _sprite.sprite_frames.has_animation(name):
		name = "idle"

	if not _sprite.sprite_frames.has_animation(name):
		return

	_current_locomotion = name
	if not _one_shot_playing and not _dead:
		_sprite.play(name)

func _play_one_shot(name: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return

	if not _sprite.sprite_frames.has_animation(name) or _sprite.sprite_frames.get_frame_count(name) == 0:
		name = _resolve_attack_anim(name)
		if not _sprite.sprite_frames.has_animation(name):
			return

	_one_shot_playing = true
	_sprite.play(name)

func _on_animation_finished() -> void:
	if _dead:
		_one_shot_playing = false
		return

	if _one_shot_playing:
		_one_shot_playing = false
		if _sprite != null and _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(_current_locomotion):
			_sprite.play(_current_locomotion)

func _resolve_attack_anim(preferred: String) -> String:
	if _sprite == null or _sprite.sprite_frames == null:
		return preferred

	if _sprite.sprite_frames.has_animation(preferred) and _sprite.sprite_frames.get_frame_count(preferred) > 0:
		return preferred

	var fallbacks = [
		preferred,
		"attack_slash",
		"attack_whip",
		"attack_orbs",
		"shield_bash",
		"chain_swing",
		"attack_spin",
		"attack_nova",
		"attack_cross",
		"hurt"
	]

	for fallback_name in fallbacks:
		if not fallback_name.is_empty() and _sprite.sprite_frames.has_animation(fallback_name) and _sprite.sprite_frames.get_frame_count(fallback_name) > 0:
			return fallback_name

	return "idle"
