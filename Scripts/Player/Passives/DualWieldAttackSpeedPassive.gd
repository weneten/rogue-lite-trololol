extends PassiveAbility
class_name DualWieldAttackSpeedPassive

# Moonlit Duelist — twin blades under moonlight, every strike faster than the last: PassiveValueA
# is a flat multiplier increase to attack speed (e.g. 0.35 = +35% attacks/sec) applied to every
# equipped weapon via PlayerStats.AttackSpeedMultiplier.

func on_initialize() -> void:
	stats.apply_attack_speed_bonus(data.passive_value_a)
