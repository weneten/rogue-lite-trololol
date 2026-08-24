extends Node

# Timed enemy-wave loop for Arena gameplay only. Autoload, but idle while no Player exists
# (MainMenu/CharacterSelect) so the pool is never parented to the wrong scene.
# Spawns on a ring around the player, clamped into arena bounds.

@export var current_wave: int = 0
@export var time_between_waves: float = 5.0
@export var is_wave_active: bool = false

# When true, process_active_wave skips enemy spawns (wave timer still runs).
# BossManager sets this for the duration of a boss encounter.
var spawns_paused: bool

@export var enemy_scene: PackedScene
@export var wave_definition: WaveData
@export var enemy_pool_prewarm: int = 10
@export var initial_delay_seconds: float = 2.0

# Min distance from player for a spawn (on-screen but not on top of them).
@export var spawn_radius_min: float = 260.0
# Max distance from player for a spawn (inside camera / arena, not beyond walls).
@export var spawn_radius_max: float = 400.0

# Half-width of playable area (matches Arena walls ~±800 with margin).
@export var arena_half_width: float = 760.0
# Half-height of playable area (matches Arena walls ~±500 with margin).
@export var arena_half_height: float = 460.0

var _enemy_pool: ObjectPool
var _pool_parent: Node

var _wave_time_remaining: float
var _spawn_time_remaining: float
var _inter_wave_time_remaining: float
var _enemies_to_spawn_this_wave: int
var _enemies_spawned_this_wave: int
var _gameplay_active: bool

var wave_time_remaining: float:
	get: return _wave_time_remaining

var time_until_next_wave: float:
	get: return _inter_wave_time_remaining

func _ready() -> void:
	if enemy_scene == null:
		enemy_scene = load("res://Scenes/Enemies/Enemy.tscn")
	if wave_definition == null:
		wave_definition = load("res://Resources/WaveData/Data/StandardWave.tres")
	_inter_wave_time_remaining = initial_delay_seconds

func _process(delta: float) -> void:
	if wave_definition == null or enemy_scene == null:
		return

	# Only run the wave loop while a Player is in the tree (Arena). Prevents spawning into
	# MainMenu/CharacterSelect and avoids pool instances parented under a freed scene.
	var player: Node2D = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null or !is_instance_valid(player):
		if _gameplay_active:
			_stop_gameplay()
		return

	if !_gameplay_active:
		_begin_gameplay()

	if !_ensure_enemy_pool():
		return

	if is_wave_active:
		_process_active_wave(delta)
	elif _inter_wave_time_remaining > 0:
		_inter_wave_time_remaining -= delta
		if _inter_wave_time_remaining <= 0:
			start_next_wave()

func _begin_gameplay() -> void:
	_gameplay_active = true
	current_wave = 0
	is_wave_active = false
	spawns_paused = false
	_enemies_spawned_this_wave = 0
	_enemies_to_spawn_this_wave = 0
	_wave_time_remaining = 0
	_inter_wave_time_remaining = initial_delay_seconds
	_enemy_pool = null
	_pool_parent = null
	print("[WaveManager] Gameplay started — wave loop armed.")

func _stop_gameplay() -> void:
	_gameplay_active = false
	is_wave_active = false
	spawns_paused = false
	_enemy_pool = null
	_pool_parent = null
	print("[WaveManager] Left gameplay — wave loop idle.")

func _ensure_enemy_pool() -> bool:
	# Parent under the same y-sort root as the Player so feet-depth sorts
	# correctly. Parenting to the Arena root put enemies in a different sorting
	# branch entirely, and Y-sort only orders siblings — so no depth comparison
	# between an enemy and the Player ever happened.
	var parent: Node = _resolve_entity_parent()
	if parent == null or !is_instance_valid(parent):
		return false

	if _enemy_pool != null and _pool_parent == parent and is_instance_valid(_pool_parent):
		return true

	_pool_parent = parent
	_enemy_pool = ObjectPool.new(enemy_scene, parent, enemy_pool_prewarm)
	return true

# The Player's own parent is the authority — that is the node enemies have to
# be siblings of. The "World" lookup is the fallback for spawning before a
# Player exists, and the scene root the last resort.
func _resolve_entity_parent() -> Node:
	var scene: Node = get_tree().current_scene
	if scene == null or !is_instance_valid(scene):
		return null

	var player: Node = get_tree().get_first_node_in_group("Player")
	if player != null and is_instance_valid(player):
		var host: Node = player.get_parent()
		if host != null and is_instance_valid(host):
			return host

	var world: Node = scene.get_node_or_null("World")
	return world if world != null else scene

func _process_active_wave(delta: float) -> void:
	_wave_time_remaining -= delta

	# Keep spawning for the whole wave timer (Brotato-style). No "quota then idle" gap.
	if !spawns_paused and _wave_time_remaining > 0:
		_spawn_time_remaining -= delta
		if _spawn_time_remaining <= 0:
			var alive: int = _count_alive_enemies()
			var max_alive: int = _get_max_alive_for_wave(current_wave)
			if alive < max_alive:
				# Catch up a bit if the field is empty so the player never stands around.
				var batch: int = 3 if alive <= 1 else 1
				batch = mini(batch, max_alive - alive)
				for i in range(batch):
					_spawn_random_enemy()
					_enemies_spawned_this_wave += 1

			_spawn_time_remaining = _get_spawn_interval_for_wave(current_wave)

	if _wave_time_remaining <= 0:
		end_wave()
		_inter_wave_time_remaining = time_between_waves

