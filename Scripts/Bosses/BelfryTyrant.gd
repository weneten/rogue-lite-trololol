extends Boss
class_name BelfryTyrant

# The Belfry Tyrant — the wave 15 bat.
#
# Two moves, and they answer each other:
#
#   sonic_wave   a fan of expanding arcs. Dodged sideways, or by standing
#                behind him. Punishes staying at range.
#   ascend_dive  he climbs out of the frame entirely, a marker hunts the
#                player across the floor, locks, and he comes down on it.
#                Punishes standing still.
#
# The dive is the reason he is a kiter rather than a chaser: he keeps his
# distance and shells you, and the only way he closes is by falling on you.
#
# While aloft he is untargetable — Weapon.is_live_candidate skips anything
# whose node is hidden, so hiding the body is all it takes. Contact damage and
# his collider go with it, so the player can run through the space he left.

enum Flight {
	GROUNDED,
	ASCENDING,
	ALOFT,
	DIVING,
}

const WAVE_ARC_DEGREES := 52.0
const WAVE_SPACING := 0.11
const WAVE_FAN_DEGREES := 13.0

const ASCEND_SECONDS := 0.45
const ALOFT_SECONDS := 1.15
# Last stretch aloft, during which the marker stops following and just fills.
# Without it the marker sits under the player until the instant of impact,
# which is not a telegraph, it is a homing missile with a decal.
const DIVE_LOCK_SECONDS := 0.55
const DIVE_SECONDS := 0.22
const DIVE_HEIGHT := 340.0
const LANDING_RECOVERY := 0.4

# How far he wants to sit. He is a shelling boss; closing the gap is the dive's
# job, not his legs'.
const PREFERRED_RANGE := 210.0
const RANGE_TOLERANCE := 55.0
const STEER_RESPONSE := 7.0

var _storm_announced: bool

var _flight: Flight = Flight.GROUNDED
var _flight_timer: float
var _dive_target: Vector2
var _dive_telegraph: BossAoeTelegraph
var _dive_damage: int
var _dive_radius: float
# Dives left in the current ascend_dive use — phase 2 buys a second one.
var _dives_queued: int
var _aloft_seconds: float = ALOFT_SECONDS

var _strafe_sign: float = 1.0
var _strafe_flip_in: float = 2.0

func on_phase_entered(phase_index: int, previous_phase_index: int = -1) -> void:
	super.on_phase_entered(phase_index, previous_phase_index)
	if phase_index >= 1 and not _storm_announced:
		_storm_announced = true
		print("[Boss] The Belfry Tyrant raises an Echo Storm!")
		BossAoeTelegraph.spawn(self, global_position, 110.0, 0.4, 0, self, false)

