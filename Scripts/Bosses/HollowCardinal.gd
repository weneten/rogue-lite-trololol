extends Boss
class_name HollowCardinal

# The Hollow Cardinal — homing curse bolts, ritual circles that punish standing still,
# phase 2 cultist adds.

var _phase2_announced: bool

func on_phase_entered(phase_index: int, previous_phase_index: int = -1) -> void:
	super.on_phase_entered(phase_index, previous_phase_index)
	if phase_index >= 1 and not _phase2_announced:
		_phase2_announced = true
		print("[Boss] Hollow Cardinal begins the Dark Mass!")

func begin_telegraph(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null:
		return

	var id = attack.attack_id if attack.attack_id != null else ""
	match id:
		"curse_bolt":
			# Self cast glow; bolts fire after wind-up.
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, 48.0, attack.windup_seconds, 0, self, false)

		"ritual_circle":
			# Circle under player feet.
			var pos = player.global_position if player else global_position
			active_telegraph = BossAoeTelegraph.spawn(
				self, pos, attack.radius, attack.windup_seconds, 0, self, false)

		"summon_cultists":
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, attack.radius, attack.windup_seconds, 0, self, false)

		_:
			super.begin_telegraph(attack, player)

func execute_attack(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null:
		return

	match attack.attack_id:
		"curse_bolt":
			_execute_curse_bolts(attack, player)
		"ritual_circle":
			_execute_ritual_circle(attack, player)
		"summon_cultists":
			_execute_summon_cultists(attack)
		_:
			super.execute_attack(attack, player)

	remember_attack_cooldown(attack)

func _execute_curse_bolts(attack: BossAttackPatternData, player: Node2D) -> void:
	if player == null:
		return

	var count = maxi(1, attack.count)
	var base_dir = (player.global_position - global_position).normalized()
	if base_dir == Vector2.ZERO:
		base_dir = Vector2.RIGHT

	for i in range(count):
		var spread = 0.0 if count == 1 else lerp(-0.45, 0.45, float(i) / (count - 1))
		var dir = base_dir.rotated(spread)
		BossHomingBolt.spawn(
			self,
			global_position + dir * 24.0,
			dir,
			attack.speed,
			roundi(attack.damage),
			self,
			attack.duration if attack.duration > 0.0 else 5.0,
			3.2 + current_phase_index * 0.6)

func _execute_ritual_circle(attack: BossAttackPatternData, player: Node2D) -> void:
	var pos = active_telegraph.global_position if active_telegraph and is_instance_valid(active_telegraph) else (player.global_position if player else global_position)

	# Phase 2: dual circles.
	var rings = maxi(2, attack.count) if current_phase_index >= 1 else maxi(1, attack.count)
	for i in range(rings):
		var ring_pos = pos
		if i > 0:
			ring_pos += Vector2(attack.range * 0.5, 0).rotated(TAU * i / rings + randf())

		BossRitualCircle.spawn(
			self,
			ring_pos,
			attack.radius,
			attack.duration if attack.duration > 0.0 else 5.0,
			roundi(attack.damage),
			self)

func _execute_summon_cultists(attack: BossAttackPatternData) -> void:
	var count = maxi(1, attack.count)
	for i in range(count):
		var angle = TAU * i / count + randf_range(0.0, 0.5)
		var pos = global_position + Vector2(attack.range, 0).rotated(angle)
		spawn_minion(
			pos,
			"Cultist",
			Color(0.45, 0.2, 0.55, 1.0),
			22,
			100.0,
			7.0,
			1.1)

func process_chase(delta: float, player: Node2D, has_live_target: bool) -> void:
	# Prefers mid-range kiting.
	if has_live_target and player != null:
		var speed = get_move_speed() * get_phase_move_multiplier()
		var dist = global_position.distance_to(player.global_position)
		var dir = (player.global_position - global_position).normalized()
		var preferred = 220.0

		if dist < preferred - 40.0:
			velocity = -dir * speed
		elif dist > preferred + 40.0:
			velocity = dir * speed * 0.85
		else:
			velocity = Vector2(-dir.y, dir.x) * speed * 0.5

		attack_cooldown_remaining -= delta
		if attack_cooldown_remaining <= 0:
			try_begin_attack(player)

		return

	super.process_chase(delta, player, has_live_target)
