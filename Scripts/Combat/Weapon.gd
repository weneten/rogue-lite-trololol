extends Node2D
class_name Weapon

# Auto-attacking weapon slot attachable to Player (Brotato-style: no manual aim/fire input).
# Facing tracks the nearest live TargetGroup member still on camera, even outside
# WeaponData.Range. Attacks themselves stay range-gated: on cooldown expiry it
# either runs a melee hitbox check (WeaponClass.Melee) or spawns pooled
# Projectile(s) at the nearest in-range target. With nothing on screen the
# carried visual whirls around the wielder instead of freezing.

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

# This weapon's offset from the shared aim direction, in radians. Set by
# WeaponInventory from the slot index so a full loadout fans out on whichever
# side the nearest enemy is on instead of stacking into one sprite.
var slot_offset: float = 0.0:
	set(value):
		slot_offset = value
		if _visual != null:
			_visual.slot_offset = value

var _visual: WeaponVisual

# Damage this weapon has dealt since the current wave started, so the HUD can
# show which of six slots is actually carrying the run. Reset by WaveManager's
# wave_start, not by the shop: a weapon bought mid-shop starts the next wave at
# zero like everything else.
var damage_this_wave: int = 0

# Buying a weapon you already carry sharpens that one instead of taking a second
# slot. Everything below reads its numbers through the accessors rather than off
# `data` directly, because `data` is a shared Resource — the same WeaponData
# object is handed to every Hunter and every run, so writing a level into it
# would upgrade the weapon for everybody, permanently, including next session.
var level: int = 1

# Per level past the first, added rather than compounded: five levels of a
# compounding 28% is nearly four times the damage, which turns one lucky shop
# into the whole run.
const DAMAGE_PER_LEVEL := 0.28
const ATTACK_SPEED_PER_LEVEL := 0.10
# Reach and blast radius grow slowest. A weapon that outranges the screen stops
# being a weapon choice and becomes an aura.
const AREA_PER_LEVEL := 0.06
# Multi-shot weapons gain a projectile at levels 3 and 5.
const PROJECTILE_EVERY_LEVELS := 2
const MAX_LEVEL := 5

func get_level_scale(per_level: float) -> float:
	return 1.0 + float(level - 1) * per_level

func get_damage() -> float:
	return data.damage * get_level_scale(DAMAGE_PER_LEVEL) if data != null else 0.0

func get_attack_speed() -> float:
	return data.attack_speed * get_level_scale(ATTACK_SPEED_PER_LEVEL) if data != null else 1.0

func get_range() -> float:
	return data.range * get_level_scale(AREA_PER_LEVEL) if data != null else 0.0

func get_aoe_radius() -> float:
	if data == null:
		return 0.0

	var base: float = data.aoe_radius if data.aoe_radius > 0.0 else data.range
	return base * get_level_scale(AREA_PER_LEVEL)

func get_projectile_count() -> int:
	if data == null:
		return 1

	return maxi(1, data.projectile_count + (level - 1) / PROJECTILE_EVERY_LEVELS)

func can_level_up() -> bool:
	return level < MAX_LEVEL

func level_up() -> bool:
	if not can_level_up():
		return false

	level += 1
	# The cooldown in flight was sized by the old attack speed. Left alone, the
	# first swing after an upgrade still comes at the old pace, which reads as
	# the purchase not having taken.
	_cooldown_remaining = minf(_cooldown_remaining, 1.0 / maxf(0.01, get_attack_speed()))
	return true

