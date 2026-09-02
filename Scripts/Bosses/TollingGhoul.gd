extends Boss
class_name TollingGhoul

# The Tolling Ghoul — a corpse the size of a door dragging a cathedral bell on
# a chain. Three attacks, and each one asks the player for a different kind of
# movement, because a boss whose every answer is "walk backwards" is a boss you
# beat by holding one key:
#
#   quake_slam      bell overhead, straight down. Two rings: get out of the
#                   wide one, and never be caught in the small one.
#   bell_whirlwind  a ring is drawn around him, then he swings and CHASES with
#                   it. Outrun it — standing still anywhere is wrong.
#   toll_combo      three swings, each covering more ground than the last, the
#                   third a leap onto wherever the player was standing. Each
#                   dodge has to be bigger than the one before it.
#
# The wind-ups track the player and then lock for the last stretch, the same
# contract the Blood Moon Alpha's leap uses: the decal is a promise, and the
# hit keeps it. Tracking for the whole wind-up would make the attacks
# undodgeable; not tracking at all makes them free.

# --- quake_slam -------------------------------------------------------------
# How far in front of himself he brings the bell down.
const SLAM_REACH := 80.0
# Last stretch of the wind-up, during which the rings stop following.
const SLAM_LOCK_SECONDS := 0.32
# Standing in the crater is meant to be a mistake worth remembering.
const EPICENTER_DAMAGE_MULTIPLIER := 3.0
const QUAKE_FISSURES := 11
const QUAKE_LIFETIME := 2.4

# --- bell_whirlwind ---------------------------------------------------------
const WHIRL_SPEED_MULTIPLIER := 1.55
# Gap between ticks while the player is inside the ring. Long enough that
# brushing the edge is survivable, short enough that living in it is not.
const WHIRL_HIT_INTERVAL := 0.45
# The spin row is four frames at 16 fps. Re-triggered a hair early so the
# animator never gets to finish it and drop back to a walk cycle mid-swing.
const SPIN_CYCLE := 0.24

# --- toll_combo -------------------------------------------------------------
const COMBO_REACH := 70.0
# Wind-up in front of each of the first two swings; also the rhythm between
# them, since one swing's telegraph is the previous swing's recovery.
const COMBO_TELEGRAPH := 0.3
# Each swing covers this much more ground, and hits this much harder, than the
# one before it.
const COMBO_GROWTH := 1.45
const COMBO_DAMAGE_GROWTH := 1.25
const COMBO_LEAP_WINDUP := 0.5
const COMBO_LEAP_LOCK := 0.14
const LEAP_TRAVEL_SECONDS := 0.34
const LEAP_HOP_HEIGHT := 66.0
const COMBO_RECOVERY := 0.5

# What each attack is worth on the roll. The attack he just used is excluded
# outright rather than merely made unlikely — with a pool of three, two
# whirlwinds in a row is most of the fight spent watching one move.
const ATTACK_WEIGHTS := {
	"quake_slam": 1.4,
	"toll_combo": 1.2,
	"bell_whirlwind": 1.0,
}

enum ComboStage {
	NONE,
	SWING,
	LEAP_WINDUP,
	LEAP_TRAVEL,
}

# Where the bell is coming down, and the two radii the hit is resolved with.
# Held on the boss rather than read back off the decals: a telegraph frees
# itself on its own clock, usually a frame before the wind-up ends.
var _slam_center: Vector2
var _slam_outer: BossAoeTelegraph
var _slam_inner: BossAoeTelegraph
var _slam_attack: BossAttackPatternData

var _whirl_remaining: float
var _whirl_radius: float
var _whirl_damage: int
var _whirl_hit_cooldown: float
var _whirl_spin_cooldown: float
var _whirl_aura: BossWhirlAura

var _combo_stage: ComboStage = ComboStage.NONE
var _combo_index: int
var _combo_timer: float
var _combo_attack: BossAttackPatternData
var _combo_center: Vector2
var _combo_radius: float
var _combo_damage: int
var _combo_telegraph: BossAoeTelegraph
var _leap_from: Vector2
var _leap_target: Vector2
var _leap_travelled: float

