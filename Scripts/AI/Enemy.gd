extends CharacterBody2D
class_name Enemy

enum EnemyState {
	WANDER,
	CHASE,
	ATTACK,
	FLEE
}

const WORLD_COLLISION_MASK = 1

@export var data: EnemyData
@export var health_component_path: NodePath
@export var sprite_node_path: NodePath
@export var sprite_animator_path: NodePath
@export var collision_shape_path: NodePath
@export var contact_hitbox_path: NodePath
@export var projectile_spawn_point_path: NodePath

@export var wander_speed_scale: float = 0.4
@export var wander_radius: float = 150.0
@export var wander_repick_seconds: float = 3.0

var _health: HealthComponent
var _animated_sprite: AnimatedSprite2D
var _fallback_polygon: Polygon2D
var _procedural_sprite: Sprite2D
var _sprite_animator: EnemySpriteAnimator
var _collision_shape: CollisionShape2D
var _contact_hitbox: Area2D
var _projectile_spawn_point: Node2D
var _pool: ObjectPool
var _projectile_pool: ObjectPool

var _state: EnemyState = EnemyState.WANDER
var _spawn_origin: Vector2
var _wander_target: Vector2
var _wander_repick_remaining: float = 0.0
var _attack_cooldown_remaining: float = 0.0
var _death_sequence_running: bool = false

var _speed_multiplier: float = 1.0
var _speed_modifier_remaining: float = 0.0

var _runtime_move_speed: float
var _runtime_attack_damage: float
var _runtime_explosion_damage: float
var _is_elite: bool = false

var _erratic_strafe_sign: float = 1.0
var _erratic_repick_remaining: float = 0.0

func _ready() -> void:
	add_to_group("Enemy")

	_health = get_node_or_null(health_component_path) as HealthComponent
	_animated_sprite = get_node_or_null(sprite_node_path) as AnimatedSprite2D
	_fallback_polygon = get_node_or_null("FallbackPolygon") as Polygon2D
	_sprite_animator = get_node_or_null(sprite_animator_path) as EnemySpriteAnimator
	if _sprite_animator == null:
		_sprite_animator = get_node_or_null("SpriteAnimator") as EnemySpriteAnimator
	_collision_shape = get_node_or_null(collision_shape_path) as CollisionShape2D
	_contact_hitbox = get_node_or_null(contact_hitbox_path) as Area2D
	_projectile_spawn_point = get_node_or_null(projectile_spawn_point_path) as Node2D
	if _projectile_spawn_point == null:
		_projectile_spawn_point = self

	if _sprite_animator != null and _sprite_animator.sprite_path.is_empty() and sprite_node_path != null:
		_sprite_animator.sprite_path = sprite_node_path

	if _health != null:
		_health.died.connect(_on_died)
		_health.damaged.connect(_on_damaged)
	else:
		push_warning("[Enemy] HealthComponentPath not wired; enemy cannot die.")

func initialize(enemy_data: EnemyData, pool: ObjectPool) -> void:
	data = enemy_data
	_pool = pool
	_spawn_origin = global_position
	_is_elite = false
	_death_sequence_running = false

	_runtime_move_speed = enemy_data.move_speed
	_runtime_attack_damage = enemy_data.attack_damage
	_runtime_explosion_damage = enemy_data.explosion_damage

	if _health != null:
		_health.max_health = enemy_data.max_health
		_health.revive(enemy_data.max_health)

	_apply_visual_defaults(enemy_data)
	_apply_phasing(enemy_data.phases_through_obstacles)

	_state = EnemyState.WANDER
	_wander_target = _spawn_origin
	_wander_repick_remaining = 0.0
	_attack_cooldown_remaining = enemy_data.attack_cooldown
	_speed_multiplier = 1.0
	_speed_modifier_remaining = 0.0
	_erratic_strafe_sign = -1.0 if randf() < 0.5 else 1.0
	_erratic_repick_remaining = 0.0
	velocity = Vector2.ZERO
	scale = Vector2.ONE

