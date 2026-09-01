extends Boss
class_name CrimsonVoivode

# The Crimson Voivode — the wave 20 vampire.
#
# Phase 1, Crimson Court:
#   blood_aura   a temporary field carried on his body. Standing next to him
#                costs blood every 0.3s, and he drinks what it takes.
#   bat_swarm    called bats stoop on the player five times fast, then leave.
#   blood_pools  ground he takes away from you, ticking every 0.3s.
#
# Phase 2, Ascendant (below 30% HP): different artwork, double damage, and
#   shadow_step  he steps into the player's own shadow and comes back out of
#                it as a blood nova.
#
# The doubling is not implemented here: it is `damage_multiplier` on the phase
# resource, applied by Boss.apply_damage_to_player, which is why the pools he
# left on the floor before the transformation also get worse when it happens.

enum Step {
	GROUNDED,
	SINKING,
	SUBMERGED,
}

const AURA_DRAIN := 0.4

# Weighted selection, like the Alpha and the Tyrant. The base class rolls
# uniformly and, with four tools on one shared cooldown, that reliably gave
# runs of the same attack five and six deep.
const ATTACK_WEIGHTS := {
	"shadow_step": 1.6,
	"blood_pools": 1.3,
	"bat_swarm": 1.2,
	"blood_aura": 1.0,
}
# What the attack he just used is worth on the next roll. Not zero — repeating
# is allowed, just not the default.
const REPEAT_DAMPING := 0.25

const SINK_SECONDS := 0.3
const SUBMERGED_SECONDS := 0.55
const NOVA_RINGS := 3
const NOVA_RING_SPACING := 0.12

# He is a caster: close enough to threaten, far enough that the fight is about
# his ground control rather than his fists.
const PREFERRED_RANGE := 175.0
const RANGE_TOLERANCE := 50.0
const STEER_RESPONSE := 6.5

var _ascended: bool

var _step: Step = Step.GROUNDED
var _step_timer: float
var _step_target: Vector2
var _step_telegraph: BossAoeTelegraph
var _nova_damage: int
var _nova_radius: float

var _aura: BloodField

# Where the pools will land, decided when the markers go down. Recomputing them
# at execution time would have put the pools wherever the player had run to,
# which makes the markers a lie.
var _pool_spots: Array[Vector2] = []

# The sprite scale the animator configured, so sinking into the floor restores
# to the right size afterwards rather than to 1.
var _base_visual_scale: Vector2 = Vector2.ONE

var _strafe_sign: float = 1.0
var _strafe_flip_in: float = 2.0

var _last_attack_id: String = ""

func pick_attack() -> BossAttackPatternData:
	var phase := get_current_phase()
	if phase == null or phase.attacks == null or phase.attacks.is_empty():
		return null

	var total := 0.0
	for attack: BossAttackPatternData in phase.attacks:
		total += _attack_weight(attack)

	if total <= 0.0:
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

	var weight: float = ATTACK_WEIGHTS.get(attack.attack_id, 1.0)
	return weight * REPEAT_DAMPING if attack.attack_id == _last_attack_id else weight

func on_phase_entered(phase_index: int, previous_phase_index: int = -1) -> void:
	super.on_phase_entered(phase_index, previous_phase_index)
	if phase_index >= 1 and not _ascended:
		_ascended = true
		print("[Boss] The Crimson Voivode ascends — blood answers him now.")
		# The transformation is a free nova: the player gets pushed off him at
		# the exact moment he becomes twice as dangerous.
		_burst_nova(global_position, 150.0, roundi(data.contact_damage * 1.5), 3)

