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
const POUNCE_CONTACT_RADIUS := 46.0
# Last stretch of the wind-up, during which the lane stops following and just
# fills. Without it the leap lands wherever the player is standing at the
# instant it fires, which is not an attack anyone can read.
const POUNCE_LOCK_SECONDS := 0.18
# Safety cap on a leap: a charge blocked by a wall has to end sometime.
const POUNCE_MAX_SECONDS := 0.9
const RAMPAGE_WINDUP := 0.32
const RAMPAGE_INTERVAL := 0.44
const HOWL_HASTE_SECONDS := 6.0
const HOWL_HASTE_MOVE := 1.35
const HOWL_HASTE_COOLDOWN := 0.7

# The leap is his signature, so it comes up far more often than anything else,
# and it always sets up a second move: land on the player, then swipe.
const ATTACK_WEIGHTS := {
	"pounce": 3.2,
	"claw_combo": 1.4,
	"rampage": 1.0,
	"howl": 0.6,
}
# Gap between the leap landing and the follow-up it bought him. Long enough to
# read as two moves, short enough that stepping out from under him is a dodge
# rather than a stroll.
const FOLLOW_UP_DELAY := 0.15

# How close he wants to be. Inside this he circles; outside he closes. He never
# walks away from the player — that read as him losing interest mid-fight.
const PROWL_RANGE := 96.0
const PROWL_RANGE_FRENZY := 70.0
const STEER_RESPONSE := 8.0

const WOLF_SHEET := "res://Assets/sprites/enemies/dire_wolf/dire_wolf.png"

var _frenzy_announced: bool

# Lunge state. Runs during RECOVER so the boss visibly travels the lane it
# just drew instead of teleporting to the end of it.
var _charge_remaining: float
var _charge_direction: Vector2 = Vector2.RIGHT
# Where the drawn lane ends. The leap stops here rather than running for a
# fixed time, so the distance he covers is the distance he showed.
var _charge_target: Vector2
var _charge_damage: int
var _charge_hit: bool

# The lane currently being drawn for a leap, and the attack that owns it, so
# the wind-up can keep re-aiming both at the player.
var _pounce_lane: BossAoeTelegraph
var _pounce_attack: BossAttackPatternData
# Where that lane points, held on the boss rather than read back off the decal.
# The telegraph frees itself on its own clock, which is usually a frame or two
# before the physics wind-up ends, and reading a freed node put the leap back
# on a fresh aim — the original bug in a new hat.
var _pounce_aim: Vector2 = Vector2.RIGHT
var _pounce_reach: float

var _haste_remaining: float

# Set when a leap resolves, consumed by the next attack pick: the follow-up is
# never another leap, and it comes almost immediately.
var _chain_follow_up: bool

# Which way he circles, flipped now and then so he does not tread one rut.
var _orbit_sign: float = 1.0
var _orbit_flip_in: float = 2.0

func _process(delta: float) -> void:
	if _haste_remaining > 0.0:
		_haste_remaining -= delta

func get_phase_move_multiplier() -> float:
	var base = super.get_phase_move_multiplier()
	return base * HOWL_HASTE_MOVE if _haste_remaining > 0.0 else base

func get_phase_cooldown_multiplier() -> float:
	var base = super.get_phase_cooldown_multiplier()
	return base * HOWL_HASTE_COOLDOWN if _haste_remaining > 0.0 else base

# Weighted pick with the leap on top. The base class rolls uniformly, which
# spread his best move thin across three others.
func pick_attack() -> BossAttackPatternData:
	var phase := get_current_phase()
	if phase == null or phase.attacks == null or phase.attacks.is_empty():
		return null

	var chaining := _chain_follow_up
	_chain_follow_up = false

	var total := 0.0
	for attack: BossAttackPatternData in phase.attacks:
		total += _attack_weight(attack, chaining)

	if total <= 0.0:
		# Only reachable when the follow-up filter excluded everything, i.e. a
		# phase whose whole pool is leaps. Fall back to the plain roll.
		return super.pick_attack()

	var roll := randf() * total
	for attack: BossAttackPatternData in phase.attacks:
		roll -= _attack_weight(attack, chaining)
		if roll <= 0.0:
			return attack

	return phase.attacks[phase.attacks.size() - 1]

func _attack_weight(attack: BossAttackPatternData, chaining: bool) -> float:
	if attack == null:
		return 0.0

	# A leap into a leap is just a longer leap, and it drags him off the player.
	if chaining and attack.attack_id == "pounce":
		return 0.0

	return ATTACK_WEIGHTS.get(attack.attack_id, 1.0)

# Paced off the fastest tool in the phase rather than the one just used. The
# base class reuses the last attack's cooldown, so a single 7s howl handed the
# player a free lap of the arena.
func get_next_attack_cooldown() -> float:
	if _chain_follow_up:
		return FOLLOW_UP_DELAY

	var phase := get_current_phase()
	if phase == null or phase.attacks == null or phase.attacks.is_empty():
		return super.get_next_attack_cooldown()

	var fastest := phase.attacks[0].cooldown_seconds
	for attack: BossAttackPatternData in phase.attacks:
		if attack != null:
			fastest = minf(fastest, attack.cooldown_seconds)

	return maxf(0.3, fastest * get_phase_cooldown_multiplier() * randf_range(0.85, 1.1))

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

	# The leap's aim belongs to the leap. A wind-up that never resolved — the
	# player died mid-cast, say — would otherwise leave it set and hand a stale
	# heading to the next one.
	if attack.attack_id != "pounce":
		_pounce_lane = null
		_pounce_attack = null

	var to_player = player.global_position - global_position
	var facing = to_player.normalized() if to_player.length_squared() > 0.0001 else Vector2.RIGHT

	match attack.attack_id:
		"claw_combo":
			active_telegraph = BossAoeTelegraph.spawn_cone(
				self, global_position, facing, attack.radius, CLAW_ARC_DEGREES,
				attack.windup_seconds, roundi(attack.damage), self, false)

		"pounce":
			_pounce_attack = attack
			_pounce_aim = facing
			_pounce_reach = _pounce_length(attack, to_player)
			_pounce_lane = BossAoeTelegraph.spawn_lane(
				self, global_position, facing, _pounce_reach,
				POUNCE_LANE_WIDTH, attack.windup_seconds, roundi(attack.damage), self, false)
			active_telegraph = _pounce_lane

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

