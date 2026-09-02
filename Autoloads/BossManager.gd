extends Node

# Spawns bosses when the matching wave starts. Self-subscribes to EventBus.wave_start —
# does NOT edit WaveManager trigger logic. Pauses normal wave spawns via WaveManager.spawns_paused
# for the duration of the encounter.
#
# Two ways a boss gets chosen, depending on the difficulty. On the authored
# schedule each boss owns a wave number and always turns up on it. On a
# difficulty with boss_every_waves set, every boss wave instead deals from a
# shuffled deck of the whole roster — see _pick_boss_for_wave.

# True while a boss fight is live. Parallel systems may read this.
var is_boss_active: bool

# Roster of bosses. If empty at _ready, loads the three default .tres definitions.
@export var boss_roster: Array[BossData]

@export var spawn_offset_from_player: float = 280.0

var _active_boss: Boss
var _active_data: BossData
var _triggered_waves: Array[int] = []

# Shuffled draw pile, used only by difficulties that spawn bosses on a cadence.
# Emptied and reshuffled as it runs out, so a long run keeps getting fights
# while never repeating one before the rest of the roster has had its turn.
var _boss_deck: Array[BossData] = []
var _last_drawn: BossData

func _ready() -> void:
	if boss_roster == null or boss_roster.is_empty():
		# One entry per trigger wave; BossManager takes the first match, so two
		# bosses must never share a wave_trigger. BatWingedCount.tres,
		# GravekeeperColossus.tres and HollowCardinal.tres are kept on disk but
		# left off the roster: BloodMoonAlpha, BelfryTyrant and CrimsonVoivode
		# took waves 10, 15 and 20 from them, and TollingGhoul holds 25. Putting
		# one back needs a wave_trigger of its own first. The admin panel
		# (F1 -> Bosses) lists every file on disk, roster or not.
		boss_roster = [
			load("res://Resources/BossData/Data/BloodMoonAlpha.tres"),
			load("res://Resources/BossData/Data/BelfryTyrant.tres"),
			load("res://Resources/BossData/Data/CrimsonVoivode.tres"),
			load("res://Resources/BossData/Data/TollingGhoul.tres")
		]

	if EventBus != null:
		EventBus.run_started.connect(_on_run_started)
		EventBus.wave_start.connect(_on_wave_start)
		EventBus.boss_encounter_end.connect(_on_boss_encounter_end)
		EventBus.player_died.connect(_on_player_died)

func _exit_tree() -> void:
	if EventBus != null:
		EventBus.run_started.disconnect(_on_run_started)
		EventBus.wave_start.disconnect(_on_wave_start)
		EventBus.boss_encounter_end.disconnect(_on_boss_encounter_end)
		EventBus.player_died.disconnect(_on_player_died)

# BossManager is an autoload, so _triggered_waves outlived the run that filled
# it: every wave that had ever spawned a boss stayed marked for the rest of the
# session, and the second run got no bosses at all. Only noticeable on waves
# 10/15/20 before — obvious the moment a difficulty puts one on every third.
func _on_run_started() -> void:
	_triggered_waves.clear()
	# The deck is per-run for the same reason: "not the same boss twice" is a
	# promise about one run, and a pile left half-dealt would carry the last
	# run's exclusions into the next one.
	_boss_deck.clear()
	_last_drawn = null
	_end_encounter(false)

func _on_wave_start(wave_number: int) -> void:
	if is_boss_active:
		return

	# One trigger per wave number per run.
	if _triggered_waves.has(wave_number):
		return

	if not _is_boss_wave(wave_number):
		return

	var match: BossData = _pick_boss_for_wave(wave_number)
	if match == null:
		return

	_triggered_waves.append(wave_number)
	spawn_boss(match, wave_number)

# Whether a boss belongs on this wave at all. Deliberately free of side effects,
# so the caller can ask before committing to a draw.
func _is_boss_wave(wave_number: int) -> bool:
	if boss_roster == null or wave_number <= 0:
		return false

	var interval: int = Difficulty.boss_every_waves(GameManager.difficulty)
	if interval > 0 and wave_number % interval == 0:
		return true

	for data: BossData in boss_roster:
		if data != null and data.wave_trigger == wave_number:
			return true

	return false

