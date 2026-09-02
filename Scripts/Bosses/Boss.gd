extends CharacterBody2D
class_name Boss

# Base boss actor: phase transitions from BossData HP thresholds, telegraphed attack
# state machine (Chase → Windup → Recover), contact damage, and Enemy-group targeting so
# player weapons hit. Subclasses override ExecuteAttack for boss-specific patterns.

enum BossState {
	CHASE,
	WINDUP,
	RECOVER,
	DEAD
}

@export var data: BossData

@export_group("Wiring")
@export var health_component_path: NodePath
@export var sprite_node_path: NodePath
@export var sprite_animator_path: NodePath
@export var collision_shape_path: NodePath
@export var contact_hitbox_path: NodePath

var health: HealthComponent
# Placeholder art. Bosses with a sprite sheet hide this and drive the animator
# instead; the two are never visible at once.
var sprite: Polygon2D
var sprite_animator: EnemySpriteAnimator
var collision_shape: CollisionShape2D
var contact_hitbox: Area2D

var state: BossState = BossState.CHASE
var current_phase_index: int
var attack_cooldown_remaining: float
var windup_remaining: float
var recover_remaining: float
var contact_cooldown_remaining: float
var pending_attack: BossAttackPatternData
var active_telegraph: BossAoeTelegraph
var enemy_scene: PackedScene

# Minions spawned this fight; freed when the boss dies.
var spawned_minions: Array[Node] = []

# The wave this fight actually started on, which on a difficulty that deals
# bosses from a deck is no longer the same thing as data.wave_trigger. Set by
# BossManager before initialize; 0 means "nobody said", and the scaling is then
# a no-op.
var spawn_wave: int = 0

func _ready() -> void:
	add_to_group("Enemy")
	add_to_group("Boss")

	health = get_node_or_null(health_component_path)
	sprite = get_node_or_null(sprite_node_path) as Polygon2D
	sprite_animator = get_node_or_null(sprite_animator_path) as EnemySpriteAnimator
	collision_shape = get_node_or_null(collision_shape_path)
	contact_hitbox = get_node_or_null(contact_hitbox_path)
	enemy_scene = load("res://Scenes/Enemies/Enemy.tscn")

	if health != null:
		health.died.connect(_on_died)
		health.health_changed.connect(_on_health_changed)
	else:
		push_warning("[%s] HealthComponentPath not wired." % get_class())

	if data != null:
		apply_data(data)

# Called by BossManager after Instantiate, before the boss is active in-world.
func initialize(data: BossData) -> void:
	self.data = data
	apply_data(data)
	current_phase_index = 0
	state = BossState.CHASE
	attack_cooldown_remaining = 1.0
	contact_cooldown_remaining = 0
	pending_attack = null
	velocity = Vector2.ZERO
	on_phase_entered(0)

func apply_data(data: BossData) -> void:
	if data == null:
		return

	if health != null:
		var max_hp: int = maxi(1, roundi(data.max_health
			* Difficulty.enemy_health_multiplier(GameManager.difficulty)
			* get_wave_health_multiplier()))
		health.max_health = max_hp
		health.revive(max_hp)

	var sheet_ok = apply_sprite_sheet(data)
	if sprite != null:
		sprite.color = data.sprite_color
		sprite.visible = not sheet_ok

# Wires the boss sheet into the shared EnemySpriteAnimator. Returns whether
# frames actually loaded, so the caller can keep the placeholder up if not.
func apply_sprite_sheet(data: BossData) -> bool:
	if sprite_animator == null or data == null:
		return false

	var sheet_path = data.sprite_sheet_path
	if sheet_path.is_empty() and data.sprite_sheet != null:
		sheet_path = data.sprite_sheet.resource_path

	if sheet_path.is_empty() and data.sprite_sheet == null:
		return false

	return sprite_animator.configure(
		sheet_path,
		data.sprite_json_path,
		data.attack_anim_name,
		data.sprite_scale if data.sprite_scale > 0.0 else 1.0,
		Color.WHITE,
		data.sprite_sheet)

# Swaps in a phase's own artwork, for bosses that visibly transform rather than
# just speeding up. No-op when the phase names no sheet of its own.
func apply_phase_sprite_sheet(phase: BossPhaseData) -> bool:
	if sprite_animator == null or phase == null or data == null:
		return false

	var sheet_path = phase.sprite_sheet_path
	if sheet_path.is_empty() and phase.sprite_sheet != null:
		sheet_path = phase.sprite_sheet.resource_path

	if sheet_path.is_empty() and phase.sprite_sheet == null:
		return false

	var scale = phase.sprite_scale
	if scale <= 0.0:
		scale = data.sprite_scale if data.sprite_scale > 0.0 else 1.0

	return sprite_animator.configure(
		sheet_path,
		phase.sprite_json_path,
		data.attack_anim_name,
		scale,
		Color.WHITE,
		phase.sprite_sheet)