# The lane follows the player while he gathers himself, then locks for the last
# stretch. Aiming once at the start was the bug: he drew a lane one way and
# leapt another, because the leap re-aimed at execution time and the decal did
# not.
func process_windup(delta: float, player: Node2D, has_live_target: bool) -> void:
	# Track while he gathers himself, then lock for the last stretch. Aiming
	# once at the start was the bug: he drew a lane one way and leapt another,
	# because the leap re-aimed at execution time and the decal did not.
	if _pounce_attack != null and player != null and windup_remaining > POUNCE_LOCK_SECONDS:
		var to_player := player.global_position - global_position
		if to_player.length_squared() > 0.0001:
			_pounce_aim = to_player.normalized()

		_pounce_reach = _pounce_length(_pounce_attack, to_player)
		if _pounce_lane != null and is_instance_valid(_pounce_lane):
			_pounce_lane.retarget(global_position, _pounce_aim, _pounce_reach)

		face_toward(player.global_position)

	super.process_windup(delta, player, has_live_target)

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
	# Straight off the aim the lane was drawn with, never a fresh look at the
	# player: the decal is the promise, and this is what keeps it.
	var facing := _pounce_aim
	var length := _pounce_reach
	if _pounce_attack == null:
		var to_player := player.global_position - global_position
		facing = to_player.normalized() if to_player.length_squared() > 0.0001 else Vector2.RIGHT
		length = _pounce_length(attack, to_player)

	_pounce_lane = null
	_pounce_attack = null
	_launch_charge(facing, length, roundi(attack.damage))
	# He lands next to the player with his weight already forward — the swipe
	# that follows is the point of the leap.
	_chain_follow_up = true

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
	_charge_target = global_position + direction * length
	# A time cap only, so a leap into a wall cannot run forever. The leap
	# actually ends on arrival, which is what makes the distance he covers
	# the distance the lane showed.
	_charge_remaining = minf(POUNCE_MAX_SECONDS, length / POUNCE_SPEED + 0.06)
	_charge_damage = damage
	_charge_hit = false
	# Anyone still standing on the drawn lane eats it immediately; the contact
	# check below only catches players who walk into him mid-leap.
	if _hit_lane(direction, length, POUNCE_LANE_WIDTH, damage):
		_charge_hit = true

# Mid-leap the body leads: he looks where he is going, not at the player he is
# about to sail past.
func resolve_facing_x(player: Node2D) -> float:
	if _charge_remaining > 0.0:
		return _charge_direction.x

	return super.resolve_facing_x(player)

func process_recover(delta: float, player: Node2D, has_live_target: bool) -> void:
	if _charge_remaining <= 0.0:
		super.process_recover(delta, player, has_live_target)
		return

	_charge_remaining -= delta
	recover_remaining -= delta

	var to_target := _charge_target - global_position
	var step := POUNCE_SPEED * delta
	if to_target.length() <= step:
		# Final stride: land exactly on the end of the lane. Divided by delta so
		# move_and_slide still resolves it as movement, which means a wall stops
		# him here the same way it would mid-leap.
		velocity = to_target / maxf(delta, 0.0001)
		_charge_remaining = 0.0
	elif _charge_remaining <= 0.0:
		# Time cap hit, so something is in the way. Stop where he actually is
		# rather than snapping to a point he never reached.
		velocity = Vector2.ZERO
	else:
		velocity = to_target.normalized() * POUNCE_SPEED

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

	# He arcs in on his prey and circles once he is on top of it. He never
	# retreats: an earlier version backed off inside its own attack range,
	# which read as the wolf losing its nerve and walking off mid-fight.
	var speed = get_move_speed() * get_phase_move_multiplier()
	var to_player = player.global_position - global_position
	var dist = to_player.length()
	var dir = to_player / dist if dist > 0.001 else Vector2.RIGHT

	_orbit_flip_in -= delta
	if _orbit_flip_in <= 0.0:
		_orbit_sign = -_orbit_sign
		_orbit_flip_in = randf_range(1.6, 3.2)

	var tangent = Vector2(-dir.y, dir.x) * _orbit_sign
	var prowl = PROWL_RANGE_FRENZY if current_phase_index >= 1 else PROWL_RANGE
	var desired: Vector2
	if dist > prowl:
		desired = (dir + tangent * 0.35).normalized() * speed
	else:
		desired = tangent * speed * 0.7

	# Steered rather than snapped, so crossing the prowl boundary does not
	# make him stutter between closing and circling.
	velocity = velocity.lerp(desired, clampf(delta * STEER_RESPONSE, 0.0, 1.0))

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