func _ready() -> void:
	_owner_body = get_node_or_null(owner_body_path) as Node2D if owner_body_path else get_parent() as Node2D
	_melee_hitbox = get_node_or_null(melee_hitbox_path) as Area2D
	_spawn_point = get_node_or_null(projectile_spawn_point_path) as Node2D if projectile_spawn_point_path else self
	_owner_stats = _owner_body.get_node_or_null("PlayerStats") as PlayerStats if _owner_body else null
	_owner_health = _owner_body.get_node_or_null("HealthComponent") as HealthComponent if _owner_body else null

	# Per-wave damage is a scoreboard, so it starts over with the wave. Connected
	# even for Summon weapons, whose Familiar reports through the same counter.
	EventBus.wave_start.connect(_on_wave_start)

	if data == null:
		push_warning("[Weapon] No WeaponData assigned; weapon is inert.")
		return

	_build_visual()

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

	if _owner_health != null and _owner_health.is_dead:
		_update_visual_facing(false)
		return

	_cooldown_remaining -= delta

	# Aim at the nearest enemy still on camera, even if they are outside this
	# weapon's attack range. Combat itself stays range-gated below. Inventory
	# computes this once per frame for the whole loadout.
	var sight_target: Node2D = null
	if WeaponInventory.instance != null:
		sight_target = WeaponInventory.instance.aim_target
	else:
		sight_target = _find_nearest_in_sight()
	if sight_target != null:
		global_rotation = (sight_target.global_position - _owner_body.global_position).angle()
		_update_visual_facing(true)
	else:
		# Nothing on screen: the visual spins around the wielder instead of
		# freezing on the last corpse or dropping to a rest pose.
		_update_visual_facing(false)

	if _cooldown_remaining > 0:
		return

	# Weapons hold fire whenever the arena is held — the count-in and the gap
	# between waves both. The enemies are frozen for it, and free hits on a field
	# that cannot fight back would turn a breather into a bonus. Aim still tracks
	# above, so the loadout is pointed the right way when the hold lifts.
	if WaveManager != null and WaveManager.is_arena_held:
		return

	var target := _find_nearest_target()
	if target == null:
		return

	_attack(target)
	if NetSession != null and NetSession.is_active:
		NetSession.note_swing()
	_cooldown_remaining = 1.0 / maxf(0.01, get_attack_speed() * (_owner_stats.attack_speed_multiplier if _owner_stats else 1.0))

# Summon weapons have no carried copy — the Familiar IS the visible thing, and
# drawing a whistle in the player's hand as well just added clutter.
func _build_visual() -> void:
	if (data.weapon_class & WeaponData.WeaponClass.SUMMON) != 0:
		return

	# Parented to the wielder, not to this node: this node sits at the body
	# origin (the feet), so anything hanging off it orbited their ankles.
	if _owner_body == null:
		return

	_visual = WeaponVisual.new()
	_visual.name = "WeaponVisual_" + data.name
	_visual.slot_offset = slot_offset
	_visual.setup(data)
	_update_visual_facing(false)
	# Deferred: a weapon whose wielder is itself mid-_ready (spawned at runtime
	# rather than authored into the scene) cannot take a new child yet, and the
	# failed add left that slot permanently invisible.
	_attach_visual.call_deferred()

# Runs a frame after _build_visual. By then the weapon may already be gone —
# Player.apply_character_data clears the scene-authored loadout on the very
# frame it is built — so this re-checks everything rather than handing add_child
# a reference that was freed in between.
func _attach_visual() -> void:
	if _visual == null or not is_instance_valid(_visual) or _visual.get_parent() != null:
		return

	if _owner_body == null or not is_instance_valid(_owner_body):
		_visual.queue_free()
		_visual = null
		return

	_owner_body.add_child(_visual)

func _update_visual_facing(has_target: bool) -> void:
	if _visual != null:
		_visual.set_aim(rotation, has_target)

func _on_wave_start(_wave_number: int) -> void:
	damage_this_wave = 0

# Single funnel for the per-wave scoreboard. Every path that lands damage — melee
# cleave, projectile hit, AoE pulse, trap trigger — routes through here so a new
# attack type cannot silently go uncounted.
func _record_damage(amount: int) -> void:
	damage_this_wave += maxi(0, amount)

# The visual lives on the wielder, so it has to be torn down with the weapon
# rather than left behind when a slot is sold.
func _exit_tree() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null

# Nearest live TargetGroup member within Data.Range, or null if none in range.
func _find_nearest_target() -> Node2D:
	var reach := get_range()
	return find_nearest(_owner_body, target_group, reach * reach, false)

# Nearest live TargetGroup member still on camera. Range is ignored — this is
# only for facing. Returns null when every enemy is off-screen (or dead/pooled),
# which is the cue for the carried weapons to spin.
func _find_nearest_in_sight() -> Node2D:
	return find_nearest(_owner_body, target_group, -1.0, true)