var _last_attack_id: String = ""

# ---------------------------------------------------------------------------
# Attack selection
# ---------------------------------------------------------------------------
func pick_attack() -> BossAttackPatternData:
	var phase := get_current_phase()
	if phase == null or phase.attacks == null or phase.attacks.is_empty():
		return null

	var total := 0.0
	for attack: BossAttackPatternData in phase.attacks:
		total += _attack_weight(attack)

	if total <= 0.0:
		# Only reachable when the no-repeat rule excluded the whole pool, i.e.
		# a phase with one attack in it. Take it again.
		_last_attack_id = ""
		return super.pick_attack()

	var roll := randf() * total
	for attack: BossAttackPatternData in phase.attacks:
		roll -= _attack_weight(attack)
		if roll <= 0.0:
			return attack

	return phase.attacks[phase.attacks.size() - 1]

func _attack_weight(attack: BossAttackPatternData) -> float:
	if attack == null:
		return 0.0

	if attack.attack_id == _last_attack_id:
		return 0.0

	return ATTACK_WEIGHTS.get(attack.attack_id, 1.0)

# ---------------------------------------------------------------------------
# Telegraphs
# ---------------------------------------------------------------------------
func begin_telegraph(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null or player == null:
		return

	# A wind-up that never resolved — the player died mid-cast — would
	# otherwise hand stale aim to the next attack.
	_clear_slam_aim()

	match attack.attack_id:
		"quake_slam":
			_begin_slam_telegraph(attack, player)

		"bell_whirlwind":
			# Centred on him and damage-free: this is the reach he is about to
			# start swinging, not a spot that is about to explode.
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, attack.radius, attack.windup_seconds, 0, self, false)

		"toll_combo":
			# Only the first swing is drawn here; the rest of the combo draws
			# itself as it goes, which is what makes the growth readable.
			active_telegraph = BossAoeTelegraph.spawn(
				self, _reach_point(player.global_position, COMBO_REACH), attack.radius,
				attack.windup_seconds, roundi(attack.damage), self, false)

		_:
			super.begin_telegraph(attack, player)

func _begin_slam_telegraph(attack: BossAttackPatternData, player: Node2D) -> void:
	_slam_attack = attack
	_slam_center = _reach_point(player.global_position, SLAM_REACH)

	# Outer first so the epicentre draws on top of it. Two shapes rather than
	# one, because "you will be hurt here" and "you will be flattened here" are
	# different pieces of news.
	_slam_outer = BossAoeTelegraph.spawn(
		self, _slam_center, attack.radius, attack.windup_seconds, 0, self, false)
	_slam_inner = BossAoeTelegraph.spawn(
		self, _slam_center, _epicenter_radius(attack), attack.windup_seconds,
		0, self, false)
	active_telegraph = _slam_inner

