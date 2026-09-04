extends Node
class_name EnemyScaling

# HP grows ~12% per wave past wave 1 (wave 1 = 1.0x).
static func health_multiplier(wave_number: int) -> float:
	var waves_past_first = maxi(0, wave_number - 1)
	return 1.0 + waves_past_first * 0.12

# Where the compounding curve below starts biting. Not wave 1: the early waves
# are where a run is still assembling itself, and a Hunter who has not found a
# second weapon yet does not need the roster growing on him faster.
const LATE_WAVE = 8

# What a difficulty adds on top of the linear curve in the late waves, as a
# compounding rate per wave (1.0 = nothing, which is what Normal passes).
#
# Linear growth loses to a build. A Hunter's damage in the back half of a run is
# a product — weapon tiers times fire rate times crit times passives — so it
# climbs geometrically while +12% a wave climbs in a straight line, and the two
# curves cross somewhere around wave twelve. After that the night is a formality
# no matter what the flat difficulty multiplier is, because doubling a number
# that is already being outgrown just moves the crossing point two waves right.
#
# A rate rather than a bigger flat number for exactly that reason: this is the
# only term in the enemy curve shaped like the thing it has to keep up with.
#
#   at 1.055, from wave 8:  w10 1.11   w15 1.45   w20 1.90   w25 2.48
#
# Against the flat 2x and the linear curve, that is what a Dark is the Night
# enemy is worth in total: w10 4.6x authored, w15 7.8x, w20 12.5x — against
# 4.2x, 5.4x and 6.6x before it.
static func late_health_multiplier(wave_number: int, rate: float) -> float:
	if rate <= 1.0 or wave_number <= LATE_WAVE:
		return 1.0

	return pow(rate, wave_number - LATE_WAVE)

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
#
# On top of that curve, from the baseline wave to the finale, comes the
# hardening below. The curve alone was written when a boss was a wall the run
# arrived at; by the time a build is finished it is a health bar that falls over
# in one rotation of the Hunter's cooldowns, which makes the encounter a cutscene
# with a loot drop at the end. The hardening is what makes it a fight again, and
# it is nearly all health — see the note above on why damage is not the lever.
const BOSS_BASELINE_WAVE = 10
const BOSS_HEALTH_PER_WAVE_EARLY = 0.07
const BOSS_HEALTH_PER_WAVE_LATE = 0.11
const BOSS_DAMAGE_PER_WAVE_EARLY = 0.03
const BOSS_DAMAGE_PER_WAVE_LATE = 0.04

# The wave the run is won on — DeathScreen.victory_wave, which ends it the
# moment that wave does. Named here because the last boss has to know it is the
# last boss; the two numbers must not drift apart.
const FINALE_WAVE = 20

# The hardening, applied from BOSS_BASELINE_WAVE and ramped to FINALE_WAVE. The
# step at the baseline is deliberate rather than a ramp starting at 1.0: wave 10
# is where the complaint starts, so wave 10 is where the fix starts.
#
# These are the second pass. The first put wave 10 at 1.75 and the finale at 3.0,
# and a finished build still took the wave 10 and wave 12 bosses down in seconds
# — which says the gap between a boss's health bar and a late build's damage was
# never a matter of tens of percent. Doubled, so a wave 10 boss now spawns with
# twice the health the first pass gave it, and every boss above it with the same
# doubling. If it is still short, the honest read is that the fight needs to
# scale with the build (damage taken, or the player's own numbers) rather than
# that this constant wants a third pass.
const BOSS_HEALTH_HARDENING_AT_BASELINE = 3.5
const BOSS_HEALTH_HARDENING_AT_FINALE = 6.0
const BOSS_DAMAGE_HARDENING_AT_BASELINE = 1.08
const BOSS_DAMAGE_HARDENING_AT_FINALE = 1.22

# And the last fight on top of that. The run ends when this wave does, so this
# is the only boss the Hunter cannot out-wait, out-level or come back to with a
# better build — the one place in the run where the whole stack has to be spent
# at once. Everything before it is a wall; this one is the door.
const FINALE_HEALTH_BONUS = 1.4
const FINALE_DAMAGE_BONUS = 1.12

# Both curves with the hardening folded in. On a difficulty that scales bosses
# by wave at all — Boss.get_wave_*_multiplier gates on that — this is what a
# boss is actually worth:
#
#            w3     w9    w10    w12    w15    w18    w20    w25
#   health  0.51   0.93   3.50   4.88   7.36  10.34  17.64  22.26
#   damage  0.79   0.97   1.08   1.20   1.38   1.57   1.91   2.19
#
# The step between wave 9 and wave 10 is the largest thing on that line and it
# is meant to be: nine is a boss the run walks through, ten is where the fight
# was supposed to start. Wave 20 carries the finale bonus on top, which is why
# it jumps again against 18.
static func boss_health_multiplier(wave_number: int) -> float:
	return (_boss_curve(wave_number, BOSS_HEALTH_PER_WAVE_EARLY, BOSS_HEALTH_PER_WAVE_LATE)
		* _hardening(wave_number, BOSS_HEALTH_HARDENING_AT_BASELINE,
			BOSS_HEALTH_HARDENING_AT_FINALE)
		* (FINALE_HEALTH_BONUS if wave_number >= FINALE_WAVE else 1.0))

static func boss_damage_multiplier(wave_number: int) -> float:
	return (_boss_curve(wave_number, BOSS_DAMAGE_PER_WAVE_EARLY, BOSS_DAMAGE_PER_WAVE_LATE)
		* _hardening(wave_number, BOSS_DAMAGE_HARDENING_AT_BASELINE,
			BOSS_DAMAGE_HARDENING_AT_FINALE)
		* (FINALE_DAMAGE_BONUS if wave_number >= FINALE_WAVE else 1.0))

# 1.0 below the baseline, `at_baseline` on it, ramped to `at_finale` by the last
# wave and held there after. Held rather than extrapolated: past the finale the
# run is already over on every difficulty that has one, so anything beyond it is
# a boss nobody was balancing for and does not need a curve still climbing.
static func _hardening(wave_number: int, at_baseline: float, at_finale: float) -> float:
	if wave_number < BOSS_BASELINE_WAVE:
		return 1.0

	var span := float(maxi(1, FINALE_WAVE - BOSS_BASELINE_WAVE))
	var t := clampf((wave_number - BOSS_BASELINE_WAVE) / span, 0.0, 1.0)
	return at_baseline + (at_finale - at_baseline) * t

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
