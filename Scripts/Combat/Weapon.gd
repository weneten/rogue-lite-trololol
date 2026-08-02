extends Node2D
class_name Weapon

# Auto-attacking weapon slot attachable to Player (Brotato-style: no manual aim/fire input).
# Every frame it looks for the nearest live member of TargetGroup within WeaponData.Range;
# once found it rotates to face it and, on cooldown expiry, either runs a melee hitbox check
# (WeaponClass.Melee) or spawns pooled Projectile(s) aimed at the target (everything else).

@export var data: WeaponData
@export var target_group: String = "Enemy"

@export_group("Wiring")
# Body this weapon is mounted on; distances/origin are measured from here. Defaults to the parent node.
@export var owner_body_path: NodePath
# Area2D whose shape defines the melee swing reach. Required for Melee-class weapons.
@export var melee_hitbox_path: NodePath
# Where projectiles spawn from (muzzle). Defaults to this node's position.
@export var projectile_spawn_point_path: NodePath

@export_group("Pooling")
@export var projectile_pool_prewarm: int = 8

var _owner_body: Node2D
var _melee_hitbox: Area2D
var _spawn_point: Node2D
var _projectile_pool: ObjectPool
var _trap_pool: ObjectPool
# Optional — only present when mounted on the Player. Non-player owners (none currently exist) just get a 1x multiplier.
var _owner_stats: PlayerStats
var _owner_health: HealthComponent

var _cooldown_remaining: float = 0.0

func _ready() -> void:
	_owner_body = get_node_or_null(owner_body_path) as Node2D if owner_body_path else get_parent() as Node2D
	_melee_hitbox = get_node_or_null(melee_hitbox_path) as Area2D
	_spawn_point = get_node_or_null(projectile_spawn_point_path) as Node2D if projectile_spawn_point_path else self
	_owner_stats = _owner_body.get_node_or_null("PlayerStats") as PlayerStats if _owner_body else null
	_owner_health = _owner_body.get_node_or_null("HealthComponent") as HealthComponent if _owner_body else null

	if data == null:
		push_warning("[Weapon] No WeaponData assigned; weapon is inert.")
		return

	var is_melee = (data.weapon_class & WeaponData.WeaponClass.MELEE) != 0
	var is_summon = (data.weapon_class & WeaponData.WeaponClass.SUMMON) != 0
	var is_trap = (data.weapon_class & WeaponData.WeaponClass.TRAP) != 0

	if is_melee and _melee_hitbox == null:
		push_warning("[Weapon] '%s' is Melee but MeleeHitboxPath is unwired; it will never deal damage." % data.name)
	if not is_melee and not is_summon and not is_trap and data.projectile_scene != null:
		_projectile_pool = ObjectPool.new(data.projectile_scene, get_tree().current_scene, projectile_pool_prewarm)
	if is_trap and data.trap_scene != null:
		_trap_pool = ObjectPool.new(data.trap_scene, get_tree().current_scene, 2)
	if is_summon and data.summon_scene != null:
		_spawn_familiar()

func _process(delta: float) -> void:
	if data == null or _owner_body == null:
		return

	# Summon-class weapons spawn an independent Familiar in _ready and never attack directly
	# themselves — the Familiar tracks/fires on its own timer, so this node has nothing left to do.
	if (data.weapon_class & WeaponData.WeaponClass.SUMMON) != 0:
		return

	_cooldown_remaining -= delta

	var target = _find_nearest_target()
	if target == null:
		return

	# Face the target regardless of cooldown so the weapon visibly tracks its target.
	global_rotation = (target.global_position - _owner_body.global_position).angle()

	if _cooldown_remaining > 0:
		return

	_attack(target)
	_cooldown_remaining = 1.0 / maxf(0.01, data.attack_speed * (_owner_stats.attack_speed_multiplier if _owner_stats else 1.0))