# Scales every point of damage this boss deals. Read by apply_damage_to_player
# and contact damage, so a phase that hits twice as hard needs one number in
# the resource rather than a duplicated set of attack patterns.
func get_phase_damage_multiplier() -> float:
	var phase = get_current_phase()
	var phase_multiplier = maxf(0.0, phase.damage_multiplier) if phase != null else 1.0
	return phase_multiplier 		* Difficulty.enemy_damage_multiplier(GameManager.difficulty) 		* get_wave_damage_multiplier()

# How much bigger this boss is for having turned up when it did. Both return 1.0
# on difficulties that do not scale bosses by wave, so the authored numbers are
# the numbers everywhere else.
func get_wave_health_multiplier() -> float:
	if not Difficulty.boss_wave_scaling(GameManager.difficulty):
		return 1.0

	return EnemyScaling.boss_health_multiplier(spawn_wave)

func get_wave_damage_multiplier() -> float:
	if not Difficulty.boss_wave_scaling(GameManager.difficulty):
		return 1.0

	return EnemyScaling.boss_damage_multiplier(spawn_wave)

# The boss's move speed for this run. Bosses read this instead of data.move_speed
# so the difficulty's speed floor reaches them too.
func get_move_speed() -> float:
	if data == null:
		return 0.0

	return Difficulty.enemy_speed(GameManager.difficulty, data.move_speed, GameManager.player_base_speed)

# Faces the sprite at a world point (sheets are drawn facing right).
func face_toward(point: Vector2) -> void:
	if sprite_animator != null:
		sprite_animator.set_facing(point.x - global_position.x)

# Which way the sprite should look this frame. Tracking the target rather than
# the velocity is what stops a boss that sidesteps or backs off from turning
# its back and appearing to moonwalk. Subclasses override for moves where the
# body genuinely leads — a leap looks where it lands.
func resolve_facing_x(player: Node2D) -> float:
	if player != null:
		return player.global_position.x - global_position.x

	return velocity.x

func _physics_process(delta: float) -> void:
	if data == null or health == null or health.is_dead or state == BossState.DEAD:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	update_phase_from_health()

	var player = get_tree().get_first_node_in_group("Player") as Node2D
	var player_health: HealthComponent = player.get_node_or_null("HealthComponent") if player else null
	var has_live_target = player != null and (player_health == null or not player_health.is_dead)

	tick_contact_damage(delta, has_live_target)

	match state:
		BossState.CHASE:
			process_chase(delta, player, has_live_target)
		BossState.WINDUP:
			process_windup(delta, player, has_live_target)
		BossState.RECOVER:
			process_recover(delta, player, has_live_target)

	if sprite_animator != null:
		sprite_animator.set_facing(resolve_facing_x(player))
		sprite_animator.update_locomotion(velocity.length_squared() > 4.0)

	move_and_slide()

func process_chase(delta: float, player: Node2D, has_live_target: bool) -> void:
	if has_live_target:
		var speed = get_move_speed() * get_phase_move_multiplier()
		velocity = (player.global_position - global_position).normalized() * speed
	else:
		velocity = Vector2.ZERO

	attack_cooldown_remaining -= delta
	if has_live_target and attack_cooldown_remaining <= 0:
		try_begin_attack(player)

func process_windup(delta: float, player: Node2D, has_live_target: bool) -> void:
	# Hold still while casting so telegraphs stay readable.
	velocity = Vector2.ZERO
	windup_remaining -= delta
	if windup_remaining > 0:
		return

	var recovery = pending_attack.recovery_seconds if pending_attack else 0.25
	if pending_attack != null:
		remember_attack_cooldown(pending_attack)
		if sprite_animator != null:
			sprite_animator.play_attack()

		if has_live_target:
			execute_attack(pending_attack, player)

	pending_attack = null
	active_telegraph = null
	state = BossState.RECOVER
	recover_remaining = recovery

func process_recover(delta: float, player: Node2D, has_live_target: bool) -> void:
	velocity = Vector2.ZERO
	recover_remaining -= delta
	if recover_remaining > 0:
		return

	state = BossState.CHASE
	attack_cooldown_remaining = get_next_attack_cooldown()

