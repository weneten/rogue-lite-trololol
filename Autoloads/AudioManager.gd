extends Node

# Music/SFX hub. Shop phase = calm track; combat waves = layered base+percussion with
# intensity-driven percussion volume; boss = public play_boss_music/stop_boss_music plus
# defensive EventBus boss-signal hooks (Bosses stage may add them later). Volume API
# routes through Master/Music/SFX AudioServer buses for SettingsMenu.

const BUS_MASTER: String = "Master"
const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"

const SFX_POOL_SIZE: int = 8
const CROSSFADE_SECONDS: float = 0.85
const INTENSITY_LERP_SPEED: float = 2.5

# Boss-wave fallback until Bosses stage wires play_boss_music / boss_encounter_start/end.
var boss_fallback_waves: Array[int] = [10, 15, 20]

@export var master_volume: float = 1.0
@export var music_volume: float = 1.0
@export var sfx_volume: float = 1.0

const SFX_DIR: String = "res://Assets/Audio/sfx/"

# The generated beds under Assets/Audio/music — see Assets/Audio/README.md and
# tools/build_music.py. Still overridable by assigning a different stream here.
#
# combat_base and combat_percussion are two halves of one 132 BPM arrangement
# of the same length, so they stay in phase however long a wave runs.
@export var shop_music_stream: AudioStream = preload("res://Assets/Audio/music/shop.wav")
@export var combat_base_stream: AudioStream = preload("res://Assets/Audio/music/combat_base.wav")
@export var combat_percussion_stream: AudioStream = preload("res://Assets/Audio/music/combat_percussion.wav")
@export var boss_music_stream: AudioStream = preload("res://Assets/Audio/music/boss.wav")
@export var menu_music_stream: AudioStream = preload("res://Assets/Audio/music/menu.wav")

# SFX stream map filled in _ready from Assets/Audio/sfx; missing files fall
# back to the null/silence-safe placeholder.
var _sfx_streams: Dictionary = {}

var _shop_music: AudioStreamPlayer
var _combat_base: AudioStreamPlayer
var _combat_percussion: AudioStreamPlayer
var _boss_music: AudioStreamPlayer
var _menu_music: AudioStreamPlayer

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int

enum MusicMode {
	NONE,
	MENU,
	SHOP,
	COMBAT,
	BOSS
}

var _mode: MusicMode = MusicMode.NONE
var _target_mode: MusicMode = MusicMode.NONE
var _crossfade_t: float = 1.0
var _intensity: float = 0.0  # 0..1, drives percussion layer
var _target_intensity: float = 0.0
var _boss_active: bool = false
var _current_wave: int = 0
var _web_audio_unlocked: bool = false
var _cached_enemy_density: float = 0.0
var _density_refresh_remaining: float = 0.0

const DENSITY_REFRESH_SECONDS := 0.25

func _ready() -> void:
	_ensure_buses()
	_build_players()
	_register_placeholder_sfx()
	_apply_all_volumes()
	_subscribe_gameplay()
	_try_subscribe_boss_signals()

	# Default: menu bed when booting into MainMenu.
	play_music("menu")

func _process(delta: float) -> void:
	_update_intensity(delta)
	_update_crossfade(delta)
	_apply_percussion_volume()

# Browsers block AudioContext until a user gesture; restart the active bed once.
func _input(event: InputEvent) -> void:
	if _web_audio_unlocked or not OS.has_feature("web"):
		return
	if not (
		event is InputEventMouseButton
		or event is InputEventKey
		or event is InputEventScreenTouch
		or event is InputEventJoypadButton
	):
		return
	if not event.is_pressed():
		return

	_web_audio_unlocked = true
	_ensure_mode_playing(_target_mode if _target_mode != MusicMode.NONE else _mode)

# -------------------------------------------------------------------------
# Public API (stable)
# -------------------------------------------------------------------------

func play_sfx(sfx_id: String) -> void:
	if sfx_id.is_empty():
		return

	var stream: AudioStream = _sfx_streams.get(sfx_id)
	# Silence-safe: missing/null stream = no audible output, still log for hook wiring.
	if stream == null:
		return

	var player: AudioStreamPlayer = _sfx_pool[_sfx_pool_index]
	_sfx_pool_index = (_sfx_pool_index + 1) % _sfx_pool.size()
	player.stream = stream
	player.play()

func play_music(track_id: String) -> void:
	if track_id.is_empty():
		return

	var lower: String = track_id.to_lower()
	match lower:
		"menu":
			_request_mode(MusicMode.MENU)
		"shop":
			_request_mode(MusicMode.SHOP)
		"combat", "wave":
			if !_boss_active:
				_request_mode(MusicMode.COMBAT)
		"boss":
			play_boss_music()
		"stop", "none":
			_request_mode(MusicMode.NONE)
		_:
			print("[AudioManager] Unknown music trackId '%s'" % track_id)

