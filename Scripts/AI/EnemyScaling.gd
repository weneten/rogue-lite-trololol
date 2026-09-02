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

# Bosses, on difficulties that ask for it. Wave 10 is the baseline because it is
# the first wave any boss was authored for: turn up there and you are the boss as
# written. Below it the numbers come down, which matters on a difficulty that
# deals bosses onto wave 3 — the Voivode as tuned would simply end the run.
#
# The slope is gentler below the baseline than above it, and that is the whole
# shape of this. A single slope steep enough to matter by wave 30 drives a wave-3
# boss down to a fifth of itself, and the obvious guard against that — a floor —
# turned out to be worse: it flattened every wave under 6 to the same number, so
# a boss on wave 3 and a boss on wave 5 were the same boss. Two slopes keep the
# curve climbing at every wave a boss can actually land on.
#
# Health climbs about three times faster than damage on purpose. A boss with more
# HP is a longer fight the player can still read and dodge; a boss with more
# damage is the same fight with a smaller mistake budget, and past a point that
# stops being difficulty and starts being a coin flip.
#
#            w1     w3     w6     w9    w10    w15    w20    w30
#   health  0.37   0.51   0.72   0.93   1.00   1.55   2.10   3.20
#   damage  0.73   0.79   0.88   0.97   1.00   1.20   1.40   1.80
const BOSS_BASELINE_WAVE = 10
const BOSS_HEALTH_PER_WAVE_EARLY = 0.07
const BOSS_HEALTH_PER_WAVE_LATE = 0.11
const BOSS_DAMAGE_PER_WAVE_EARLY = 0.03
const BOSS_DAMAGE_PER_WAVE_LATE = 0.04

static func boss_health_multiplier(wave_number: int) -> float:
	return _boss_curve(wave_number, BOSS_HEALTH_PER_WAVE_EARLY, BOSS_HEALTH_PER_WAVE_LATE)

static func boss_damage_multiplier(wave_number: int) -> float:
	return _boss_curve(wave_number, BOSS_DAMAGE_PER_WAVE_EARLY, BOSS_DAMAGE_PER_WAVE_LATE)

# 1.0 at the baseline wave, `early` per wave below it and `late` per wave above.
# The clamp is a guard against a mistuned constant, not part of the curve: at the
# authored slopes it never binds for any wave a run can reach.
static func _boss_curve(wave_number: int, early: float, late: float) -> float:
	if wave_number <= 0:
		return 1.0

	var offset := wave_number - BOSS_BASELINE_WAVE
	return maxf(0.2, 1.0 + offset * (late if offset > 0 else early))

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
