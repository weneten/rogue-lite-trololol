extends Boss
class_name BloodMoonAlpha

# The Blood Moon Alpha — the wave 10 werewolf.
#
# Four abilities, and every one of them is telegraphed with a shape that
# matches how it actually hits, because the whole fight is a dodging puzzle:
#
#   claw_combo  cone in front       step out of the arc, or behind him
#   pounce      lane to the player  step sideways off the line
#   howl        ring around him     leave melee before it lands
#   rampage     three lanes         phase 2 only; keep moving
#
# A red circle on the floor for all four would tell the player that something
# is coming but never what — a boss whose attacks cannot be told apart is a
# boss you can only fight by running away from.

const CLAW_ARC_DEGREES := 105.0
const POUNCE_LANE_WIDTH := 52.0
const POUNCE_SPEED := 760.0
const POUNCE_DURATION := 0.28
const POUNCE_CONTACT_RADIUS := 46.0
const RAMPAGE_WINDUP := 0.32
const RAMPAGE_INTERVAL := 0.44
const HOWL_HASTE_SECONDS := 6.0
const HOWL_HASTE_MOVE := 1.35
const HOWL_HASTE_COOLDOWN := 0.7

const WOLF_SHEET := "res://Assets/sprites/enemies/dire_wolf/dire_wolf.png"

var _frenzy_announced: bool

# Lunge state. Runs during RECOVER so the boss visibly travels the lane it
# just drew instead of teleporting to the end of it.
var _charge_remaining: float
var _charge_direction: Vector2 = Vector2.RIGHT
var _charge_damage: int
var _charge_hit: bool

var _haste_remaining: float

func _process(delta: float) -> void:
	if _haste_remaining > 0.0:
		_haste_remaining -= delta

func get_phase_move_multiplier() -> float:
	var base = super.get_phase_move_multiplier()
	return base * HOWL_HASTE_MOVE if _haste_remaining > 0.0 else base

func get_phase_cooldown_multiplier() -> float:
	var base = super.get_phase_cooldown_multiplier()
	return base * HOWL_HASTE_COOLDOWN if _haste_remaining > 0.0 else base

func on_phase_entered(phase_index: int, previous_phase_index: int = -1) -> void:
	super.on_phase_entered(phase_index, previous_phase_index)
	if phase_index >= 1 and not _frenzy_announced:
		_frenzy_announced = true
		print("[Boss] The Blood Moon Alpha breaks into Blood Frenzy!")
		# Free haste on the transition so the phase change is felt, not just read.
		_haste_remaining = maxf(_haste_remaining, HOWL_HASTE_SECONDS)
		BossAoeTelegraph.spawn(self, global_position, 96.0, 0.4, 0, self, false)

