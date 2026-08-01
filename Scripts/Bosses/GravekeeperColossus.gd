extends Boss
class_name GravekeeperColossus

# The Gravekeeper Colossus — slow heavy melee, ground-smash shockwave zones, summons ghouls.

func begin_telegraph(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null:
		return

	var id = attack.attack_id if attack.attack_id != null else ""
	match id:
		"ground_smash":
			# Multiple shockwave rings at staggered offsets around player / self.
			var center = player.global_position if player else global_position
			active_telegraph = BossAoeTelegraph.spawn(
				self, center, attack.radius, attack.windup_seconds,
				roundi(attack.damage), self, false)

			# Extra warning zones (visual only; hit resolved in ExecuteAttack).
			var extra = maxi(0, attack.count - 1)
			for i in range(extra):
				var a = TAU * i / maxi(1, extra) + randf_range(0.0, 1.0)
				var pos = center + Vector2(attack.range * 0.45, 0).rotated(a)
				BossAoeTelegraph.spawn(
					self, pos, attack.radius * 0.7, attack.windup_seconds,
					0, self, false)

		"summon_ghouls":
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, attack.radius, attack.windup_seconds, 0, self, false)

		"heavy_melee":
			active_telegraph = BossAoeTelegraph.spawn(
				self, global_position, attack.radius, attack.windup_seconds,
				roundi(attack.damage), self, false)

func execute_attack(attack: BossAttackPatternData, player: Node2D) -> void:
	if attack == null:
		return

	match attack.attack_id:
		"ground_smash":
			_execute_ground_smash(attack, player)
		"summon_ghouls":
			_execute_summon_ghouls(attack)
		"heavy_melee":
			apply_damage_in_radius(global_position, attack.radius, roundi(attack.damage))

	remember_attack_cooldown(attack)

func _execute_ground_smash(attack: BossAttackPatternData, player: Node2D) -> void:
	var center = active_telegraph.global_position if active_telegraph and is_instance_valid(active_telegraph) else (player.global_position if player else global_position)

	apply_damage_in_radius(center, attack.radius, roundi(attack.damage))

	var extra = maxi(0, attack.count - 1)
	for i in range(extra):
		var a = TAU * i / maxi(1, extra)
		var pos = center + Vector2(attack.range * 0.45, 0).rotated(a)
		apply_damage_in_radius(pos, attack.radius * 0.7, roundi(attack.damage * 0.75))

func _execute_summon_ghouls(attack: BossAttackPatternData) -> void:
	var count = maxi(1, attack.count)
	for i in range(count):
		var angle = TAU * i / count
		# "Graves" pop around the colossus.
		var grave_pos = global_position + Vector2(attack.range, 0).rotated(angle)
		BossAoeTelegraph.spawn(self, grave_pos, 28.0, 0.2, 0, self, false)
		spawn_minion(
			grave_pos,
			"Ghoul",
			Color(0.36, 0.5, 0.3, 1.0),
			18,
			140.0,
			6.0,
			0.85)

func process_chase(delta: float, player: Node2D, has_live_target: bool) -> void:
	# Deliberately slow: never sprints; base MoveSpeed already low.
	super.process_chase(delta, player, has_live_target)