# Nearest live TargetGroup member within Data.Range, or null if none in range.
func _find_nearest_target() -> Node2D:
	var nearest = null
	var nearest_dist_sq = data.range * data.range

	for node in get_tree().get_nodes_in_group(target_group):
		if not node is Node2D:
			continue

		var candidate = node as Node2D
		var health = candidate.get_node_or_null("HealthComponent") as HealthComponent
		if health != null and health.is_dead:
			continue

		var dist_sq = _owner_body.global_position.distance_squared_to(candidate.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = candidate

	return nearest

func _attack(target: Node2D) -> void:
	AudioManager.play_sfx(_resolve_weapon_hit_sfx_id())

	# Let the wielder play its swing. Duck-typed so this works for the player
	# and for anything else that ends up holding a weapon.
	if _owner_body != null and _owner_body.has_method("play_attack_animation"):
		_owner_body.play_attack_animation(target)

	# Order matters: Trap pre-empts everything (it never attacks directly), Melee handles its
	# own cleave via the hitbox overlap even when also flagged AoE (War Cleaver), and pure AoE
	# (no Melee) gets the radius-burst path; anything left over fires a projectile.
	if (data.weapon_class & WeaponData.WeaponClass.TRAP) != 0:
		_place_trap()
	elif (data.weapon_class & WeaponData.WeaponClass.MELEE) != 0:
		_perform_melee_attack()
	elif (data.weapon_class & WeaponData.WeaponClass.AOE) != 0:
		_perform_area_attack(target)
	else:
		_fire_projectiles(target)

# Maps WeaponClass flags to an SFX id (first matching class wins).
func _resolve_weapon_hit_sfx_id() -> String:
	var c = data.weapon_class
	if (c & WeaponData.WeaponClass.TRAP) != 0: return "weapon_trap"
	if (c & WeaponData.WeaponClass.MELEE) != 0: return "weapon_melee"
	if (c & WeaponData.WeaponClass.FIREARM) != 0: return "weapon_firearm"
	if (c & WeaponData.WeaponClass.MAGIC) != 0: return "weapon_magic"
	if (c & WeaponData.WeaponClass.HOLY) != 0: return "weapon_holy"
	if (c & WeaponData.WeaponClass.CURSED) != 0: return "weapon_cursed"
	if (c & WeaponData.WeaponClass.AOE) != 0: return "weapon_aoe"
	if (c & WeaponData.WeaponClass.SUMMON) != 0: return "weapon_summon"
	if (c & WeaponData.WeaponClass.RANGED) != 0: return "weapon_ranged"
	return "weapon_hit"

# Brotato-style melee: damage every live TargetGroup member within WeaponData.Range.
# Hitbox overlap alone was too small vs Range, so weapons "swung" without landing hits.
func _perform_melee_attack() -> void:
	if _owner_body == null or data == null:
		return

	var range = maxf(8.0, data.range)
	var range_sq = range * range
	var origin = _owner_body.global_position

	# Prefer hitbox overlaps when present (multi-target cleave geometry), then fill gaps
	# with a pure distance check so nothing inside Range is immune.
	var hit_ids = []

	if _melee_hitbox != null:
		for body in _melee_hitbox.get_overlapping_bodies():
			if not body.is_in_group(target_group):
				continue

			if _try_damage_target(body):
				hit_ids.append(body.get_instance_id())

	for node in get_tree().get_nodes_in_group(target_group):
		if not node is Node2D:
			continue

		var body = node as Node2D

		if hit_ids.has(body.get_instance_id()):
			continue

		if origin.distance_squared_to(body.global_position) > range_sq:
			continue

		_try_damage_target(body)

# Applies one weapon hit (crit, mults, lifesteal, knockback). Returns false if skipped.
func _try_damage_target(body: Node2D) -> bool:
	var health = body.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.is_dead:
		return false

	var crit_chance = data.crit_chance + (_owner_stats.extra_crit_chance if _owner_stats else 0.0)
	var crit_multiplier = data.crit_multiplier + (_owner_stats.extra_crit_multiplier if _owner_stats else 0.0)
	var is_crit = randf() < crit_chance

	var damage_multiplier = _compute_damage_multiplier(body)
	var final_damage = maxi(1, roundi(
		data.damage * damage_multiplier * (crit_multiplier if is_crit else 1.0)))

	health.take_damage(final_damage, _owner_body)
	if _owner_stats:
		_owner_stats.notify_damage_dealt(final_damage, body)
	_apply_on_hit_lifesteal(final_damage)

	if body is TargetDummy and data.knockback > 0.0:
		var dummy = body as TargetDummy
		var push_dir = (dummy.global_position - _owner_body.global_position).normalized()
		dummy.apply_knockback(push_dir * data.knockback)

	return true

# Spawns Data.ProjectileCount pooled projectiles fanned across Data.Spread degrees, aimed at target.
func _fire_projectiles(target: Node2D) -> void:
	if _projectile_pool == null:
		return

	var base_direction = (target.global_position - _spawn_point.global_position).normalized()
	var count = maxi(1, data.projectile_count)
	var spread_rad = deg_to_rad(data.spread)

	var crit_chance = data.crit_chance + (_owner_stats.extra_crit_chance if _owner_stats else 0.0)
	var crit_multiplier = data.crit_multiplier + (_owner_stats.extra_crit_multiplier if _owner_stats else 0.0)
	# Undead/Magic bonuses are resolved against the tracked target at fire time rather than
	# whatever the projectile actually collides with — an acceptable approximation since
	# projectiles fly straight at where the target was when fired.
	var damage_multiplier = _compute_damage_multiplier(target)

	for i in range(count):
		# Evenly fan projectiles across [-spread/2, +spread/2]; a single projectile fires straight.
		var t = 0.0 if count == 1 else float(i) / (count - 1) - 0.5
		var angle_offset = spread_rad * t
		var direction = base_direction.rotated(angle_offset)

		var projectile = _projectile_pool.acquire()
		projectile.launch(
			_spawn_point.global_position,
			direction,
			_projectile_pool,
			_owner_body,
			data.damage * damage_multiplier,
			crit_chance,
			crit_multiplier,
			data.knockback,
			target_group,
			func(dealt: int, hit_body: Node2D):
				if _owner_stats:
					_owner_stats.notify_damage_dealt(dealt, hit_body)
				_apply_on_hit_lifesteal(dealt)
		)

# Radius burst used by pure WeaponClass.AoE weapons (Firebomb, Frost Lantern, Holy Water
# Flask, Bell of Judgement): damages every live TargetGroup member within AoERadius of either
# the current target (thrown weapons) or the wielder (self-centered pulses), and applies the
# weapon's slow if configured. Unlike melee cleave this isn't gated on a hitbox overlap, so it
# works for weapons with no travelling projectile at all.
func _perform_area_attack(primary_target: Node2D) -> void:
	var origin = _owner_body.global_position if data.aoe_centered_on_self else primary_target.global_position
	var radius = data.aoe_radius if data.aoe_radius > 0.0 else data.range
	var radius_sq = radius * radius

	var crit_chance = data.crit_chance + (_owner_stats.extra_crit_chance if _owner_stats else 0.0)
	var crit_multiplier = data.crit_multiplier + (_owner_stats.extra_crit_multiplier if _owner_stats else 0.0)

	for node in get_tree().get_nodes_in_group(target_group):
		if not node is Node2D or origin.distance_squared_to(node.global_position) > radius_sq:
			continue

		var body = node as Node2D
		var health = body.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.is_dead:
			continue

		var is_crit = randf() < crit_chance
		var damage_multiplier = _compute_damage_multiplier(body)
		var final_damage = roundi(data.damage * damage_multiplier * (crit_multiplier if is_crit else 1.0))
		health.take_damage(final_damage, _owner_body)
		if _owner_stats:
			_owner_stats.notify_damage_dealt(final_damage, body)
		_apply_on_hit_lifesteal(final_damage)

		if data.slow_multiplier > 0.0 and body is Enemy:
			var slowed_enemy = body as Enemy
			slowed_enemy.apply_movement_modifier(1.0 - data.slow_multiplier, data.slow_duration_seconds)

		if body is TargetDummy and data.knockback > 0.0:
			var dummy = body as TargetDummy
			var push_dir = (dummy.global_position - origin).normalized()
			dummy.apply_knockback(push_dir * data.knockback)

# Drops a pooled Trap at the wielder's feet (Iron Bear Trap); it sits armed until
# something in TargetGroup walks over it or TrapLifetimeSeconds elapses unused.
func _place_trap() -> void:
	if _trap_pool == null:
		return

	var crit_chance = data.crit_chance + (_owner_stats.extra_crit_chance if _owner_stats else 0.0)
	var crit_multiplier = data.crit_multiplier + (_owner_stats.extra_crit_multiplier if _owner_stats else 0.0)
	var damage_multiplier = _owner_stats.damage_multiplier if _owner_stats else 1.0

	var trap = _trap_pool.acquire()
	trap.arm(
		_owner_body.global_position,
		_trap_pool,
		_owner_body,
		data.damage * damage_multiplier,
		crit_chance,
		crit_multiplier,
		target_group,
		data.trap_root_duration_seconds,
		data.trap_lifetime_seconds,
		func(dealt: int, hit_body: Node2D):
			if _owner_stats:
				_owner_stats.notify_damage_dealt(dealt, hit_body)
			_apply_on_hit_lifesteal(dealt)
	)

# Instantiates Data.SummonScene once as an independent scene-tree sibling (not a
# child of this Weapon, so it can roam freely) and hands it the owner/stats it needs to fight
# on its own. Called once from _ready — buying a second copy of a Summon weapon spawns a
# second independent familiar, matching how every other weapon slot stacks.
func _spawn_familiar() -> void:
	var familiar = data.summon_scene.instantiate() as Node2D
	(get_tree().current_scene if get_tree().current_scene else get_parent()).add_child(familiar)
	familiar.global_position = _owner_body.global_position

	if familiar is Familiar:
		var familiar_script = familiar as Familiar
		familiar_script.setup(_owner_body, data, _owner_stats)

# Heals the wielder for Data.OnHitLifestealFraction of a landed hit (Vampiric Claws).
# Stacks additively with PlayerStats.LifestealFraction, which notify_damage_dealt already applies.
func _apply_on_hit_lifesteal(damage_dealt: int) -> void:
	if data.on_hit_lifesteal_fraction <= 0.0:
		return

	if _owner_health:
		_owner_health.heal(roundi(damage_dealt * data.on_hit_lifesteal_fraction))

# Base damage_multiplier plus the character-passive bonuses that only apply
# conditionally: magic_damage_multiplier (+ this weapon's own magic_scaling_per_point) for
# WeaponClass.Magic, cursed_missing_hp_scaling for WeaponClass.Cursed, and undead_damage_multiplier
# when the target is an EnemyData.is_undead archetype.
func _compute_damage_multiplier(target: Node2D) -> float:
	var multiplier = _owner_stats.damage_multiplier if _owner_stats else 1.0

	if (data.weapon_class & WeaponData.WeaponClass.MAGIC) != 0:
		var magic_stat = _owner_stats.magic_damage_multiplier if _owner_stats else 1.0
		multiplier *= magic_stat

		if data.magic_scaling_per_point > 0.0:
			# Rewards magic-focused Hunters extra hard on weapons tuned for it, on top of the
			# flat magic_damage_multiplier every Magic weapon already gets above.
			multiplier *= 1.0 + data.magic_scaling_per_point * maxf(0.0, magic_stat - 1.0)

	if (data.weapon_class & WeaponData.WeaponClass.CURSED) != 0 and data.cursed_missing_hp_scaling > 0.0 and _owner_health != null and _owner_health.max_health > 0:
		var missing_hp_fraction = 1.0 - float(_owner_health.current_health) / _owner_health.max_health
		multiplier *= 1.0 + data.cursed_missing_hp_scaling * missing_hp_fraction

	if target is Enemy:
		var enemy = target as Enemy
		if enemy.data != null and enemy.data.is_undead:
			multiplier *= _owner_stats.undead_damage_multiplier if _owner_stats else 1.0

	return multiplier