# Boss encounter spike. Bosses stage should call this when a boss spawns.
func play_boss_music() -> void:
	_boss_active = true
	_request_mode(MusicMode.BOSS)
	_target_intensity = 1.0

# End boss theme; returns to combat layers if a wave is active, else shop.
func stop_boss_music() -> void:
	_boss_active = false
	if WaveManager != null and WaveManager.is_wave_active:
		_request_mode(MusicMode.COMBAT)
	else:
		_request_mode(MusicMode.SHOP)

func set_master_volume(linear01: float) -> void:
	master_volume = clampf(linear01, 0.0, 1.0)
	_set_bus_linear(BUS_MASTER, master_volume)

func set_music_volume(linear01: float) -> void:
	music_volume = clampf(linear01, 0.0, 1.0)
	_set_bus_linear(BUS_MUSIC, music_volume)

func set_sfx_volume(linear01: float) -> void:
	sfx_volume = clampf(linear01, 0.0, 1.0)
	_set_bus_linear(BUS_SFX, sfx_volume)
	# Sample playback on web can ignore bus volume; keep the pool in sync.
	for player in _sfx_pool:
		if player != null:
			_set_player_linear(player, sfx_volume)

# -------------------------------------------------------------------------
# Setup
# -------------------------------------------------------------------------

func _ensure_buses() -> void:
	# Prefer project default_bus_layout.tres (Music/SFX). Runtime add_bus works on
	# desktop but is silently broken on Godot 4.x web — HTML5 needs the layout.
	var had_layout: bool = (
		AudioServer.get_bus_index(BUS_MUSIC) >= 0
		and AudioServer.get_bus_index(BUS_SFX) >= 0
	)
	_ensure_bus(BUS_MUSIC, BUS_MASTER)
	_ensure_bus(BUS_SFX, BUS_MASTER)
	if not had_layout:
		push_warning(
			"[AudioManager] Music/SFX buses missing from default_bus_layout.tres; "
			+ "runtime-created buses are silent on web export."
		)

static func _ensure_bus(name: String, send_to: String) -> void:
	if AudioServer.get_bus_index(name) >= 0:
		return

	var idx: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, send_to)

func _build_players() -> void:
	_shop_music = _make_music_player("ShopMusic", shop_music_stream)
	_combat_base = _make_music_player("CombatBase", combat_base_stream)
	_combat_percussion = _make_music_player("CombatPercussion", combat_percussion_stream)
	_boss_music = _make_music_player("BossMusic", boss_music_stream)
	_menu_music = _make_music_player("MenuMusic", menu_music_stream)

	for i in range(SFX_POOL_SIZE):
		var sfx: AudioStreamPlayer = AudioStreamPlayer.new()
		sfx.name = "SfxPool_%d" % i
		sfx.bus = BUS_SFX
		sfx.volume_db = 0.0
		_configure_web_playback(sfx)
		add_child(sfx)
		_sfx_pool.append(sfx)

func _make_music_player(name: String, stream: AudioStream) -> AudioStreamPlayer:
	_ensure_loop(stream)

	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = name
	player.bus = BUS_MUSIC
	player.stream = stream  # may be null — silence-safe until assets assigned
	player.volume_db = -80.0
	_configure_web_playback(player)
	add_child(player)
	return player

# playback_type: 0=Default, 1=Stream, 2=Sample.
# Stream mixes on the WASM main thread — Chrome copes, Firefox hitchs and can
# throw on tree pause (shop / level-up). Sample is the Godot 4.3+ web default.
static func _configure_web_playback(player: AudioStreamPlayer) -> void:
	if OS.has_feature("web"):
		player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE

# Music beds are generated WAVs with no authored loop points, so the loop is
# set here in code rather than relying on editor import settings.
static func _ensure_loop(stream: AudioStream) -> void:
	var wav := stream as AudioStreamWAV
	if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)

func _register_placeholder_sfx() -> void:
	# Keys used by EventBus hooks + call-site wires. Loaded from Assets/Audio/sfx;
	# any id with no matching file stays null (silence-safe placeholder).
	var ids: Array[String] = [
		"enemy_death",
		"player_hit",
		"player_death",
		"weapon_melee",
		"weapon_ranged",
		"weapon_firearm",
		"weapon_magic",
		"weapon_holy",
		"weapon_cursed",
		"weapon_aoe",
		"weapon_summon",
		"weapon_trap",
		"weapon_hit",
		"ui_click",
		"ui_confirm",
		"ui_levelup",
		"ui_shop_open",
		"ui_purchase",
		"pickup_material"
	]

	for id: String in ids:
		var path := SFX_DIR + id + ".wav"
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path) as AudioStream
			_sfx_streams[id] = stream
			if stream == null:
				push_warning("[AudioManager] Failed to load SFX '%s' at %s" % [id, path])
		else:
			_sfx_streams[id] = null
			push_warning("[AudioManager] Missing SFX '%s' at %s" % [id, path])