# ---------------------------------------------------------------------------
# Telegraphs
# ---------------------------------------------------------------------------
func begin_telegraph(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null or player == null:
		return

	match attack.attack_id:
		"sonic_wave":
			# The cone the fan will fill, drawn before a single wave exists.
			active_telegraph = BossAoeTelegraph.spawn_cone(
				self, global_position, _direction_to(player.global_position),
				attack.range, WAVE_ARC_DEGREES + WAVE_FAN_DEGREES * maxi(0, attack.count - 1),
				attack.windup_seconds, roundi(attack.damage), self, false)

		"ascend_dive":
			# A crouch under him: he is gathering himself to launch. The real
			# warning is the marker that appears once he is off the screen.
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, 70.0, attack.windup_seconds, 0, self, false)

		_:
			super.begin_telegraph(attack, player)

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------
func execute_attack(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null or player == null:
		return

	match attack.attack_id:
		"sonic_wave":
			_execute_sonic_wave(attack, player)
		"ascend_dive":
			_execute_ascend(attack)
		_:
			super.execute_attack(attack, player)

	remember_attack_cooldown(attack)

# A fan of arcs, staggered so they arrive as a rhythm rather than one wall.
func _execute_sonic_wave(attack: BossAttackPatternData, player: Node2D) -> void:
	var count := maxi(1, attack.count)
	var base := _direction_to(player.global_position)
	var speed := attack.speed if attack.speed > 0.0 else 300.0

	for i in range(count):
		var spread := (float(i) - float(count - 1) * 0.5) * deg_to_rad(WAVE_FAN_DEGREES)
		var direction := base.rotated(spread)
		var delay := i * WAVE_SPACING
		if delay <= 0.0:
			_fire_wave(direction, attack, speed)
			continue

		var tree := get_tree()
		if tree == null:
			continue

		tree.create_timer(delay).timeout.connect(func():
			if not is_instance_valid(self) or state == BossState.DEAD:
				return

			# Re-aimed at the live player: a fan locked in at wind-up let the
			# player simply walk out of it while it was still spawning.
			var aim := _direction_to(_player_position(global_position + base))
			_fire_wave(aim.rotated(spread), attack, speed))

func _fire_wave(direction: Vector2, attack: BossAttackPatternData, speed: float) -> void:
	BossSonicWave.spawn(
		self, global_position, direction, WAVE_ARC_DEGREES, speed,
		attack.range, roundi(attack.damage), self)

func _execute_ascend(attack: BossAttackPatternData) -> void:
	_dive_damage = roundi(attack.damage)
	_dive_radius = maxf(48.0, attack.radius)
	_dives_queued = maxi(1, attack.count)
	_begin_ascent(attack.duration if attack.duration > 0.0 else ALOFT_SECONDS)

# ---------------------------------------------------------------------------
# Flight
# ---------------------------------------------------------------------------
func _begin_ascent(aloft_seconds: float) -> void:
	_flight = Flight.ASCENDING
	_flight_timer = ASCEND_SECONDS
	# Held open for the whole manoeuvre; the landing sets the real recovery.
	recover_remaining = 99.0
	velocity = Vector2.ZERO

	if sprite_animator != null:
		sprite_animator.play_named("dash")

	_aloft_seconds = aloft_seconds

func process_recover(delta: float, player: Node2D, has_live_target: bool) -> void:
	if _flight == Flight.GROUNDED:
		super.process_recover(delta, player, has_live_target)
		return

	velocity = Vector2.ZERO
	_flight_timer -= delta

	match _flight:
		Flight.ASCENDING:
			_tick_ascending()
		Flight.ALOFT:
			_tick_aloft(player)
		Flight.DIVING:
			_tick_diving()

func _tick_ascending() -> void:
	var climb := 1.0 - clampf(_flight_timer / ASCEND_SECONDS, 0.0, 1.0)
	_set_sprite_lift(climb * DIVE_HEIGHT)
	_set_sprite_alpha(1.0 - climb * 0.85)

	if _flight_timer > 0.0:
		return

	_set_intangible(true)
	_flight = Flight.ALOFT
	_flight_timer = maxf(DIVE_LOCK_SECONDS + 0.1, _aloft_seconds)
	_dive_target = _player_position(global_position)
	_dive_telegraph = BossAoeTelegraph.spawn(
		self, _dive_target, _dive_radius, _flight_timer + DIVE_SECONDS,
		_dive_damage, self, false)

func _tick_aloft(player: Node2D) -> void:
	# The marker hunts the player, then locks for the last stretch so the dodge
	# is a real one: keep moving and the last place you stood is where he lands.
	if _flight_timer > DIVE_LOCK_SECONDS and player != null:
		_dive_target = player.global_position
		if _dive_telegraph != null and is_instance_valid(_dive_telegraph):
			_dive_telegraph.global_position = _dive_target

	if _flight_timer > 0.0:
		return

	_flight = Flight.DIVING
	_flight_timer = DIVE_SECONDS
	global_position = _dive_target
	_set_sprite_lift(DIVE_HEIGHT)
	_set_sprite_alpha(1.0)
	visible = true
	if sprite_animator != null:
		sprite_animator.play_named("dash")

func _tick_diving() -> void:
	var fall := 1.0 - clampf(_flight_timer / DIVE_SECONDS, 0.0, 1.0)
	_set_sprite_lift((1.0 - fall) * DIVE_HEIGHT)

	if _flight_timer > 0.0:
		return

	_land()

func _land() -> void:
	_set_sprite_lift(0.0)
	_set_sprite_alpha(1.0)
	_set_intangible(false)
	_flight = Flight.GROUNDED

	if _dive_telegraph != null and is_instance_valid(_dive_telegraph):
		_dive_telegraph.queue_free()
		_dive_telegraph = null

	apply_damage_in_radius(global_position, _dive_radius, _dive_damage)
	# The impact ring: a short, damage-free flash so the hit is visible even
	# when it missed.
	BossAoeTelegraph.spawn(self, global_position, _dive_radius, 0.22, 0, self, false)

	_dives_queued -= 1
	if _dives_queued > 0:
		_begin_ascent(_aloft_seconds * 0.85)
		return

	recover_remaining = LANDING_RECOVERY

# Hidden means untargetable (Weapon.is_live_candidate), and the collider and
# contact hitbox go with it so the arena floor he left is genuinely empty.
func _set_intangible(on: bool) -> void:
	visible = not on

	if collision_shape != null:
		collision_shape.set_deferred("disabled", on)

	if contact_hitbox != null:
		contact_hitbox.set_deferred("monitoring", not on)

func _set_sprite_lift(pixels: float) -> void:
	var visual := _visual()
	if visual != null:
		visual.position.y = -pixels

func _set_sprite_alpha(alpha: float) -> void:
	var visual := _visual()
	if visual != null:
		visual.modulate.a = clampf(alpha, 0.0, 1.0)

func _visual() -> CanvasItem:
	return sprite_animator.get_sprite() if sprite_animator != null else null

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
func process_chase(delta: float, player: Node2D, has_live_target: bool) -> void:
	if not has_live_target or player == null:
		super.process_chase(delta, player, has_live_target)
		return

	var speed := get_move_speed() * get_phase_move_multiplier()
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var dir := to_player / dist if dist > 0.001 else Vector2.RIGHT

	_strafe_flip_in -= delta
	if _strafe_flip_in <= 0.0:
		_strafe_sign = -_strafe_sign
		_strafe_flip_in = randf_range(1.4, 2.8)

	var tangent := Vector2(-dir.y, dir.x) * _strafe_sign
	var desired: Vector2
	if dist < PREFERRED_RANGE - RANGE_TOLERANCE:
		# Backing off reads correctly on a flyer — and Boss.resolve_facing_x
		# keeps him looking at the player the whole way, so he retreats facing
		# his prey instead of turning tail.
		desired = (-dir * 0.85 + tangent * 0.5).normalized() * speed
	elif dist > PREFERRED_RANGE + RANGE_TOLERANCE:
		desired = (dir * 0.9 + tangent * 0.35).normalized() * speed
	else:
		desired = tangent * speed * 0.8

	velocity = velocity.lerp(desired, clampf(delta * STEER_RESPONSE, 0.0, 1.0))

	attack_cooldown_remaining -= delta
	if attack_cooldown_remaining <= 0:
		try_begin_attack(player)

# Paced off the fastest tool in the phase, so one long dive cooldown does not
# hand the player a quiet arena. Matches how the Alpha paces.
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
	# Dying mid-flight would otherwise leave an invisible corpse and a marker
	# hanging over the arena.
	if _flight != Flight.GROUNDED:
		_flight = Flight.GROUNDED
		_set_sprite_lift(0.0)
		_set_sprite_alpha(1.0)
		_set_intangible(false)

	if _dive_telegraph != null and is_instance_valid(_dive_telegraph):
		_dive_telegraph.queue_free()
		_dive_telegraph = null

	super._on_died(source)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _direction_to(point: Vector2) -> Vector2:
	var delta := point - global_position
	return delta.normalized() if delta.length_squared() > 0.0001 else Vector2.RIGHT

func _player_position(fallback: Vector2) -> Vector2:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	return player.global_position if player != null else fallback
