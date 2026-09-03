class_name Difficulty

# Run difficulty, as one table rather than a scattering of `if hard_mode` checks.
#
# Every system that cares reads its own number out of here — WaveManager asks
# how dense the waves are, Enemy asks how much health to spawn with, Player asks
# how much of its own health it keeps. Adding a third difficulty means adding a
# row, not hunting for branches.
#
# Normal is deliberately all-ones and all-defaults: the mode the game was tuned
# in has to be the mode where none of this does anything.

enum Level {
	NORMAL,
	DARK_NIGHT,
}

const ORDER: Array[int] = [Level.NORMAL, Level.DARK_NIGHT]

const PROFILES := {
	Level.NORMAL: {
		"name": "Normal",
		"tagline": "The hunt as it was written.",
		"description": "Standard enemy strength, one boss on waves 10, 15 and 20.",
		"enemy_health": 1.0,
		"enemy_damage": 1.0,
		# 0 keeps whatever speed the archetype was authored with.
		"enemy_speed_of_player": 0.0,
		"player_health": 1.0,
		"player_damage": 1.0,
		"enemy_density": 1.0,
		# 0 means bosses only appear on their own wave_trigger.
		"boss_every_waves": 0,
		"wave_waits_for_boss": false,
		# Bosses only ever appear on their own wave, so scaling them by it would
		# just re-tune three fixed encounters nobody asked to have re-tuned.
		"boss_wave_scaling": false,
		# 0 disables the wardens entirely.
		"overspeed_threshold": 0.0,
		# What a run pays in Blood Marks, and what dying costs of the stockpile.
		"meta_currency": 1.0,
		"death_meta_loss": 0.0,
	},
	Level.DARK_NIGHT: {
		"name": "Dark is the Night!",
		"tagline": "Whatever is behind you is barely slower than you.",
		"description": "Enemies: double health, +120% damage, 94% of your speed, half again as many. You: 55% health, 75% damage. A boss every third wave, drawn at random and never the same one twice in a row, and the wave does not end until it falls. Bosses grow with the wave they arrive on. Outrun the night by more than a quarter and it sends something to slow you down. Blood Marks pay four times over — but fall here and half of everything you have banked stays in the dark.",
		"enemy_health": 2.0,
		# +120% damage dealt, i.e. 2.2x what the archetype does.
		"enemy_damage": 2.2,
		# Not a multiplier on their own speed: a target expressed against the
		# Hunter's starting speed, so the chase stays as tight for a slow Hunter
		# as for a fast one. 0.9433 of the 300 baseline is 283.
		"enemy_speed_of_player": 0.9433,
		"player_health": 0.55,
		"player_damage": 0.75,
		"enemy_density": 1.5,
		"boss_every_waves": 3,
		"wave_waits_for_boss": true,
		# A boss can land on wave 3 or wave 30 here, so it has to be worth the
		# wave it lands on.
		"boss_wave_scaling": true,
		# Move speed multiplier past which the dark mages start arriving.
		"overspeed_threshold": 1.25,
		# The wager. Four times the Blood Marks for the run, against half of
		# everything already banked if the night takes you. Surviving to wave 20
		# collects without paying: the cost is dying, not playing.
		"meta_currency": 4.0,
		"death_meta_loss": 0.5,
	},
}

static func profile(level: int) -> Dictionary:
	return PROFILES.get(level, PROFILES[Level.NORMAL])

static func display_name(level: int) -> String:
	return profile(level)["name"]

static func tagline(level: int) -> String:
	return profile(level)["tagline"]

static func description(level: int) -> String:
	return profile(level)["description"]

static func enemy_health_multiplier(level: int) -> float:
	return profile(level)["enemy_health"]

static func enemy_damage_multiplier(level: int) -> float:
	return profile(level)["enemy_damage"]

static func player_health_multiplier(level: int) -> float:
	return profile(level)["player_health"]

static func player_damage_multiplier(level: int) -> float:
	return profile(level)["player_damage"]

static func enemy_density_multiplier(level: int) -> float:
	return profile(level)["enemy_density"]

static func boss_every_waves(level: int) -> int:
	return profile(level)["boss_every_waves"]

static func wave_waits_for_boss(level: int) -> bool:
	return profile(level)["wave_waits_for_boss"]

static func boss_wave_scaling(level: int) -> bool:
	return profile(level)["boss_wave_scaling"]

# The move-speed multiplier a Hunter has to exceed before the dark mages take an
# interest. 0 means this difficulty never sends them.
static func overspeed_threshold(level: int) -> float:
	return profile(level)["overspeed_threshold"]

# What a finished run pays in Blood Marks, against the Normal payout.
static func meta_currency_multiplier(level: int) -> float:
	return profile(level)["meta_currency"]

# The share of the banked Blood Marks that dying costs. 0 means death is free.
# Charged against what was banked before the run, so the run's own payout is
# never clawed back — the wager is the stockpile, not the night's work.
static func death_meta_loss_fraction(level: int) -> float:
	return profile(level)["death_meta_loss"]

# The speed an enemy or boss should move at, given the Hunter's starting speed.
# Returns `authored_speed` unchanged on difficulties that do not override it.
static func enemy_speed(level: int, authored_speed: float, player_base_speed: float) -> float:
	var fraction: float = profile(level)["enemy_speed_of_player"]
	if fraction <= 0.0 or player_base_speed <= 0.0:
		return authored_speed

	# Never a downgrade: an archetype already faster than the Hunter keeps its
	# own speed rather than being slowed down by the harder difficulty.
	return maxf(authored_speed, player_base_speed * fraction)

static func is_default(level: int) -> bool:
	return level == Level.NORMAL

static func next(level: int) -> int:
	var index := ORDER.find(level)
	return ORDER[(index + 1) % ORDER.size()] if index >= 0 else Level.NORMAL
