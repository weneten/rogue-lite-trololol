extends Boss
class_name BatWingedCount

# The Bat-Winged Count — blinks, summons bat swarms, blood frenzy at ~50% HP
# (faster attacks via phase cooldown multiplier + life drain on hits).

var _frenzy_announced: bool

func on_phase_entered(phase_index: int, previous_phase_index: int = -1) -> void:
	super.on_phase_entered(phase_index, previous_phase_index)
	if phase_index >= 1 and not _frenzy_announced:
		_frenzy_announced = true
		print("[Boss] Bat-Winged Count enters Blood Frenzy!")
		# Brief self telegraph as visual flare.
		BossAoeTelegraph.spawn(self, global_position, 70.0, 0.35, 0, self, false)

func begin_telegraph(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null:
		return

	var id = attack.attack_id if attack.attack_id != null else ""
	match id:
		"blink":
			# Destination flash near player.
			if player != null:
				var dest = player.global_position + Vector2(attack.range, 0).rotated(randf_range(0.0, TAU))
				active_telegraph = BossAoeTelegraph.spawn(
					self, dest, 36.0, attack.windup_seconds, 0, self, false)

		"bat_swarm":
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, attack.radius, attack.windup_seconds, 0, self, false)

		"blood_slash":
			# Slash arc centered on boss toward player.
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, attack.radius, attack.windup_seconds,
				roundi(attack.damage), self, false)

func execute_attack(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null or player == null:
		return

	var heal = attack.heal_fraction
	# Blood frenzy phase also forces life drain even if pattern heal is 0.
	if current_phase_index >= 1 and heal <= 0.0:
		heal = 0.35

	match attack.attack_id:
		"blink":
			_execute_blink(attack, player, heal)
		"bat_swarm":
			_execute_bat_swarm(attack)
		"blood_slash":
			apply_damage_in_radius(global_position, attack.radius, roundi(attack.damage), heal)

	remember_attack_cooldown(attack)

func _execute_blink(attack: BossAttackPatternData, player: Node2D, heal: float) -> void:
	var dest: Vector2
	if active_telegraph != null and is_instance_valid(active_telegraph):
		dest = active_telegraph.global_position
	else:
		dest = player.global_position + Vector2(attack.range, 0).rotated(randf_range(0.0, TAU))

	global_position = dest
	# Arrival slash.
	apply_damage_in_radius(global_position, attack.radius * 0.75, roundi(attack.damage), heal)

func _execute_bat_swarm(attack: BossAttackPatternData) -> void:
	var count = maxi(1, attack.count)
	for i in range(count):
		var angle = TAU * i / count + randf_range(-0.2, 0.2)
		var offset = Vector2(attack.radius, 0).rotated(angle)
		spawn_minion(
			global_position + offset,
			"Bat",
			Color(0.25, 0.12, 0.3, 1.0),
			8,
			170.0,
			maxf(2.0, attack.damage * 0.25),
			0.7)

func process_chase(delta: float, player: Node2D, has_live_target: bool) -> void:
	# Frenzy: slightly more aggressive close-range orbit.
	if current_phase_index >= 1 and has_live_target and player != null:
		var speed = get_move_speed() * get_phase_move_multiplier()
		var to_player = player.global_position - global_position
		var dist = to_player.length()
		var dir = to_player / dist if dist > 0.001 else Vector2.RIGHT
		# Prefer ~120px hover range.
		if dist < 100.0:
			velocity = -dir * speed
		elif dist > 160.0:
			velocity = dir * speed
		else:
			velocity = Vector2(-dir.y, dir.x) * speed * 0.7

		attack_cooldown_remaining -= delta
		if attack_cooldown_remaining <= 0:
			try_begin_attack(player)

		return

	super.process_chase(delta, player, has_live_target)