func apply_spawn_modifiers(wave_number: int, is_elite: bool) -> void:
	if data == null:
		return

	var hp_mul = EnemyScaling.health_multiplier(wave_number)
	var dmg_mul = EnemyScaling.damage_multiplier(wave_number)
	var spd_mul = EnemyScaling.speed_multiplier(wave_number)

	_is_elite = is_elite
	if is_elite:
		hp_mul *= EnemyScaling.ELITE_HEALTH_MULTIPLIER
		dmg_mul *= EnemyScaling.ELITE_DAMAGE_MULTIPLIER
		spd_mul *= EnemyScaling.ELITE_SPEED_MULTIPLIER

	_runtime_move_speed = data.move_speed * spd_mul
	_runtime_attack_damage = data.attack_damage * dmg_mul
	_runtime_explosion_damage = data.explosion_damage * dmg_mul

	if _health != null:
		var max_hp = maxi(1, roundi(data.max_health * hp_mul))
		_health.max_health = max_hp
		_health.revive(max_hp)

	_apply_elite_visual(is_elite)

func apply_movement_modifier(multiplier: float, duration_seconds: float) -> void:
	multiplier = clampf(multiplier, 0.0, 1.0)
	if _speed_modifier_remaining <= 0 or multiplier <= _speed_multiplier:
		_speed_multiplier = multiplier
	_speed_modifier_remaining = maxf(_speed_modifier_remaining, duration_seconds)

func _physics_process(delta: float) -> void:
	if data == null or _health == null or _health.is_dead or _death_sequence_running:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var player = get_tree().get_first_node_in_group("Player") as Node2D
	var player_health: HealthComponent = null
	if player != null:
		player_health = player.get_node_or_null("HealthComponent") as HealthComponent
	var has_live_target = player != null and (player_health == null or not player_health.is_dead)

	if _speed_modifier_remaining > 0:
		_speed_modifier_remaining -= delta
		if _speed_modifier_remaining <= 0:
			_speed_modifier_remaining = 0.0
			_speed_multiplier = 1.0

	var distance_to_player = INF
	if has_live_target:
		distance_to_player = global_position.distance_to(player.global_position)

	_update_state(has_live_target, distance_to_player)
	_move(delta, player, distance_to_player)
	_update_sprite_facing_and_anim(player, has_live_target)

	_attack_cooldown_remaining -= delta
	if has_live_target and distance_to_player <= data.attack_range and _attack_cooldown_remaining <= 0:
		_perform_attack(player)
		_attack_cooldown_remaining = data.attack_cooldown

func _update_sprite_facing_and_anim(player: Node2D, has_live_target: bool) -> void:
	if _sprite_animator == null:
		return

	var face_x = velocity.x
	if absf(face_x) < 8.0 and has_live_target and player != null:
		face_x = player.global_position.x - global_position.x

	_sprite_animator.set_facing(face_x)
	var moving = velocity.length_squared() > (20.0 * 20.0)
	_sprite_animator.update_locomotion(moving)

func _update_state(has_live_target: bool, distance_to_player: float) -> void:
	if not has_live_target:
		_state = EnemyState.WANDER
		return

	if data.behavior_type == EnemyData.EnemyBehaviorType.FLEE and data.preferred_distance > 0.0 and distance_to_player < data.preferred_distance:
		_state = EnemyState.FLEE
	elif distance_to_player <= data.attack_range:
		_state = EnemyState.ATTACK
	else:
		_state = EnemyState.CHASE

func _move(delta: float, player: Node2D, distance_to_player: float) -> void:
	match _state:
		EnemyState.CHASE:
			velocity = _chase_velocity(delta, player) * _speed_multiplier
		EnemyState.FLEE:
			velocity = (global_position - player.global_position).normalized() * _runtime_move_speed * _speed_multiplier
		EnemyState.ATTACK:
			velocity = Vector2.ZERO
		EnemyState.WANDER:
			velocity = _wander_movement(delta) * _speed_multiplier

	move_and_slide()

func _chase_velocity(delta: float, player: Node2D) -> Vector2:
	var toward = (player.global_position - global_position).normalized()
	if not data.erratic_movement:
		return toward * _runtime_move_speed

	_erratic_repick_remaining -= delta
	if _erratic_repick_remaining <= 0:
		_erratic_strafe_sign = -1.0 if randf() < 0.5 else 1.0
		_erratic_repick_remaining = randi_range(0.35, 0.9)

	var lateral = toward.rotated(PI * 0.5 * _erratic_strafe_sign)
	var dir = (toward * 0.65 + lateral * 0.75).normalized()
	return dir * _runtime_move_speed