# ---------------------------------------------------------------------------
# Telegraphs
# ---------------------------------------------------------------------------
func begin_telegraph(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null or player == null:
		return

	var to_player = player.global_position - global_position
	var facing = to_player.normalized() if to_player.length_squared() > 0.0001 else Vector2.RIGHT

	match attack.attack_id:
		"claw_combo":
			active_telegraph = BossAoeTelegraph.spawn_cone(
				self, global_position, facing, attack.radius, CLAW_ARC_DEGREES,
				attack.windup_seconds, roundi(attack.damage), self, false)

		"pounce":
			active_telegraph = BossAoeTelegraph.spawn_lane(
				self, global_position, facing, _pounce_length(attack, to_player),
				POUNCE_LANE_WIDTH, attack.windup_seconds, roundi(attack.damage), self, false)

		"howl":
			# Centred on him and damage-free: the threat is the pack, not the noise.
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, attack.radius, attack.windup_seconds, 0, self, false)

		"rampage":
			# One wide fan covering the whole flurry, then a fresh lane per lunge.
			active_telegraph = BossAoeTelegraph.spawn_cone(
				self, global_position, facing, attack.range, 150.0,
				attack.windup_seconds, 0, self, false)

		_:
			super.begin_telegraph(attack, player)

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------
func execute_attack(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null or player == null:
		return

	face_toward(player.global_position)

	match attack.attack_id:
		"claw_combo":
			_execute_claw_combo(attack, player)
		"pounce":
			_execute_pounce(attack, player)
		"howl":
			_execute_howl(attack)
		"rampage":
			_execute_rampage(attack)
		_:
			super.execute_attack(attack, player)

	remember_attack_cooldown(attack)

# Two swipes: the first lands with the cone that was already drawn, the second
# is a short backhand with its own quick cone, so the follow-up is dodgeable
# rather than an unavoidable second tick of the same hit.
func _execute_claw_combo(attack: BossAttackPatternData, player: Node2D) -> void:
	var facing = _direction_to(player.global_position)
	_hit_cone(facing, attack.radius, CLAW_ARC_DEGREES, roundi(attack.damage))

	var tree = get_tree()
	if tree == null or attack.count <= 1:
		return

	tree.create_timer(0.16).timeout.connect(func():
		if not is_instance_valid(self) or state == BossState.DEAD:
			return

		var target = get_tree().get_first_node_in_group("Player") as Node2D
		if target == null:
			return

		BossAoeTelegraph.spawn_cone(
			self, global_position, _direction_to(target.global_position),
			attack.radius, CLAW_ARC_DEGREES, 0.22,
			maxi(1, roundi(attack.damage * 0.8)), self, true))

func _execute_pounce(attack: BossAttackPatternData, player: Node2D) -> void:
	var to_player = player.global_position - global_position
	var facing = to_player.normalized() if to_player.length_squared() > 0.0001 else Vector2.RIGHT
	var length = _pounce_length(attack, to_player)
	_launch_charge(facing, length, roundi(attack.damage))

func _execute_howl(attack: BossAttackPatternData) -> void:
	_haste_remaining = maxf(_haste_remaining, attack.duration if attack.duration > 0.0 else HOWL_HASTE_SECONDS)

	var count = maxi(1, attack.count)
	var wolf_health = maxi(6, roundi(attack.damage * 2.0))
	for i in range(count):
		var angle = TAU * i / count + randf_range(-0.25, 0.25)
		var offset = Vector2(attack.radius * 0.7, 0).rotated(angle)
		spawn_minion(
			global_position + offset,
			"Dire Wolf",
			Color.WHITE,
			wolf_health,
			186.0,
			maxf(3.0, attack.damage),
			0.8,
			WOLF_SHEET,
			1.7)

# Phase 2 flurry: several short lunges back to back, each with its own lane.
func _execute_rampage(attack: BossAttackPatternData) -> void:
	var steps = maxi(2, attack.count)
	# Hold the boss in recovery for the whole flurry so it cannot start a
	# second attack on top of its own.
	recover_remaining = maxf(recover_remaining, steps * RAMPAGE_INTERVAL + RAMPAGE_WINDUP)
	_rampage_step(0, steps, roundi(attack.damage), attack.range)

func _rampage_step(step: int, total: int, damage: int, max_range: float) -> void:
	if step >= total or not is_instance_valid(self) or state == BossState.DEAD:
		return

	var tree = get_tree()
	if tree == null:
		return

	var player = tree.get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	var to_player = player.global_position - global_position
	var facing = to_player.normalized() if to_player.length_squared() > 0.0001 else Vector2.RIGHT
	var length = clampf(to_player.length() + 40.0, 110.0, maxf(140.0, max_range))
	face_toward(player.global_position)

	BossAoeTelegraph.spawn_lane(
		self, global_position, facing, length, POUNCE_LANE_WIDTH,
		RAMPAGE_WINDUP, damage, self, false)

	tree.create_timer(RAMPAGE_WINDUP).timeout.connect(func():
		if not is_instance_valid(self) or state == BossState.DEAD:
			return

		if sprite_animator != null:
			sprite_animator.play_attack()

		_launch_charge(facing, length, damage)
		get_tree().create_timer(RAMPAGE_INTERVAL).timeout.connect(func():
			_rampage_step(step + 1, total, damage, max_range)))

# ---------------------------------------------------------------------------
# Charge
# ---------------------------------------------------------------------------
func _launch_charge(direction: Vector2, length: float, damage: int) -> void:
	_charge_direction = direction
	_charge_remaining = POUNCE_DURATION
	_charge_damage = damage
	_charge_hit = false
	# Anyone still standing on the drawn lane eats it immediately; the contact
	# check below only catches players who walk into him mid-leap.
	if _hit_lane(direction, length, POUNCE_LANE_WIDTH, damage):
		_charge_hit = true

func process_recover(delta: float, player: Node2D, has_live_target: bool) -> void:
	if _charge_remaining <= 0.0:
		super.process_recover(delta, player, has_live_target)
		return

	_charge_remaining -= delta
	recover_remaining -= delta
	velocity = _charge_direction * POUNCE_SPEED

	if not _charge_hit and player != null \
			and global_position.distance_to(player.global_position) <= POUNCE_CONTACT_RADIUS:
		_charge_hit = true
		apply_damage_to_player(_charge_damage, _life_drain())

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
func process_chase(delta: float, player: Node2D, has_live_target: bool) -> void:
	if not has_live_target or player == null:
		super.process_chase(delta, player, has_live_target)
		return

	# He circles his prey rather than walking into it, which keeps him out of
	# the player's melee range long enough for the telegraphs to matter.
	var speed = data.move_speed * get_phase_move_multiplier()
	var to_player = player.global_position - global_position
	var dist = to_player.length()
	var dir = to_player / dist if dist > 0.001 else Vector2.RIGHT
	var prowl = 92.0 if current_phase_index >= 1 else 130.0

	if dist < prowl * 0.75:
		velocity = -dir * speed * 0.8
	elif dist > prowl * 1.5:
		velocity = dir * speed
	else:
		velocity = (dir.rotated(PI * 0.5) * 0.85 + dir * 0.35).normalized() * speed * 0.9

	attack_cooldown_remaining -= delta
	if attack_cooldown_remaining <= 0:
		try_begin_attack(player)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _direction_to(point: Vector2) -> Vector2:
	var delta = point - global_position
	return delta.normalized() if delta.length_squared() > 0.0001 else Vector2.RIGHT

func _pounce_length(attack: BossAttackPatternData, to_player: Vector2) -> float:
	# Long enough to always overshoot the player a little, so backing straight
	# up never works and the sideways dodge is the answer.
	return clampf(to_player.length() + 50.0, 120.0, maxf(160.0, attack.range))

func _life_drain() -> float:
	return 0.25 if current_phase_index >= 1 else 0.0

func _hit_cone(facing: Vector2, radius: float, arc_degrees: float, damage: int) -> bool:
	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return false

	var local = player.global_position - global_position
	if local.length() > radius:
		return false

	if absf(rad_to_deg(facing.angle_to(local))) > arc_degrees * 0.5:
		return false

	apply_damage_to_player(damage, _life_drain())
	return true

func _hit_lane(facing: Vector2, length: float, width: float, damage: int) -> bool:
	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return false

	var local = player.global_position - global_position
	var along = local.dot(facing)
	if along < -width * 0.5 or along > length:
		return false

	if absf(local.dot(Vector2(-facing.y, facing.x))) > width * 0.5:
		return false

	apply_damage_to_player(damage, _life_drain())
	return true
