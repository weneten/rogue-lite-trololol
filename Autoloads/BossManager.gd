extends Node

# Spawns bosses when the matching wave starts. Self-subscribes to EventBus.wave_start —
# does NOT edit WaveManager trigger logic. Pauses normal wave spawns via WaveManager.spawns_paused
# for the duration of the encounter.

# True while a boss fight is live. Parallel systems may read this.
var is_boss_active: bool

# Roster of bosses. If empty at _ready, loads the three default .tres definitions.
@export var boss_roster: Array[BossData]

@export var spawn_offset_from_player: float = 280.0

var _active_boss: Boss
var _active_data: BossData
var _triggered_waves: Array[int] = []

func _ready() -> void:
	if boss_roster == null or boss_roster.is_empty():
		boss_roster = [
			load("res://Resources/BossData/Data/BatWingedCount.tres"),
			load("res://Resources/BossData/Data/GravekeeperColossus.tres"),
			load("res://Resources/BossData/Data/HollowCardinal.tres")
		]

	if EventBus != null:
		EventBus.wave_start.connect(_on_wave_start)
		EventBus.boss_encounter_end.connect(_on_boss_encounter_end)
		EventBus.player_died.connect(_on_player_died)

func _exit_tree() -> void:
	if EventBus != null:
		EventBus.wave_start.disconnect(_on_wave_start)
		EventBus.boss_encounter_end.disconnect(_on_boss_encounter_end)
		EventBus.player_died.disconnect(_on_player_died)

func _on_wave_start(wave_number: int) -> void:
	if is_boss_active:
		return

	# One trigger per wave number per run.
	if _triggered_waves.has(wave_number):
		return

	var match: BossData = _find_boss_for_wave(wave_number)
	if match == null:
		return

	_triggered_waves.append(wave_number)
	spawn_boss(match)

func _find_boss_for_wave(wave_number: int) -> BossData:
	if boss_roster == null:
		return null

	for data: BossData in boss_roster:
		if data != null and data.wave_trigger == wave_number:
			return data

	return null

func spawn_boss(data: BossData) -> void:
	if data == null:
		return

	if data.boss_scene == null:
		push_error("[BossManager] BossData '%s' has no BossScene." % data.boss_name)
		return

	var player: Node2D = get_tree().get_first_node_in_group("Player") as Node2D
	var origin: Vector2 = player.global_position if player != null else Vector2.ZERO
	var spawn_pos: Vector2 = origin + Vector2(spawn_offset_from_player, 0.0).rotated(randf_range(0.0, TAU))

	var instance: Node = data.boss_scene.instantiate()
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else self
	parent.add_child(instance)

	if not instance is Boss:
		push_error("[BossManager] BossScene root is not a Boss: %s" % data.boss_scene.resource_path)
		instance.queue_free()
		return

	var boss: Boss = instance as Boss
	boss.global_position = spawn_pos
	boss.initialize(data)

	_active_boss = boss
	_active_data = data
	is_boss_active = true

	if WaveManager != null:
		WaveManager.spawns_paused = true

	EventBus.boss_encounter_start.emit(data.boss_name, data.wave_trigger)
	print("[BossManager] Spawned %s on wave %d." % [data.boss_name, data.wave_trigger])

func _on_boss_encounter_end(boss_name: String, defeated: bool) -> void:
	_end_encounter(defeated)

func _on_player_died() -> void:
	if !is_boss_active:
		return

	var name: String = _active_data.boss_name if _active_data != null else "Boss"
	if _active_boss != null and is_instance_valid(_active_boss):
		_active_boss.queue_free()

	# Emit so listeners (audio/UI) can react; _end_encounter also runs via the handler.
	EventBus.boss_encounter_end.emit(name, false)

func _end_encounter(defeated: bool) -> void:
	if !is_boss_active and _active_boss == null:
		return

	is_boss_active = false
	_active_boss = null
	_active_data = null

	if WaveManager != null:
		WaveManager.spawns_paused = false

	if defeated:
		print("[BossManager] Boss defeated — wave spawns resumed.")
	else:
		print("[BossManager] Boss encounter ended (not defeated) — wave spawns resumed.")

# Debug / tests: force a roster entry by wave trigger.
func debug_spawn_boss_for_wave(wave_number: int) -> void:
	var data: BossData = _find_boss_for_wave(wave_number)
	if data != null:
		spawn_boss(data)
