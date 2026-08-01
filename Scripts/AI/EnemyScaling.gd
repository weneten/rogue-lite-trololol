extends Node
class_name EnemyScaling

# HP grows ~12% per wave past wave 1 (wave 1 = 1.0x).
static func health_multiplier(wave_number: int) -> float:
	var waves_past_first = maxi(0, wave_number - 1)
	return 1.0 + waves_past_first * 0.12

# Damage grows ~8% per wave past wave 1.
static func damage_multiplier(wave_number: int) -> float:
	var waves_past_first = maxi(0, wave_number - 1)
	return 1.0 + waves_past_first * 0.08

# Speed grows slowly (~3%/wave) so late packs stay readable.
static func speed_multiplier(wave_number: int) -> float:
	var waves_past_first = maxi(0, wave_number - 1)
	return 1.0 + waves_past_first * 0.03

# Elites start appearing at wave 4; chance caps at 25%.
static func elite_chance(wave_number: int) -> float:
	if wave_number < 4:
		return 0.0

	return minf(0.25, 0.04 + (wave_number - 4) * 0.02)

static func roll_elite(wave_number: int) -> bool:
	var chance = elite_chance(wave_number)
	return chance > 0.0 and randf() < chance

const ELITE_HEALTH_MULTIPLIER = 1.8
const ELITE_DAMAGE_MULTIPLIER = 1.45
const ELITE_SPEED_MULTIPLIER = 1.12