func _wander_movement(delta: float) -> Vector2:
	_wander_repick_remaining -= delta
	var reached_target = global_position.distance_squared_to(_wander_target) < (16.0 * 16.0)

	var repick_seconds = wander_repick_seconds * 0.45 if data.erratic_movement else wander_repick_seconds

	if _wander_repick_remaining <= 0 or reached_target:
		var offset = Vector2(wander_radius, 0).rotated(randf_range(0.0, TAU)) * randf_range(0.2, 1.0)
		_wander_target = _spawn_origin + offset
		_wander_repick_remaining = repick_seconds

	return (_wander_target - global_position).normalized() * _runtime_move_speed * wander_speed_scale

func _perform_attack(player: Node2D) -> void:
	if player != null:
		if _sprite_animator:
			_sprite_animator.set_facing(player.global_position.x - global_position.x)

	if _sprite_animator:
		_sprite_animator.play_attack()

	if data.attack_pattern == EnemyData.EnemyAttackPattern.MELEE:
		_perform_melee_attack()
	else:
		_fire_projectile_at(player)

func _perform_melee_attack() -> void:
	if _contact_hitbox == null:
		return

	for body in _contact_hitbox.get_overlapping_bodies():
		if not body.is_in_group("Player"):
			continue

		var health = body.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.is_dead:
			continue

		health.take_damage(roundi(_runtime_attack_damage), self)

func _fire_projectile_at(player: Node2D) -> void:
	if data.projectile_scene == null:
		return

	if _projectile_pool == null:
		_projectile_pool = ObjectPool.new(data.projectile_scene, get_tree().current_scene if get_tree().current_scene != null else get_parent(), 4)

	var spawn_pos = _projectile_spawn_point.global_position
	var direction = (player.global_position - spawn_pos).normalized()

	var projectile = _projectile_pool.acquire()
	projectile.launch(spawn_pos, direction, _projectile_pool, self, _runtime_attack_damage, 0.0, 1.0, 0.0, "Player")

func _on_damaged(amount: int, source: Node) -> void:
	if _death_sequence_running or _health == null or _health.is_dead:
		return

	if _sprite_animator:
		_sprite_animator.play_hurt()

func _on_died(source: Node) -> void:
	if _death_sequence_running:
		return

	_death_sequence_running = true
	velocity = Vector2.ZERO
	set_physics_process(false)

	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)

	if _contact_hitbox != null:
		# Deferred: pooled actors are released from inside collision callbacks,
		# and Godot forbids toggling an Area2D's monitoring flags while it is
		# flushing physics signals. Every path here already guards on its own
		# active/dead flag, so the one-frame lag changes no behaviour.
		_contact_hitbox.set_deferred("monitoring", false)

	if data != null and data.explode_on_death:
		_detonate_death_explosion()

	EventBus.enemy_killed.emit(self, data.currency_reward if data != null else 0, data.experience_reward if data != null else 0)

	if _sprite_animator != null:
		await _sprite_animator.play_death_async()

	if _pool:
		_pool.return_instance(self)
	_death_sequence_running = false

func _detonate_death_explosion() -> void:
	var radius = data.explosion_radius
	var radius_sq = radius * radius
	var damage = maxi(1, roundi(_runtime_explosion_damage))

	_damage_group_in_radius("Player", radius_sq, damage)
	_damage_group_in_radius("Enemy", radius_sq, damage)

func _damage_group_in_radius(group_name: String, radius_sq: float, damage: int) -> void:
	var tree = get_tree()
	if tree == null:
		return

	for node in tree.get_nodes_in_group(group_name):
		if node == self or not (node is Node2D):
			continue

		var body = node as Node2D
		if global_position.distance_squared_to(body.global_position) > radius_sq:
			continue

		var health = body.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.is_dead:
			continue

		health.take_damage(damage, self)

func _apply_visual_defaults(enemy_data: EnemyData) -> void:
	if enemy_data == null:
		return

	modulate = Color.WHITE
	scale = Vector2.ONE

	var sheet_path = enemy_data.sprite_sheet_path
	if sheet_path.is_empty() and enemy_data.sprite_sheet != null:
		sheet_path = enemy_data.sprite_sheet.resource_path

	var wants_sheet = enemy_data.sprite_sheet != null or not sheet_path.is_empty()
	var sheet_ok = false

	if wants_sheet and _sprite_animator != null:
		sheet_ok = _sprite_animator.configure(
			sheet_path,
			enemy_data.sprite_json_path,
			enemy_data.attack_anim_name,
			enemy_data.sprite_scale if enemy_data.sprite_scale > 0.0 else 1.0,
			enemy_data.sprite_color,
			enemy_data.sprite_sheet)
	else:
		if _sprite_animator:
			_sprite_animator.reset_visual()

	if _animated_sprite != null:
		_animated_sprite.visible = sheet_ok

	if _fallback_polygon != null:
		_fallback_polygon.visible = false

	if not sheet_ok:
		_show_procedural_skin(enemy_data, enemy_data.sprite_color)
	elif _procedural_sprite != null:
		_procedural_sprite.visible = false

	if wants_sheet and not sheet_ok:
		push_warning("[Enemy] Sheet failed for '%s' path='%s' — using procedural skin." % [enemy_data.enemy_name, sheet_path])