# ---------------------------------------------------------------------------
# Telegraphs
# ---------------------------------------------------------------------------
func begin_telegraph(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null or player == null:
		return

	match attack.attack_id:
		"blood_aura":
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, attack.radius, attack.windup_seconds, 0, self, false)

		"bat_swarm":
			# On him, not on the player: the bats are coming from him, and the
			# marker that matters is the one under each stoop.
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, 80.0, attack.windup_seconds, 0, self, false)

		"blood_pools":
			# One marker per pool, so the player can see the whole shape of the
			# ground he is about to lose. The spots are fixed here and reused
			# at execution.
			_pool_spots.clear()
			var count = maxi(1, attack.count)
			for i in range(count):
				var spot = _pool_spot(attack, player, i, count)
				_pool_spots.append(spot)
				var telegraph = BossAoeTelegraph.spawn(
					self, spot, attack.radius, attack.windup_seconds, 0, self, false)
				if i == 0:
					active_telegraph = telegraph

		"shadow_step":
			# Under the player's feet: that is literally where he is going.
			active_telegraph = BossAoeTelegraph.spawn(
				self, player.global_position, attack.radius, attack.windup_seconds,
				0, self, false)

		_:
			super.begin_telegraph(attack, player)

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------
func execute_attack(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null or player == null:
		return

	face_toward(player.global_position)
	_last_attack_id = attack.attack_id

	match attack.attack_id:
		"blood_aura":
			_execute_blood_aura(attack)
		"bat_swarm":
			_execute_bat_swarm(attack)
		"blood_pools":
			_execute_blood_pools(attack, player)
		"shadow_step":
			_execute_shadow_step(attack, player)
		_:
			super.execute_attack(attack, player)

	remember_attack_cooldown(attack)

func _execute_blood_aura(attack: BossAttackPatternData) -> void:
	if _aura != null and is_instance_valid(_aura):
		_aura.queue_free()

	_aura = BloodField.spawn_aura(
		self, self, attack.radius,
		maxi(1, roundi(attack.damage)),
		attack.duration if attack.duration > 0.0 else 5.0,
		self, AURA_DRAIN)

func _execute_bat_swarm(attack: BossAttackPatternData) -> void:
	VampireBatSwarm.summon(
		self, global_position,
		maxi(1, attack.count),
		maxi(1, roundi(attack.damage)),
		maxf(32.0, attack.radius),
		maxf(0.2, attack.speed) if attack.speed > 0.0 else 0.55,
		self)

func _execute_blood_pools(attack: BossAttackPatternData, player: Node2D) -> void:
	var spots := _pool_spots
	if spots.is_empty():
		var count = maxi(1, attack.count)
		for i in range(count):
			spots.append(_pool_spot(attack, player, i, count))

	for spot in spots:
		BloodField.spawn_pool(
			self, spot, attack.radius,
			maxi(1, roundi(attack.damage)),
			attack.duration if attack.duration > 0.0 else 8.0,
			self)

	_pool_spots = []

func _execute_shadow_step(attack: BossAttackPatternData, player: Node2D) -> void:
	_step_target = player.global_position
	_nova_damage = roundi(attack.damage)
	_nova_radius = maxf(60.0, attack.range if attack.range > 0.0 else attack.radius * 1.6)
	_begin_shadow_step()

# ---------------------------------------------------------------------------
# Shadow step
# ---------------------------------------------------------------------------
func _begin_shadow_step() -> void:
	var visual := sprite_animator.get_sprite() if sprite_animator != null else null
	if visual != null:
		_base_visual_scale = visual.scale

	_step = Step.SINKING
	_step_timer = SINK_SECONDS
	# Held open for the whole manoeuvre; arriving sets the real recovery.
	recover_remaining = 99.0
	velocity = Vector2.ZERO

	if sprite_animator != null:
		sprite_animator.play_named("dash")

func process_recover(delta: float, player: Node2D, has_live_target: bool) -> void:
	if _step == Step.GROUNDED:
		super.process_recover(delta, player, has_live_target)
		return

	velocity = Vector2.ZERO
	_step_timer -= delta

	match _step:
		Step.SINKING:
			_tick_sinking()
		Step.SUBMERGED:
			_tick_submerged(player)

func _tick_sinking() -> void:
	# Melts downward into his own shadow rather than fading on the spot.
	var sink := 1.0 - clampf(_step_timer / SINK_SECONDS, 0.0, 1.0)
	_set_visual_sink(sink)

	if _step_timer > 0.0:
		return

	_set_intangible(true)
	_step = Step.SUBMERGED
	_step_timer = SUBMERGED_SECONDS
	# The marker rides the player while he is under, so the arrival is aimed
	# but still leaves a window to walk out of.
	_step_telegraph = BossAoeTelegraph.spawn(
		self, _step_target, _nova_radius, SUBMERGED_SECONDS, _nova_damage, self, false)

func _tick_submerged(player: Node2D) -> void:
	if _step_timer > SUBMERGED_SECONDS * 0.45 and player != null:
		_step_target = player.global_position
		if _step_telegraph != null and is_instance_valid(_step_telegraph):
			_step_telegraph.global_position = _step_target

	if _step_timer > 0.0:
		return

	_arrive()

func _arrive() -> void:
	global_position = _step_target
	_set_intangible(false)
	_set_visual_sink(0.0)
	_step = Step.GROUNDED

	if _step_telegraph != null and is_instance_valid(_step_telegraph):
		_step_telegraph.queue_free()
		_step_telegraph = null

	if sprite_animator != null:
		sprite_animator.play_attack()

	_burst_nova(global_position, _nova_radius, _nova_damage, NOVA_RINGS)
	recover_remaining = 0.45

# Expanding rings out of the point he surfaced at. The first ring carries the
# damage; the rest are the shape of it leaving.
func _burst_nova(centre: Vector2, radius: float, damage: int, rings: int) -> void:
	apply_damage_in_radius(centre, radius, damage)

	var tree := get_tree()
	for i in range(maxi(1, rings)):
		var scale := 0.45 + 0.28 * i
		if i == 0:
			BossAoeTelegraph.spawn(self, centre, radius * scale, 0.2, 0, self, false)
			continue

		if tree == null:
			continue

		tree.create_timer(i * NOVA_RING_SPACING).timeout.connect(func():
			if is_instance_valid(self):
				BossAoeTelegraph.spawn(self, centre, radius * scale, 0.2, 0, self, false))

func _set_intangible(on: bool) -> void:
	visible = not on

	if collision_shape != null:
		collision_shape.set_deferred("disabled", on)

	if contact_hitbox != null:
		contact_hitbox.set_deferred("monitoring", not on)

# Squashes the sprite into the floor as he goes under.
func _set_visual_sink(amount: float) -> void:
	var visual := sprite_animator.get_sprite() if sprite_animator != null else null
	if visual == null:
		return

	if amount <= 0.0:
		visual.scale = _base_visual_scale
		visual.modulate.a = 1.0
		return

	visual.scale = Vector2(
		_base_visual_scale.x * (1.0 + amount * 0.25),
		_base_visual_scale.y * maxf(0.05, 1.0 - amount))
	visual.modulate.a = clampf(1.0 - amount * 0.9, 0.0, 1.0)

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
func process_chase(delta: float, player: Node2D, has_live_target: bool) -> void:
	if not has_live_target or player == null:
		super.process_chase(delta, player, has_live_target)
		return

	var speed := data.move_speed * get_phase_move_multiplier()
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var dir := to_player / dist if dist > 0.001 else Vector2.RIGHT

	_strafe_flip_in -= delta
	if _strafe_flip_in <= 0.0:
		_strafe_sign = -_strafe_sign
		_strafe_flip_in = randf_range(1.5, 3.0)

	var tangent := Vector2(-dir.y, dir.x) * _strafe_sign
	var desired: Vector2
	if dist < PREFERRED_RANGE - RANGE_TOLERANCE:
		# He drifts back rather than turning away — Boss.resolve_facing_x keeps
		# him looking at his prey the whole time.
		desired = (-dir * 0.8 + tangent * 0.55).normalized() * speed
	elif dist > PREFERRED_RANGE + RANGE_TOLERANCE:
		desired = (dir * 0.9 + tangent * 0.3).normalized() * speed
	else:
		desired = tangent * speed * 0.75

	velocity = velocity.lerp(desired, clampf(delta * STEER_RESPONSE, 0.0, 1.0))

	attack_cooldown_remaining -= delta
	if attack_cooldown_remaining <= 0:
		try_begin_attack(player)

# Paced off the fastest tool in the phase, like the other two bosses, so one
# long-cooldown summon does not buy the player a quiet arena.
func get_next_attack_cooldown() -> float:
	var phase := get_current_phase()
	if phase == null or phase.attacks == null or phase.attacks.is_empty():
		return super.get_next_attack_cooldown()

	var fastest := phase.attacks[0].cooldown_seconds
	for attack: BossAttackPatternData in phase.attacks:
		if attack != null:
			fastest = minf(fastest, attack.cooldown_seconds)

	return maxf(0.35, fastest * get_phase_cooldown_multiplier() * randf_range(0.85, 1.1))

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
func _on_died(source: Node) -> void:
	# Dying underground would leave an invisible corpse and a marker behind.
	if _step != Step.GROUNDED:
		_step = Step.GROUNDED
		_set_intangible(false)
		_set_visual_sink(0.0)

	if _step_telegraph != null and is_instance_valid(_step_telegraph):
		_step_telegraph.queue_free()
		_step_telegraph = null

	if _aura != null and is_instance_valid(_aura):
		_aura.queue_free()
		_aura = null

	super._on_died(source)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# Pools ring the player rather than landing on them: the attack takes ground
# away and forces a move, it does not simply deal damage for standing still.
func _pool_spot(attack: BossAttackPatternData, player: Node2D, index: int, count: int) -> Vector2:
	var spread = attack.range if attack.range > 0.0 else 130.0
	var angle = TAU * index / count + float(index) * 0.37
	return player.global_position + Vector2(spread, 0).rotated(angle)
