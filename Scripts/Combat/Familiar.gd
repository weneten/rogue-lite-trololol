extends Node2D
class_name Familiar

# Independent auto-attacking pet spawned by WeaponClass.Summon weapons (Grimoire of Bones'
# skeleton, Spectral Hound Whistle's hound). Unlike Weapon — a slot rigidly mounted on the
# owner — a Familiar is a free-roaming Node2D that hovers near its owner and fires its own
# pooled projectiles at the nearest enemy on its own cooldown; the Weapon node that spawned it
# does nothing further once Setup() is called.

@export var target_group: String = "Enemy"
@export var follow_speed: float = 220.0
# Offset from the owner this familiar tries to hover at, so multiple familiars/weapon
# copies don't all stack exactly on top of the owner.
@export var follow_offset: Vector2 = Vector2(-40, -20)
@export var projectile_spawn_point_path: NodePath
@export var projectile_pool_prewarm: int = 4

var _data: WeaponData
var _owner: Node2D
var _owner_stats: PlayerStats
var _spawn_point: Node2D
var _projectile_pool: ObjectPool

var _cooldown_remaining: float = 0.0
# Reports damage back to the Weapon slot that summoned this familiar, so the
# HUD's per-weapon scoreboard credits the summon rather than showing a zero.
var _report_damage: Callable = Callable()

func _ready() -> void:
	_spawn_point = get_node_or_null(projectile_spawn_point_path) as Node2D if projectile_spawn_point_path else self

# Wires this familiar to fight on behalf of owner using data's stats. Called once by
# Weapon.spawn_familiar right after instantiation.
func setup(owner: Node2D, data: WeaponData, owner_stats: PlayerStats, report_damage: Callable = Callable()) -> void:
	_owner = owner
	_data = data
	_owner_stats = owner_stats
	_report_damage = report_damage

	if data.projectile_scene != null:
		_projectile_pool = ObjectPool.new(data.projectile_scene, get_tree().current_scene if get_tree().current_scene else get_parent(), projectile_pool_prewarm)

func _process(delta: float) -> void:
	if _owner == null or _data == null:
		return

	var owner_health := _owner.get_node_or_null("HealthComponent") as HealthComponent
	if owner_health != null and owner_health.is_dead:
		return

	var desired_position = _owner.global_position + follow_offset
	global_position = global_position.move_toward(desired_position, follow_speed * delta)

	_cooldown_remaining -= delta

	var target = _find_nearest_target()
	if target == null:
		return

	global_rotation = (target.global_position - global_position).angle()

	if _cooldown_remaining > 0:
		return

	_fire_at(target)
	_cooldown_remaining = 1.0 / maxf(0.01, _data.attack_speed * (_owner_stats.attack_speed_multiplier if _owner_stats else 1.0))

# Nearest live TargetGroup member within Data.Range of the familiar itself (not the owner).
func _find_nearest_target() -> Node2D:
	var nearest = null
	var nearest_dist_sq = _data.range * _data.range

	for node in get_tree().get_nodes_in_group(target_group):
		if not node is Node2D:
			continue

		var candidate = node as Node2D
		var health = candidate.get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.is_dead:
			continue

		var dist_sq = global_position.distance_squared_to(candidate.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = candidate

	return nearest

func _fire_at(target: Node2D) -> void:
	if _projectile_pool == null:
		return

	var direction = (target.global_position - _spawn_point.global_position).normalized()
	var crit_chance = _data.crit_chance + (_owner_stats.extra_crit_chance if _owner_stats else 0.0)
	var crit_multiplier = _data.crit_multiplier + (_owner_stats.extra_crit_multiplier if _owner_stats else 0.0)

	var damage_multiplier = _owner_stats.damage_multiplier if _owner_stats else 1.0
	if target is Enemy:
		var enemy = target as Enemy
		if enemy.data != null and enemy.data.is_undead:
			damage_multiplier *= _owner_stats.undead_damage_multiplier if _owner_stats else 1.0

	var projectile = _projectile_pool.acquire()
	projectile.launch(
		_spawn_point.global_position,
		direction,
		_projectile_pool,
		_owner,
		_data.damage * damage_multiplier,
		crit_chance,
		crit_multiplier,
		_data.knockback,
		target_group,
		func(dealt: int, hit_body: Node2D):
			if _report_damage.is_valid():
				_report_damage.call(dealt)
			if _owner_stats:
				_owner_stats.notify_damage_dealt(dealt, hit_body)
	)