func _apply_all_volumes() -> void:
	set_master_volume(master_volume)
	set_music_volume(music_volume)
	set_sfx_volume(sfx_volume)

static func _set_bus_linear(bus_name: String, linear01: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return

	# 0 linear = mute (-80 dB floor); Godot linear_to_db(0) is -inf which AudioServer rejects.
	var db: float = -80.0 if linear01 <= 0.0001 else linear_to_db(linear01)
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, linear01 <= 0.0001)

# -------------------------------------------------------------------------
# Event wiring
# -------------------------------------------------------------------------

func _subscribe_gameplay() -> void:
	if EventBus == null:
		return

	EventBus.enemy_killed.connect(_on_enemy_killed_sfx)
	EventBus.player_damaged.connect(_on_player_damaged_sfx)
	EventBus.player_died.connect(_on_player_died_sfx)
	EventBus.wave_start.connect(_on_wave_start_music)
	EventBus.wave_end.connect(_on_wave_end_music)
	# Level-up chime fired from LevelUpUI call site (not EventBus) to avoid double-play.

# Bosses stage may add boss_encounter_start/end on EventBus concurrently. Connect by
# string name only if present so this autoload never hard-depends on missing signals.
func _try_subscribe_boss_signals() -> void:
	var bus: Node = EventBus
	if bus == null:
		return

	# Typed C# events match EventBus signatures (name+wave / name+defeated).
	# Prefer these over zero-arg Callables so Godot never arity-mismatches.
	EventBus.boss_encounter_start.connect(_on_boss_encounter_start_music)
	EventBus.boss_encounter_end.connect(_on_boss_encounter_end_music)

func _on_boss_encounter_start_music(boss_name: String, wave_number: int) -> void:
	play_boss_music()

func _on_boss_encounter_end_music(boss_name: String, defeated: bool) -> void:
	stop_boss_music()

func _on_enemy_killed_sfx(enemy: Node, currency_reward: int, experience_reward: int) -> void:
	play_sfx("enemy_death")

func _on_player_damaged_sfx(damage_amount: float, current_health: float) -> void:
	play_sfx("player_hit")

func _on_player_died_sfx() -> void:
	play_sfx("player_death")

func _on_wave_start_music(wave_number: int) -> void:
	_current_wave = wave_number

	# BossManager owns music via boss_encounter_start; only start combat bed here.
	# (Fallback waves kept as soft intensity bump if boss spawn fails.)
	if !_boss_active:
		if boss_fallback_waves.has(wave_number):
			# Soft spike if BossManager has not yet flipped _boss_active this frame.
			_target_intensity = 1.0

		play_music("combat")

func _on_wave_end_music(wave_number: int) -> void:
	if _boss_active:
		stop_boss_music()

	play_music("shop")
	play_sfx("ui_shop_open")
	_target_intensity = 0.0

# -------------------------------------------------------------------------
# Music state / intensity
# -------------------------------------------------------------------------

func _request_mode(mode: MusicMode) -> void:
	if _target_mode == mode and _mode == mode and _crossfade_t >= 1.0:
		return

	_target_mode = mode
	_crossfade_t = 0.0
	_ensure_mode_playing(mode)

func _ensure_mode_playing(mode: MusicMode) -> void:
	# Start target players (looping streams) at low volume; crossfade ramps them.
	match mode:
		MusicMode.MENU:
			_safe_play(_menu_music)
		MusicMode.SHOP:
			_safe_play(_shop_music)
		MusicMode.COMBAT:
			_safe_play(_combat_base)
			_safe_play(_combat_percussion)
		MusicMode.BOSS:
			_safe_play(_boss_music)

static func _safe_play(player: AudioStreamPlayer) -> void:
	if player == null or player.stream == null:
		return

	if !player.playing:
		player.play()

