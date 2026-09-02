extends Node

# The night's answer to a Hunter who has outrun it.
#
# Past Difficulty.overspeed_threshold — a move-speed multiplier of 1.25, so a
# quarter faster than the Hunter started — this begins planting dark mages as
# far across the arena as there is room for. They do not move and they do not
# chase; they stand there and drag on him until somebody walks over and stops
# them, which is the one thing being fast was supposed to make easy.
#
# It is an autoload of its own rather than a branch inside WaveManager for one
# reason: WaveManager stops spawning for the length of a boss fight, and this
# has to keep going through it. Speed is exactly as much of a problem during a
# boss as outside one.
#
# The threshold is read off PlayerStats.move_speed_multiplier, which holds only
# what the Hunter has bought. The slow goes on external_speed_multiplier
# instead, so the two never see each other — see the note on that field.

const MAGE_SCENE := "res://Scenes/Enemies/DarkMage.tscn"

# What one channelling mage does to him. They compound, so the second takes the
# same quarter off what the first left.
const SLOW_PER_MAGE := 0.78
# However many arrive, he never drops below this much of his own speed. Being
# punished for speed should not become being unable to move.
const SLOW_FLOOR := 0.45

# First one arrives promptly enough to be read as a consequence; the rest space
# themselves out so the arena does not fill with them.
const FIRST_DELAY := 4.0
const SPAWN_INTERVAL := 11.0
const MAX_ALIVE := 3

# Health, before the wave and the difficulty have their say. Deliberately soft:
# the difficulty is in reaching one, not in killing it once you have.
const BASE_HEALTH := 34

# Candidate points sampled when placing one. The farthest from the Hunter wins,
# so "as far away as possible" is answered by the arena's actual shape rather
# than by a fixed distance that a corner would break.
const PLACEMENT_SAMPLES := 32
const MIN_PLACEMENT_DISTANCE := 520.0

var _mages: Array[DarkMage] = []
var _spawn_timer: float = FIRST_DELAY
var _scene: PackedScene
var _was_over: bool = false

func _ready() -> void:
	_scene = load(MAGE_SCENE)
	if EventBus != null:
		EventBus.run_started.connect(_on_run_started)
		EventBus.player_died.connect(_on_player_died)

func _exit_tree() -> void:
	if EventBus != null:
		EventBus.run_started.disconnect(_on_run_started)
		EventBus.player_died.disconnect(_on_player_died)

func _on_run_started() -> void:
	clear()

func _on_player_died() -> void:
	clear()

# Sends every mage away and lifts the slow. Used between runs, and when the
# Hunter is no longer fast enough to have earned one.
func clear() -> void:
	for mage in _mages:
		if is_instance_valid(mage):
			mage.dismiss()

	_mages.clear()
	_spawn_timer = FIRST_DELAY
	_was_over = false
	_apply_slow(1.0)

func _process(delta: float) -> void:
	_prune()

	var threshold := Difficulty.overspeed_threshold(GameManager.difficulty)
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	var stats: PlayerStats = player.get_node_or_null("PlayerStats") if player != null else null

	if threshold <= 0.0 or stats == null:
		if _was_over:
			clear()

		return

	var over := stats.move_speed_multiplier > threshold
	if over != _was_over:
		_was_over = over
		if over:
			print("[DarkMages] Hunter at %.0f%% speed — the night starts sending wardens."
				% (stats.move_speed_multiplier * 100.0))
		else:
			# He slowed down on his own account. Call them off rather than
			# leaving a punishment running for something no longer true.
			clear()
			return

	if not over:
		_apply_slow(1.0)
		return

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		if _mages.size() < MAX_ALIVE:
			_spawn(player)

	_apply_slow(combined_slow())

# What the player's speed is multiplied by right now. One place, because how
# several wardens stack is the whole balance of the mechanic.
func combined_slow() -> float:
	var channelling := 0
	for mage in _mages:
		if is_instance_valid(mage) and mage.get_is_channelling():
			channelling += 1

	if channelling <= 0:
		return 1.0

	return maxf(SLOW_FLOOR, pow(SLOW_PER_MAGE, channelling))

func get_channelling_count() -> int:
	var count := 0
	for mage in _mages:
		if is_instance_valid(mage) and mage.get_is_channelling():
			count += 1

	return count

func _apply_slow(value: float) -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	var stats: PlayerStats = player.get_node_or_null("PlayerStats")
	if stats != null:
		stats.external_speed_multiplier = value

func _prune() -> void:
	var alive: Array[DarkMage] = []
	for mage in _mages:
		if is_instance_valid(mage):
			alive.append(mage)

	_mages = alive

func _spawn(player: Node2D) -> void:
	if _scene == null:
		return

	var mage: DarkMage = _scene.instantiate()
	_resolve_parent().add_child(mage)
	mage.global_position = _far_placement(player.global_position)

	var wave: int = WaveManager.current_wave if WaveManager != null else 1
	var health := roundi(BASE_HEALTH
		* EnemyScaling.health_multiplier(maxi(1, wave))
		* Difficulty.enemy_health_multiplier(GameManager.difficulty))
	mage.configure(health)
	_mages.append(mage)

# The farthest of a handful of sampled points inside the arena. Sampling rather
# than picking the opposite corner outright, because the opposite corner is the
# same spot every time and the Hunter would learn to stand in the middle.
func _far_placement(from: Vector2) -> Vector2:
	var half_w := WaveManager.arena_half_width if WaveManager != null else 760.0
	var half_h := WaveManager.arena_half_height if WaveManager != null else 460.0
	# Kept off the wall so it is reachable and its shadow pool is fully drawn.
	var margin := 60.0
	half_w = maxf(margin + 1.0, half_w - margin)
	half_h = maxf(margin + 1.0, half_h - margin)

	var best := Vector2(half_w, half_h)
	var best_dist := -1.0
	for i in range(PLACEMENT_SAMPLES):
		var candidate := Vector2(randf_range(-half_w, half_w), randf_range(-half_h, half_h))
		var dist := candidate.distance_squared_to(from)
		if dist > best_dist:
			best_dist = dist
			best = candidate

	# An arena smaller than the ideal gap still has to put it somewhere; taking
	# the farthest sample is the best that geometry allows.
	if best_dist < MIN_PLACEMENT_DISTANCE * MIN_PLACEMENT_DISTANCE:
		push_warning("[DarkMages] Arena too small to place a warden %.0fpx away; used %.0fpx."
			% [MIN_PLACEMENT_DISTANCE, sqrt(maxf(0.0, best_dist))])

	return best

func _resolve_parent() -> Node:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene != null and is_instance_valid(scene):
		var world: Node = scene.get_node_or_null("World")
		return world if world != null else scene

	return self