func start_next_wave() -> void:
	current_wave += 1
	is_wave_active = true

	_wave_time_remaining = clampf(
		wave_definition.base_duration + wave_definition.duration_growth_per_wave * (current_wave - 1),
		20.0, 90.0)
	# Cap is concurrent alive, not a fixed total — spawns continue until the timer ends.
	_enemies_to_spawn_this_wave = _get_max_alive_for_wave(current_wave)
	_enemies_spawned_this_wave = 0
	_spawn_time_remaining = 0

	EventBus.wave_start.emit(current_wave)
	print("[WaveManager] Wave %d start — continuous spawn for %.0fs (interval %.2fs, max alive %d)." % [
		current_wave, _wave_time_remaining, _get_spawn_interval_for_wave(current_wave), _enemies_to_spawn_this_wave])

# How many enemies may be alive at once this wave (prevents infinite pile-up).
func _get_max_alive_for_wave(wave: int) -> int:
	if wave_definition == null:
		return 12

	var growth: float = wave_definition.enemy_count_growth_per_wave * maxi(0, wave - 1)
	# BaseEnemyCount now means "starting concurrent pressure", not total quota.
	var cap: int = roundi((wave_definition.base_enemy_count + 3.0 + growth * 2.0) * _density_multiplier())
	var hard_cap: int = 22 if OS.has_feature("web") else 45
	return clampi(cap, 6, hard_cap)

func _get_spawn_interval_for_wave(wave: int) -> float:
	if wave_definition == null:
		return 1.0

	# Slightly faster each wave; floor so it never becomes a spawn-storm.
	var interval: float = wave_definition.spawn_interval - 0.06 * maxi(0, wave - 1)
	# Density relics shorten the gap as well as raising the ceiling: a higher cap
	# alone just fills more slowly and never actually feels denser.
	return clampf(interval / maxf(0.5, _density_multiplier()), 0.25, 3.0)

# Risk/reward relics (see PlayerStats.enemy_density_multiplier). Reads 1.0 when
# no player is in the tree, so menus and standalone scenes are unaffected.
func _density_multiplier() -> float:
	return PlayerStats.instance.enemy_density_multiplier if PlayerStats.instance != null else 1.0

func _count_alive_enemies() -> int:
	var tree: SceneTree = get_tree()
	if tree == null:
		return 0

	var count: int = 0
	for node in tree.get_nodes_in_group("Enemy"):
		# Count anything still simulating — OffscreenCuller hides far enemies
		# with visible=false, and treating those as dead made the spawner
		# keep filling the map behind the camera until a hitch.
		if node is Enemy and is_instance_valid(node) and node.is_inside_tree() \
				and (node as Enemy).is_physics_processing():
			count += 1

	return count

func end_wave() -> void:
	is_wave_active = false
	EventBus.wave_end.emit(current_wave)

func _spawn_random_enemy() -> void:
	var data: EnemyData = _select_weighted_enemy(wave_definition.enemy_pool, current_wave)
	if data == null:
		push_warning("[WaveManager] No enemy in pool for wave %d." % current_wave)
		return

	var player: Node2D = get_tree().get_first_node_in_group("Player") as Node2D
	var origin: Vector2 = player.global_position if player != null else Vector2.ZERO
	var spawn_pos: Vector2 = _pick_spawn_position(origin)

	var enemy: Enemy = _enemy_pool.acquire()
	enemy.global_position = spawn_pos
	enemy.initialize(data, _enemy_pool)
	enemy.apply_spawn_modifiers(current_wave, EnemyScaling.roll_elite(current_wave))

# Random point on a ring around the player, clamped into the arena so enemies never spawn
# outside walls (where they get stuck and never reach the player).
func _pick_spawn_position(player_pos: Vector2) -> Vector2:
	var min_r: float = minf(spawn_radius_min, spawn_radius_max)
	var max_r: float = maxf(spawn_radius_min, spawn_radius_max)

	for attempt in range(16):
		var angle: float = randf_range(0.0, TAU)
		var dist: float = randf_range(min_r, max_r)
		var candidate: Vector2 = player_pos + Vector2(dist, 0.0).rotated(angle)
		candidate = _clamp_to_arena(candidate)

		# Accept if still a bit away from the player after clamping.
		if candidate.distance_squared_to(player_pos) >= 120.0 * 120.0:
			return candidate

	# Fallback: any clamped offset.
	var fallback_angle: float = randf_range(0.0, TAU)
	return _clamp_to_arena(player_pos + Vector2(220.0, 0.0).rotated(fallback_angle))

func _clamp_to_arena(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, -arena_half_width, arena_half_width),
		clampf(pos.y, -arena_half_height, arena_half_height))

static func _select_weighted_enemy(pool: Array, wave_number: int) -> EnemyData:
	if pool == null or pool.is_empty():
		return null

	var total_weight: float = 0.0
	for candidate: EnemyData in pool:
		if candidate != null and candidate.min_wave_to_appear <= wave_number:
			total_weight += maxf(0.0, candidate.spawn_weight)

	if total_weight <= 0.0:
		return null

	var roll: float = randf() * total_weight
	for candidate: EnemyData in pool:
		if candidate == null or candidate.min_wave_to_appear > wave_number:
			continue

		roll -= maxf(0.0, candidate.spawn_weight)
		if roll <= 0.0:
			return candidate

	# Last eligible entry (pool[-1] may be locked by MinWave).
	for i in range(pool.size() - 1, -1, -1):
		if pool[i] != null and pool[i].min_wave_to_appear <= wave_number:
			return pool[i]

	return null