# The slam tracks the player while he hauls the bell up, then locks. Aiming
# once at the start would let the player simply walk away from it; aiming right
# up to the hit would make it impossible to leave.
func process_windup(delta: float, player: Node2D, has_live_target: bool) -> void:
	if _slam_attack != null and player != null and windup_remaining > SLAM_LOCK_SECONDS:
		_slam_center = _reach_point(player.global_position, SLAM_REACH)
		if _slam_outer != null and is_instance_valid(_slam_outer):
			_slam_outer.global_position = _slam_center

		if _slam_inner != null and is_instance_valid(_slam_inner):
			_slam_inner.global_position = _slam_center

		face_toward(player.global_position)

	super.process_windup(delta, player, has_live_target)

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------
func execute_attack(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null or player == null:
		return

	face_toward(player.global_position)
	_last_attack_id = attack.attack_id

	match attack.attack_id:
		"quake_slam":
			_execute_quake_slam(attack, player)
		"bell_whirlwind":
			_execute_whirlwind(attack)
		"toll_combo":
			_execute_toll_combo(attack, player)
		_:
			super.execute_attack(attack, player)

	remember_attack_cooldown(attack)

func _execute_quake_slam(attack: BossAttackPatternData, player: Node2D) -> void:
	var center := _slam_center
	if _slam_attack == null:
		center = _reach_point(player.global_position, SLAM_REACH)

	var epicenter := _epicenter_radius(attack)
	_clear_slam_aim()

	BossGroundQuake.spawn(self, center, attack.radius, epicenter, QUAKE_FISSURES,
		attack.duration if attack.duration > 0.0 else QUAKE_LIFETIME)
	_resolve_quake_hit(center, attack.radius, epicenter, roundi(attack.damage))

# Caught in the crater is a different event from caught by the shockwave, so it
# is a different number rather than the same one applied twice.
func _resolve_quake_hit(center: Vector2, outer: float, epicenter: float, damage: int) -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	var distance := center.distance_to(player.global_position)
	if distance <= epicenter:
		apply_damage_to_player(maxi(1, roundi(damage * EPICENTER_DAMAGE_MULTIPLIER)))
	elif distance <= outer:
		apply_damage_to_player(damage)

func _execute_whirlwind(attack: BossAttackPatternData) -> void:
	_whirl_radius = attack.radius
	_whirl_damage = roundi(attack.damage)
	_whirl_remaining = attack.duration if attack.duration > 0.0 else 2.4
	# He swings through the first target immediately — the ring was the warning.
	_whirl_hit_cooldown = 0.0
	_whirl_spin_cooldown = 0.0
	_whirl_aura = BossWhirlAura.attach(self, _whirl_radius)

func _execute_toll_combo(attack: BossAttackPatternData, player: Node2D) -> void:
	_combo_attack = attack
	_combo_index = 0
	_begin_combo_swing(player)

# ---------------------------------------------------------------------------
# Recovery: where the whirlwind and the combo actually live
#
# Both are multi-second performances, and the base state machine only has room
# for one instant of damage per attack. Running them out of RECOVER, and
# refusing to leave it until they are done, is what stops the boss starting a
# second attack on top of the one it is still swinging.
# ---------------------------------------------------------------------------
func process_recover(delta: float, player: Node2D, has_live_target: bool) -> void:
	if _whirl_remaining > 0.0:
		_process_whirlwind(delta, player)
		return

	if _combo_stage != ComboStage.NONE:
		_process_combo(delta, player)
		return

	super.process_recover(delta, player, has_live_target)

func _process_whirlwind(delta: float, player: Node2D) -> void:
	_whirl_remaining -= delta

	# The animator would drop back to a walk the moment the spin row ends, so
	# the swing is restarted a hair before it can.
	_whirl_spin_cooldown -= delta
	if _whirl_spin_cooldown <= 0.0 and sprite_animator != null:
		sprite_animator.play_named("attack_spin")
		_whirl_spin_cooldown = SPIN_CYCLE

	if player != null:
		var to_player := player.global_position - global_position
		if to_player.length_squared() > 0.0001:
			velocity = to_player.normalized() * get_move_speed() * get_phase_move_multiplier() * WHIRL_SPEED_MULTIPLIER
		else:
			velocity = Vector2.ZERO

		_whirl_hit_cooldown -= delta
		if _whirl_hit_cooldown <= 0.0 and to_player.length() <= _whirl_radius:
			apply_damage_to_player(_whirl_damage)
			_whirl_hit_cooldown = WHIRL_HIT_INTERVAL
	else:
		velocity = Vector2.ZERO

	if _whirl_remaining > 0.0:
		return

	_end_whirlwind()
	# He is dizzy and wide open, which is the payment for having chased.
	recover_remaining = 0.55

func _end_whirlwind() -> void:
	_whirl_remaining = 0.0
	velocity = Vector2.ZERO
	if _whirl_aura != null and is_instance_valid(_whirl_aura):
		_whirl_aura.close()

	_whirl_aura = null

func _process_combo(delta: float, player: Node2D) -> void:
	_combo_timer -= delta

	match _combo_stage:
		ComboStage.SWING:
			velocity = Vector2.ZERO
			if _combo_timer <= 0.0:
				_resolve_combo_swing(player)

		ComboStage.LEAP_WINDUP:
			velocity = Vector2.ZERO
			# The landing zone follows until the last moment, then commits.
			if player != null and _combo_timer > COMBO_LEAP_LOCK:
				_leap_target = _leap_landing(player.global_position)
				if _combo_telegraph != null and is_instance_valid(_combo_telegraph):
					_combo_telegraph.global_position = _leap_target

				face_toward(_leap_target)

			if _combo_timer <= 0.0:
				_begin_leap_travel()

		ComboStage.LEAP_TRAVEL:
			_process_leap_travel(delta)

		_:
			velocity = Vector2.ZERO

func _begin_combo_swing(player: Node2D) -> void:
	_combo_stage = ComboStage.SWING
	_combo_timer = COMBO_TELEGRAPH
	_combo_radius = _combo_step_radius(_combo_index)
	_combo_damage = _combo_step_damage(_combo_index)

	var aim := player.global_position if player != null else global_position + Vector2.RIGHT * COMBO_REACH
	_combo_center = _reach_point(aim, COMBO_REACH)
	face_toward(aim)

	# The first swing's zone was already drawn by begin_telegraph, so only the
	# follow-ups need one of their own.
	if _combo_index > 0:
		_combo_telegraph = BossAoeTelegraph.spawn(
			self, _combo_center, _combo_radius, COMBO_TELEGRAPH, _combo_damage, self, false)

func _resolve_combo_swing(player: Node2D) -> void:
	_combo_telegraph = null
	if sprite_animator != null:
		sprite_animator.play_attack()

	apply_damage_in_radius(_combo_center, _combo_radius, _combo_damage)

	_combo_index += 1
	# Two swings, then the leap. count is the whole combo length, so a designer
	# who writes 4 gets three swings and a leap.
	var swings := maxi(2, _combo_attack.count if _combo_attack != null else 3) - 1
	if _combo_index < swings:
		_begin_combo_swing(player)
	else:
		_begin_combo_leap(player)

func _begin_combo_leap(player: Node2D) -> void:
	_combo_stage = ComboStage.LEAP_WINDUP
	_combo_timer = COMBO_LEAP_WINDUP
	_combo_radius = _combo_step_radius(_combo_index)
	_combo_damage = _combo_step_damage(_combo_index)
	_leap_target = _leap_landing(player.global_position if player != null else global_position)

	_combo_telegraph = BossAoeTelegraph.spawn(
		self, _leap_target, _combo_radius, COMBO_LEAP_WINDUP, _combo_damage, self, false)
	face_toward(_leap_target)

func _begin_leap_travel() -> void:
	_combo_stage = ComboStage.LEAP_TRAVEL
	_combo_timer = LEAP_TRAVEL_SECONDS
	_combo_telegraph = null
	_leap_from = global_position
	_leap_travelled = 0.0
	if sprite_animator != null:
		sprite_animator.play_named("dash")

func _process_leap_travel(delta: float) -> void:
	_leap_travelled += delta
	var t := clampf(_leap_travelled / LEAP_TRAVEL_SECONDS, 0.0, 1.0)

	# Driven through velocity rather than by setting global_position, so a wall
	# stops the leap the same way it stops anything else.
	var want := _leap_from.lerp(_leap_target, t)
	var step := want - global_position
	velocity = step / maxf(delta, 0.0001)

	# The hop is drawn, not simulated: the body's shadow stays on the floor
	# where the landing zone is, and only the sprite leaves the ground.
	_set_sprite_hop(sin(PI * t) * LEAP_HOP_HEIGHT)

	if _combo_timer > 0.0:
		return

	_land_leap()

func _land_leap() -> void:
	_set_sprite_hop(0.0)
	velocity = Vector2.ZERO
	_combo_stage = ComboStage.NONE

	if sprite_animator != null:
		sprite_animator.play_attack()

	# He comes down bell-first, so the landing cracks the floor the same way the
	# slam does — smaller, and without the lethal core.
	BossGroundQuake.spawn(self, _leap_target, _combo_radius,
		_combo_radius * 0.3, 5, 1.4)
	apply_damage_in_radius(_leap_target, _combo_radius, _combo_damage)

	_combo_attack = null
	recover_remaining = COMBO_RECOVERY

# ---------------------------------------------------------------------------
# Facing
# ---------------------------------------------------------------------------
# Mid-leap and mid-spin the body leads. Looking back at the player while
# sailing past them is the moonwalk the base class exists to avoid, and a
# spinning boss should face the way it is travelling.
func resolve_facing_x(player: Node2D) -> float:
	if _combo_stage == ComboStage.LEAP_TRAVEL:
		return _leap_target.x - _leap_from.x

	if _whirl_remaining > 0.0 and absf(velocity.x) > 1.0:
		return velocity.x

	return super.resolve_facing_x(player)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func initialize(data: BossData) -> void:
	super.initialize(data)
	_reset_performances()

func on_phase_entered(phase_index: int, previous_phase_index: int = -1) -> void:
	super.on_phase_entered(phase_index, previous_phase_index)
	if phase_index >= 1 and previous_phase_index >= 0:
		# The bell cracks and he stops pacing himself. Announced with a ring so
		# the change is felt on the floor, not just read in the log.
		BossAoeTelegraph.spawn(self, global_position, 110.0, 0.45, 0, self, false)

func _on_died(source: Node) -> void:
	_reset_performances()
	super._on_died(source)

func _reset_performances() -> void:
	_end_whirlwind()
	_combo_stage = ComboStage.NONE
	_combo_attack = null
	_combo_telegraph = null
	_clear_slam_aim()
	_set_sprite_hop(0.0)

func _clear_slam_aim() -> void:
	_slam_attack = null
	_slam_outer = null
	_slam_inner = null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# A point `reach` in front of him, on the line to `target`. The bell lands
# where he can swing it, not on top of whatever he happens to be looking at.
func _reach_point(target: Vector2, reach: float) -> Vector2:
	var to_target := target - global_position
	var distance := to_target.length()
	if distance <= 0.0001:
		return global_position + Vector2.RIGHT * reach

	return global_position + to_target / distance * minf(reach, distance)

# The leap is capped by the attack's range so he cannot cross the arena with
# it, and never lands short of a stride or he ends up standing on himself.
func _leap_landing(target: Vector2) -> Vector2:
	var reach := _combo_attack.range if _combo_attack != null and _combo_attack.range > 0.0 else 260.0
	var to_target := target - global_position
	var distance := to_target.length()
	if distance <= 0.0001:
		return global_position

	return global_position + to_target / distance * clampf(distance, 40.0, reach)

func _combo_step_radius(index: int) -> float:
	var base := _combo_attack.radius if _combo_attack != null else 70.0
	return base * pow(COMBO_GROWTH, index)

func _combo_step_damage(index: int) -> int:
	var base := _combo_attack.damage if _combo_attack != null else 18.0
	return maxi(1, roundi(base * pow(COMBO_DAMAGE_GROWTH, index)))

func _epicenter_radius(attack: BossAttackPatternData) -> float:
	# `range` is the epicentre on this attack. Clamped under the outer radius
	# so a mistuned resource cannot make the whole zone lethal.
	var epicenter := attack.range if attack.range > 0.0 else attack.radius * 0.34
	return clampf(epicenter, 16.0, attack.radius * 0.6)

func _set_sprite_hop(height: float) -> void:
	if sprite_animator == null:
		return

	var sprite := sprite_animator.get_sprite()
	if sprite != null:
		sprite.position.y = -height