static func find_nearest(from: Node2D, group: String, max_dist_sq: float, require_in_sight: bool) -> Node2D:
	if from == null or not is_instance_valid(from) or from.get_tree() == null:
		return null

	var nearest: Node2D = null
	var nearest_dist_sq := max_dist_sq if max_dist_sq >= 0.0 else INF
	var origin := from.global_position
	var vp: Viewport = from.get_viewport() if require_in_sight else null
	var visible_rect := vp.get_visible_rect() if vp != null else Rect2()
	var canvas := vp.get_canvas_transform() if vp != null else Transform2D.IDENTITY

	for node in from.get_tree().get_nodes_in_group(group):
		if not node is Node2D:
			continue

		var candidate := node as Node2D
		if not is_live_candidate(candidate):
			continue
		if require_in_sight and vp != null:
			var screen_pos: Vector2 = canvas * candidate.global_position
			if not visible_rect.has_point(screen_pos):
				continue

		var dist_sq := origin.distance_squared_to(candidate.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = candidate

	return nearest

static func is_live_candidate(candidate: Node2D) -> bool:
	# Pooled corpses stay in the group but are hidden. Do not require
	# physics_processing: co-op enemy ghosts are StaticBody2D copies and
	# would fail that check, so joiners never found a target.
	if not candidate.visible or not candidate.is_inside_tree():
		return false

	var health := candidate.get_node_or_null("HealthComponent") as HealthComponent
	if health != null and health.is_dead:
		return false
	return true

func _attack(target: Node2D) -> void:
	AudioManager.play_sfx(_resolve_weapon_hit_sfx_id())

	# Tell the wielder a weapon went off. Duck-typed so this works for the
	# player and for anything else that ends up holding a weapon. The wielder
	# does not animate — the swing below is the whole attack, on the weapon.
	if _owner_body != null and _owner_body.has_method("on_weapon_attack"):
		_owner_body.on_weapon_attack(target)

	if _visual != null:
		_visual.play_swing(data.weapon_class)

	# Order matters: Trap pre-empts everything (it never attacks directly), Melee handles its
	# own cleave via the hitbox overlap even when also flagged AoE (War Cleaver), and pure AoE
	# (no Melee) gets the radius-burst path; anything left over fires a projectile.
	if (data.weapon_class & WeaponData.WeaponClass.DICE) != 0:
		_throw_dice(target)
	elif (data.weapon_class & WeaponData.WeaponClass.TRAP) != 0:
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
	if (c & WeaponData.WeaponClass.DICE) != 0: return "weapon_ranged"
	if (c & WeaponData.WeaponClass.RANGED) != 0: return "weapon_ranged"
	return "weapon_hit"

# Brotato-style melee: damage every live TargetGroup member within WeaponData.Range.
# Hitbox overlap alone was too small vs Range, so weapons "swung" without landing hits.
func _perform_melee_attack() -> void:
	if _owner_body == null or data == null:
		return

	var range = maxf(8.0, get_range())
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
		get_damage() * damage_multiplier * (crit_multiplier if is_crit else 1.0)))

	health.take_damage(final_damage, _owner_body)
	_record_damage(final_damage)
	if _owner_stats:
		_owner_stats.notify_damage_dealt(final_damage, body)
	_apply_on_hit_lifesteal(final_damage)

	if body is TargetDummy and data.knockback > 0.0:
		var dummy = body as TargetDummy
		var push_dir = (dummy.global_position - _owner_body.global_position).normalized()
		dummy.apply_knockback(push_dir * data.knockback)

	return true

# WeaponClass.DICE (Bone Dice): casts a pair of dice on the floor. One die rolls how many
# enemies are hit, the other rolls the damage each of them takes; both are decided here and
# handed to the DiceCast, which plays the throw and calls back when the dice settle. The
# damage deliberately lands on the settle, not on the throw — a hit that happens before the
# numbers come up is a hit that came from nothing.
func _throw_dice(target: Node2D) -> void:
	var luck: float = _owner_stats.luck if _owner_stats else 0.0
	var sides := DiceCast.sides_for_luck(luck, data.dice_base_sides)
	var bonus := DiceCast.roll_bonus_for_luck(luck)

	var target_count := DiceCast.roll(sides, bonus)
	var damage_pips := DiceCast.roll(sides, bonus)
	# The damage die shows the hit that will land (pips × this weapon's damage, plus
	# the wielder's global multipliers). Crits and per-target bonuses still roll at
	# settle, so the face is the typical hit, not every possible one.
	var display_damage := _dice_display_damage(damage_pips)

	var cast := DiceCast.new()
	cast.name = "DiceCast"
	# Parented to the arena, not to this weapon: the dice stay where they landed while
	# the Jester keeps running, which is the whole point of throwing them on the floor.
	var host: Node = get_tree().current_scene if get_tree() != null else null
	if host == null:
		return
	host.add_child(cast)

	cast.resolved.connect(func(count: int, pips: int): _resolve_dice(count, pips))
	cast.begin(_spawn_point.global_position, target.global_position, target_count, damage_pips, display_damage)