func _update_crossfade(delta: float) -> void:
	if _crossfade_t >= 1.0 and _mode == _target_mode:
		return

	_crossfade_t = minf(1.0, _crossfade_t + delta / CROSSFADE_SECONDS)
	var t: float = _smooth01(_crossfade_t)

	# Fade all music players toward their target role volumes.
	var menu_vol: float = t if _target_mode == MusicMode.MENU else (1.0 - t if _mode == MusicMode.MENU else 0.0)
	var shop_vol: float = t if _target_mode == MusicMode.SHOP else (1.0 - t if _mode == MusicMode.SHOP else 0.0)
	var combat_vol: float = t if _target_mode == MusicMode.COMBAT else (1.0 - t if _mode == MusicMode.COMBAT else 0.0)
	var boss_vol: float = t if _target_mode == MusicMode.BOSS else (1.0 - t if _mode == MusicMode.BOSS else 0.0)

	# When starting a fade from None, outgoing is 0; when finishing, lock mode.
	if _mode == MusicMode.NONE and _target_mode != MusicMode.NONE:
		menu_vol = t if _target_mode == MusicMode.MENU else 0.0
		shop_vol = t if _target_mode == MusicMode.SHOP else 0.0
		combat_vol = t if _target_mode == MusicMode.COMBAT else 0.0
		boss_vol = t if _target_mode == MusicMode.BOSS else 0.0

	_set_player_linear(_menu_music, menu_vol)
	_set_player_linear(_shop_music, shop_vol)
	_set_player_linear(_combat_base, combat_vol)
	# Percussion uses combat_vol * intensity (applied in _apply_percussion_volume).
	_set_player_linear(_boss_music, boss_vol)

	if _crossfade_t >= 1.0:
		_stop_if_silent(_menu_music, menu_vol)
		_stop_if_silent(_shop_music, shop_vol)
		_stop_if_silent(_combat_base, combat_vol)
		_stop_if_silent(_boss_music, boss_vol)
		if _target_mode != MusicMode.COMBAT:
			_stop_if_silent(_combat_percussion, 0.0)

		_mode = _target_mode

func _apply_percussion_volume() -> void:
	var combat_presence: float = 0.0
	if _target_mode == MusicMode.COMBAT:
		combat_presence = 1.0 if _mode == MusicMode.COMBAT else _crossfade_t
	elif _mode == MusicMode.COMBAT:
		combat_presence = 1.0 - _crossfade_t

	_set_player_linear(_combat_percussion, combat_presence * _intensity)

func _update_intensity(delta: float) -> void:
	_density_refresh_remaining -= delta
	if _density_refresh_remaining <= 0.0:
		_refresh_enemy_density()
		_density_refresh_remaining = DENSITY_REFRESH_SECONDS

	if _boss_active or _target_mode == MusicMode.BOSS:
		_target_intensity = 1.0
	elif _target_mode == MusicMode.COMBAT or _mode == MusicMode.COMBAT:
		_target_intensity = _compute_combat_intensity()
	else:
		_target_intensity = 0.0

	_intensity = move_toward(_intensity, _target_intensity, delta * INTENSITY_LERP_SPEED)

func _refresh_enemy_density() -> void:
	var live: int = 0
	var tree: SceneTree = get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group("Enemy"):
			if node is CollisionObject2D and (node as CollisionObject2D).is_physics_processing():
				live += 1
	_cached_enemy_density = clampf(live / 24.0, 0.0, 1.0)

# Blends wave number progress, active-wave time progress, and live enemy density (0..1).
# Percussion layer rides this so late/dense waves feel heavier.
func _compute_combat_intensity() -> float:
	# Wave ladder: wave 1 ~0.15, wave 20+ saturates.
	var wave_factor: float = clampf(_current_wave / 20.0, 0.0, 1.0)

	var time_factor: float = 0.5
	var waves: Node = WaveManager
	if waves != null and WaveManager.is_wave_active:
		# Prefer remaining-time progress; fall back if duration unknown.
		var remaining: float = WaveManager.wave_time_remaining
		# Approximate total duration from remaining growth: use 45s mid as soft ref.
		var approx_total: float = clampf(20.0 + 3.0 * (_current_wave - 1), 20.0, 90.0)
		var elapsed_frac: float = 1.0 - clampf(remaining / approx_total, 0.0, 1.0)
		time_factor = elapsed_frac

	# Soft cap ~24 live enemies = full density layer. Refreshed on a timer
	# so the music bed does not walk the whole Enemy group every frame.
	var density: float = _cached_enemy_density

	return clampf(0.25 * wave_factor + 0.35 * time_factor + 0.40 * density, 0.0, 1.0)

static func _set_player_linear(player: AudioStreamPlayer, linear01: float) -> void:
	if player == null:
		return

	linear01 = clampf(linear01, 0.0, 1.0)
	player.volume_db = -80.0 if linear01 <= 0.0001 else linear_to_db(linear01)

static func _stop_if_silent(player: AudioStreamPlayer, linear01: float) -> void:
	if player != null and linear01 <= 0.0001 and player.playing:
		player.stop()

static func _smooth01(t: float) -> float:
	# Smoothstep ease for crossfades.
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
