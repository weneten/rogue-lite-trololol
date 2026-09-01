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
	},
	Level.DARK_NIGHT: {
		"name": "Dark is the Night!",
		"tagline": "Whatever is behind you is barely slower than you.",
		"description": "Enemies: double health, +120% damage, 94% of your speed, half again as many. You: 55% health, 75% damage. A boss every third wave, and the wave does not end until it falls.",
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