func try_begin_attack(player: Node2D) -> void:
	var attack = pick_attack()
	if attack == null:
		attack_cooldown_remaining = 1.0
		return

	pending_attack = attack
	windup_remaining = maxf(0.05, attack.windup_seconds)
	state = BossState.WINDUP
	velocity = Vector2.ZERO
	if player != null:
		face_toward(player.global_position)

	begin_telegraph(attack, player)

# Default telegraph: red AoE on the player (or self for self-centered attacks).
# Subclasses may override for multi-zone / custom previews. DealDamageOnComplete is false
# so ExecuteAttack owns the real hit (avoids double damage).
func begin_telegraph(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null or player == null:
		return

	var id = attack.attack_id if attack.attack_id != null else ""
	# Summons / blinks flash at boss; most AoEs telegraph on player.
	var self_centered = id in ["bat_swarm", "summon_ghouls", "summon_cultists", "blink", "heavy_melee", "blood_slash"]

	var pos = global_position if self_centered else player.global_position
	var radius = maxf(24.0, attack.radius)

	# Blink has a short self flash only.
	if id == "blink":
		radius = 40.0

	active_telegraph = BossAoeTelegraph.spawn(
		self,
		pos,
		radius,
		attack.windup_seconds,
		roundi(attack.damage),
		self,
		false)

# Boss-specific attack resolution. Override in subclasses.
func execute_attack(attack: BossAttackPatternData, player: Node2D) -> void:
	# Generic fallback: AoE at player feet.
	if player != null and global_position.distance_to(player.global_position) <= attack.radius + 16.0:
		apply_damage_to_player(roundi(attack.damage), attack.heal_fraction)

func apply_damage_to_player(damage: int, heal_fraction: float = 0.0) -> void:
	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	var health_comp: HealthComponent = player.get_node_or_null("HealthComponent")
	if health_comp == null or health_comp.is_dead:
		return

	var scaled = maxi(1, roundi(damage * get_phase_damage_multiplier()))
	health_comp.take_damage(scaled, self)
	if heal_fraction > 0.0 and health != null and not health.is_dead:
		health.heal(maxi(1, roundi(scaled * heal_fraction)))

func apply_damage_in_radius(center: Vector2, radius: float, damage: int, heal_fraction: float = 0.0) -> void:
	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null or center.distance_to(player.global_position) > radius:
		return

	apply_damage_to_player(damage, heal_fraction)

func pick_attack() -> BossAttackPatternData:
	var phase = get_current_phase()
	if phase == null or phase.attacks == null or phase.attacks.size() == 0:
		return null

	var index = randi() % phase.attacks.size()
	return phase.attacks[index]

func get_current_phase() -> BossPhaseData:
	if data == null or data.phases == null or data.phases.size() == 0:
		return null

	current_phase_index = clampi(current_phase_index, 0, data.phases.size() - 1)
	return data.phases[current_phase_index]

func get_phase_move_multiplier() -> float:
	var phase = get_current_phase()
	return phase.move_speed_multiplier if phase else 1.0

func get_phase_cooldown_multiplier() -> float:
	var phase = get_current_phase()
	return phase.attack_cooldown_multiplier if phase else 1.0

var _last_used_cooldown: float = 2.5

func get_next_attack_cooldown() -> float:
	var base_cd = _last_used_cooldown
	var phase = get_current_phase()
	if phase != null and phase.attacks != null and phase.attacks.size() > 0:
		# Prefer the last attack's cooldown; fall back to the phase's fastest attack.
		base_cd = _last_used_cooldown
		var min_cd = phase.attacks[0].cooldown_seconds
		for i in range(1, phase.attacks.size()):
			min_cd = minf(min_cd, phase.attacks[i].cooldown_seconds)

		if base_cd <= 0.0:
			base_cd = min_cd

	return maxf(0.35, base_cd * get_phase_cooldown_multiplier() * randf_range(0.85, 1.15))

func remember_attack_cooldown(attack: BossAttackPatternData) -> void:
	if attack != null:
		_last_used_cooldown = attack.cooldown_seconds

func update_phase_from_health() -> void:
	if data == null or data.phases == null or data.phases.size() <= 1 or health == null or health.max_health <= 0:
		return

	var fraction = float(health.current_health) / health.max_health
	var new_phase = 0
	for i in range(data.phases.size()):
		var phase = data.phases[i]
		if phase == null:
			continue

		# Phase 0 always qualifies; later phases unlock when HP is at or below threshold.
		if i == 0 or fraction <= phase.enter_hp_fraction:
			new_phase = i

	if new_phase != current_phase_index:
		var previous = current_phase_index
		current_phase_index = new_phase
		on_phase_entered(current_phase_index, previous)

func on_phase_entered(phase_index: int, previous_phase_index: int = -1) -> void:
	var phase = get_current_phase()
	if phase != null:
		apply_phase_sprite_sheet(phase)
		print("[Boss] %s entered %s (index %d)." % [data.boss_name, phase.phase_name, phase_index])

func tick_contact_damage(delta: float, has_live_target: bool) -> void:
	if not has_live_target or contact_hitbox == null or data == null:
		return

	# A boss that has made itself intangible turns this Area2D off — the Voivode
	# does it mid shadow step, the Belfry Tyrant while he is aloft. Asking a
	# disabled area what it overlaps is an error per frame for the whole
	# manoeuvre, and the answer would be "nothing" regardless.
	if not contact_hitbox.monitoring:
		return

	contact_cooldown_remaining -= delta
	if contact_cooldown_remaining > 0:
		return

	for body in contact_hitbox.get_overlapping_bodies():
		if not body.is_in_group("Player"):
			continue

		var hp: HealthComponent = body.get_node_or_null("HealthComponent")
		if hp == null or hp.is_dead:
			continue

		hp.take_damage(maxi(1, roundi(data.contact_damage * get_phase_damage_multiplier())), self)
		contact_cooldown_remaining = data.contact_damage_cooldown
		break

# Spawns a lightweight Enemy minion from Enemy.tscn with runtime EnemyData.
# Tracks it for cleanup; frees on minion death (Enemy pool is null).
func spawn_minion(global_position: Vector2, name: String, color: Color, max_health: int, move_speed: float,
	attack_damage: float, attack_cooldown: float = 1.0, sheet_path: String = "",
	sprite_scale: float = 1.0) -> Enemy:
	if enemy_scene == null:
		return null

	var data_obj = EnemyData.new()
	data_obj.enemy_name = name
	data_obj.sprite_color = color
	data_obj.max_health = max_health
	data_obj.move_speed = move_speed
	data_obj.attack_damage = attack_damage
	data_obj.attack_pattern = EnemyData.EnemyAttackPattern.MELEE
	data_obj.behavior_type = EnemyData.EnemyBehaviorType.CHASE
	data_obj.aggro_range = 900.0
	data_obj.attack_range = 36.0
	data_obj.attack_cooldown = attack_cooldown
	data_obj.currency_reward = 1
	data_obj.experience_reward = 1
	data_obj.is_undead = true
	# Optional: give the add real sheet art instead of the procedural skin.
	data_obj.sprite_sheet_path = sheet_path
	data_obj.sprite_scale = sprite_scale

	var enemy = enemy_scene.instantiate()
	# Parent under World with Player/enemies so minions y-sort correctly.
	var parent = get_parent()
	if parent == null or not is_instance_valid(parent):
		var scene = get_tree().current_scene if get_tree() else null
		parent = scene.get_node_or_null("World") if scene != null else null
		if parent == null:
			parent = scene
	parent.add_child(enemy)
	enemy.global_position = global_position
	enemy.initialize(data_obj, null)

	var minion_health: HealthComponent = enemy.get_node_or_null("HealthComponent")
	if minion_health != null:
		minion_health.died.connect(func(_src):
			if is_instance_valid(enemy):
				enemy.queue_free()
			spawned_minions.erase(enemy))

	spawned_minions.append(enemy)
	return enemy

var _last_seen_health: int = -1

func _on_health_changed(current_health: int, max_health: int) -> void:
	# Flinch only on damage, and never mid-wind-up: a boss that twitches out of
	# its own telegraph is a boss whose attacks cannot be read.
	var took_damage = _last_seen_health >= 0 and current_health < _last_seen_health
	_last_seen_health = current_health
	if took_damage and state == BossState.CHASE and sprite_animator != null:
		sprite_animator.play_hurt()

func _on_died(source: Node) -> void:
	state = BossState.DEAD
	velocity = Vector2.ZERO
	free_minions()
	if sprite_animator != null:
		sprite_animator.play_death_async()

	var currency = data.currency_reward if data else 0
	var xp = data.experience_reward if data else 0
	EventBus.enemy_killed.emit(self, currency, xp)
	EventBus.boss_encounter_end.emit(data.boss_name if data else name, true)

	# Brief death hold then free — BossManager also listens to OnBossEncounterEnd.
	var tree = get_tree()
	if tree != null:
		tree.create_timer(1.1 if sprite_animator != null else 0.6).timeout.connect(func():
			if is_instance_valid(self):
				queue_free())

func _exit_tree() -> void:
	free_minions()

# Despawns adds (bats/ghouls/cultists) owned by this fight.
func free_minions() -> void:
	for minion in spawned_minions:
		if is_instance_valid(minion):
			minion.queue_free()

	spawned_minions.clear()