func _show_procedural_skin(enemy_data: EnemyData, tint: Color) -> void:
	if _procedural_sprite == null:
		_procedural_sprite = Sprite2D.new()
		_procedural_sprite.name = "ProceduralSkin"
		_procedural_sprite.centered = true
		# Matches EnemySpriteAnimator.SPRITE_Z so carried weapons and charms
		# layer the same whether the sheet loaded or the fallback is showing.
		_procedural_sprite.z_index = EnemySpriteAnimator.SPRITE_Z
		_procedural_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_procedural_sprite)

	var archetype = ProceduralSprite.archetype_for_enemy(enemy_data.enemy_name, enemy_data.is_undead)
	var palette = ProceduralSprite.palette_for_name(enemy_data.enemy_name)
	var primary: Color = tint if tint.a > 0.01 and tint != Color.WHITE else palette[0]
	var accent: Color = palette[1]

	_procedural_sprite.texture = ProceduralSprite.build(archetype, primary, accent, hash(enemy_data.enemy_name))
	_procedural_sprite.position.y = ProceduralSprite.anchor_y(archetype, 16.0)
	_procedural_sprite.visible = true

func _apply_elite_visual(is_elite: bool) -> void:
	if data == null:
		return

	if not is_elite:
		_apply_visual_defaults(data)
		return

	scale = Vector2.ONE * 1.12
	var elite_tint = data.sprite_color.lerp(Color(1.0, 0.35, 0.3, data.sprite_color.a), 0.55)
	elite_tint = Color(
		minf(1.5, elite_tint.r * 1.25),
		elite_tint.g * 0.85,
		elite_tint.b * 0.85,
		elite_tint.a)

	var sheet_path = data.sprite_sheet_path
	if sheet_path.is_empty() and data.sprite_sheet != null:
		sheet_path = data.sprite_sheet.resource_path

	var wants_sheet = data.sprite_sheet != null or not sheet_path.is_empty()
	var sheet_ok = false
	if wants_sheet and _sprite_animator != null:
		var scale_val = (data.sprite_scale if data.sprite_scale > 0.0 else 1.0) * 1.08
		sheet_ok = _sprite_animator.configure(
			sheet_path,
			data.sprite_json_path,
			data.attack_anim_name,
			scale_val,
			elite_tint,
			data.sprite_sheet)

	if _fallback_polygon != null:
		_fallback_polygon.visible = false

	if not sheet_ok:
		_show_procedural_skin(data, elite_tint)
	elif _procedural_sprite != null:
		_procedural_sprite.visible = false

	if _animated_sprite != null:
		_animated_sprite.visible = sheet_ok
		if sheet_ok:
			_animated_sprite.modulate = elite_tint

func _apply_phasing(phases: bool) -> void:
	collision_mask = 0 if phases else WORLD_COLLISION_MASK

func on_spawn() -> void:
	visible = true
	set_physics_process(true)
	set_process(true)
	process_mode = PROCESS_MODE_INHERIT
	# Pooled corpses leave host z at CORPSE_Z; restore living sort layer.
	z_index = 0

	collision_layer = 4
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", false)

	if _contact_hitbox != null:
		_contact_hitbox.set_deferred("monitoring", true)
		_contact_hitbox.set_deferred("monitorable", true)

func on_despawn() -> void:
	visible = false
	velocity = Vector2.ZERO
	set_physics_process(false)
	set_process(false)
	_is_elite = false
	_death_sequence_running = false
	modulate = Color.WHITE
	scale = Vector2.ONE
	collision_mask = WORLD_COLLISION_MASK
	collision_layer = 4
	if _sprite_animator:
		_sprite_animator.reset_visual()

	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)

	if _contact_hitbox != null:
		_contact_hitbox.set_deferred("monitoring", false)
		_contact_hitbox.set_deferred("monitorable", false)