# Face value for the damage die: pips × per-pip weapon damage × wielder multipliers.
# Matches `_resolve_dice` before crit and per-target bonuses (undead, etc.).
func _dice_display_damage(damage_pips: int) -> int:
	var pips: float = float(maxi(1, damage_pips))
	return maxi(1, roundi(get_damage() * pips * _compute_damage_multiplier(null)))

# Applies one settled throw: the nearest `target_count` live enemies in range each take
# `damage_pips` times this weapon's per-pip damage.
func _resolve_dice(target_count: int, damage_pips: int) -> void:
	if _owner_body == null or not is_instance_valid(_owner_body) or data == null:
		return

	var reach := get_range()
	var reach_sq := reach * reach
	var origin: Vector2 = _owner_body.global_position

	var candidates: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(target_group):
		if not node is Node2D:
			continue
		var body := node as Node2D
		if not is_live_candidate(body):
			continue
		if origin.distance_squared_to(body.global_position) > reach_sq:
			continue
		candidates.append(body)

	candidates.sort_custom(func(a: Node2D, b: Node2D):
		return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))

	var crit_chance: float = data.crit_chance + (_owner_stats.extra_crit_chance if _owner_stats else 0.0)
	var crit_multiplier: float = data.crit_multiplier + (_owner_stats.extra_crit_multiplier if _owner_stats else 0.0)
	var pips: float = float(maxi(1, damage_pips))

	for i in range(mini(target_count, candidates.size())):
		var body := candidates[i]
		var health := body.get_node_or_null("HealthComponent") as HealthComponent
		if health == null or health.is_dead:
			continue

		var is_crit: bool = randf() < crit_chance
		var multiplier := _compute_damage_multiplier(body)
		var final_damage: int = maxi(1, roundi(
			get_damage() * pips * multiplier * (crit_multiplier if is_crit else 1.0)))

		health.take_damage(final_damage, _owner_body)
		_record_damage(final_damage)
		if _owner_stats:
			_owner_stats.notify_damage_dealt(final_damage, body)
		_apply_on_hit_lifesteal(final_damage)

# Spawns Data.ProjectileCount pooled projectiles fanned across Data.Spread degrees, aimed at target.
func _fire_projectiles(target: Node2D) -> void:
	if _projectile_pool == null:
		return

	var base_direction = (target.global_position - _spawn_point.global_position).normalized()
	var count = get_projectile_count()
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
			get_damage() * damage_multiplier,
			crit_chance,
			crit_multiplier,
			data.knockback,
			target_group,
			func(dealt: int, hit_body: Node2D):
				_record_damage(dealt)
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
	var radius = get_aoe_radius()
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
		var final_damage = roundi(get_damage() * damage_multiplier * (crit_multiplier if is_crit else 1.0))
		health.take_damage(final_damage, _owner_body)
		_record_damage(final_damage)
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
	var damage_multiplier = (_owner_stats.damage_multiplier * _owner_stats.difficulty_damage_multiplier) if _owner_stats else 1.0

	var trap = _trap_pool.acquire()
	trap.arm(
		_owner_body.global_position,
		_trap_pool,
		_owner_body,
		get_damage() * damage_multiplier,
		crit_chance,
		crit_multiplier,
		target_group,
		data.trap_root_duration_seconds,
		data.trap_lifetime_seconds,
		func(dealt: int, hit_body: Node2D):
			_record_damage(dealt)
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
		familiar_script.setup(_owner_body, data, _owner_stats, _record_damage)

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
func _compute_damage_multiplier(target: Node2D = null) -> float:
	var multiplier = _owner_stats.damage_multiplier if _owner_stats else 1.0
	multiplier *= _owner_stats.difficulty_damage_multiplier if _owner_stats else 1.0

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