# Which boss shows up. On the authored schedule that is whoever owns the wave.
# On a difficulty that promises "a boss every N waves" it is a draw from the
# deck instead — including on the authored waves, which is the part that makes
# the no-repeat rule mean anything: leaving wave 10 hard-wired to the Blood Moon
# Alpha would hand it to you a second time whenever the deck had already dealt
# it, which is exactly what the deck exists to prevent.
func _pick_boss_for_wave(wave_number: int) -> BossData:
	if boss_roster == null:
		return null

	if Difficulty.boss_every_waves(GameManager.difficulty) > 0:
		return _draw_boss()

	for data: BossData in boss_roster:
		if data != null and data.wave_trigger == wave_number:
			return data

	return null

# Draws the next boss off the pile, refilling it when it runs dry. A deck rather
# than a plain random pick: rolling each boss wave independently would happily
# serve the same fight three times before touching the rest of the roster, and a
# fixed cycle (what this used to do) means the second run is the first one over
# again. Dealing a shuffled deck is the only one of the three that is both a
# surprise and fair.
func _draw_boss() -> BossData:
	if _boss_deck.is_empty():
		_refill_boss_deck()

	if _boss_deck.is_empty():
		return null

	_last_drawn = _boss_deck.pop_back()
	return _last_drawn

func _refill_boss_deck() -> void:
	_boss_deck.clear()
	for data: BossData in boss_roster:
		if data != null:
			_boss_deck.append(data)

	_boss_deck.shuffle()

	# The seam between two decks is the one place a repeat can still slip
	# through: the last card of the old pile and the first of the new one are
	# shuffled independently of each other. If the new pile opens with the boss
	# that just fell, trade it with someone further down.
	if _boss_deck.size() > 1 and _boss_deck.back() == _last_drawn:
		var top := _boss_deck.size() - 1
		var other := randi() % top
		var swap := _boss_deck[other]
		_boss_deck[other] = _boss_deck[top]
		_boss_deck[top] = swap

# `wave_number` is the wave this actually happened on, which is no longer the
# same thing as the boss's own wave_trigger now that a deck difficulty can deal
# any boss to any boss wave. Defaults back to the trigger for callers that have
# no wave in hand — the admin panel's force-spawn.
func spawn_boss(data: BossData, wave_number: int = -1) -> void:
	if data == null:
		return

	if wave_number < 0:
		wave_number = data.wave_trigger

	if data.boss_scene == null:
		push_error("[BossManager] BossData '%s' has no BossScene." % data.boss_name)
		return

	var player: Node2D = get_tree().get_first_node_in_group("Player") as Node2D
	var origin: Vector2 = player.global_position if player != null else Vector2.ZERO
	var spawn_pos: Vector2 = origin + Vector2(spawn_offset_from_player, 0.0).rotated(randf_range(0.0, TAU))

	var instance: Node = data.boss_scene.instantiate()
	# Same y-sort root as Player/enemies so bosses depth-sort by feet.
	var parent: Node = _resolve_entity_parent()
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

	EventBus.boss_encounter_start.emit(data.boss_name, wave_number)
	print("[BossManager] Spawned %s on wave %d." % [data.boss_name, wave_number])

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

# Debug / tests: force whoever the given wave would produce. On a deck
# difficulty this really does draw a card, so what you preview is what that
# wave would actually have given you.
func debug_spawn_boss_for_wave(wave_number: int) -> void:
	if not _is_boss_wave(wave_number):
		return

	var data: BossData = _pick_boss_for_wave(wave_number)
	if data != null:
		spawn_boss(data, wave_number)

# Admin panel: start any encounter on demand, even one already fought this run
# or one whose boss is still on the field. Clears the live fight first so two
# bosses can never share the arena.
func debug_force_spawn(data: BossData) -> void:
	if data == null:
		return

	# Deliberately does not mark the wave as triggered: previewing an encounter
	# from the admin panel should not delete it from the run.
	debug_end_encounter()
	spawn_boss(data)

# Removes the live boss without paying out its rewards.
func debug_end_encounter() -> void:
	if _active_boss != null and is_instance_valid(_active_boss):
		_active_boss.queue_free()

	_end_encounter(false)

func get_active_boss_name() -> String:
	return _active_data.boss_name if _active_data != null else ""

# The boss currently on the field, or null. The health bar needs the node, not
# just the name from boss_encounter_start, and reaching into the group would
# also pick up a corpse that has not finished its death animation.
func get_active_boss() -> Boss:
	return _active_boss if _active_boss != null and is_instance_valid(_active_boss) else null

func get_active_data() -> BossData:
	return _active_data

func _resolve_entity_parent() -> Node:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene != null and is_instance_valid(scene):
		var world: Node = scene.get_node_or_null("World")
		if world != null:
			return world
		return scene
	return self
