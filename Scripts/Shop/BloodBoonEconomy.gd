class_name BloodBoonEconomy

# Pure, static numbers for the Jester's Blood Boon economy: what a spin costs, what a
# Blood Boon costs in Grave Coin or XP, which faces the wheel can land and what each one
# does. Isolated from the passive and both UIs the same way ShopEconomy is isolated from
# ShopUI, so every dial the Jester is balanced on lives in one file.
#
# The wheel never misses: a spin always lands three of a kind. The gamble is *which* three,
# and the worst face (666) turns the machine on its owner. Luck bends the odds toward the
# good faces AND scales every damage number — the Jester's own included, which is why the
# shop tooltip carries a lethality warning.

enum Face {
	SEVEN,   # 777 — jackpot: executes the highest-HP enemy on the map
	SKULL,   # 666's opposite: heavy damage to everything
	BELL,    # focused damage on the nearest cluster
	BAT,     # damage plus a bite of health back
	VIAL,    # light damage to everything, and it slows them
	COIN,    # no damage: pays out Grave Coin and returns the spin's Blood Boon
	SIX,     # 666 — the machine bites the hand: damages the Jester
}

# ------------------------------------------------------------------------- prices

# Blood Boons the Jester starts every run holding.
const STARTING_COINS = 10

# A spin costs SPIN_BASE_COST on wave 1 and climbs by one every WAVES_PER_PRICE_STEP waves:
# waves 1-2 = 1, waves 3-4 = 2, waves 5-6 = 3…
const SPIN_BASE_COST = 1
const WAVES_PER_PRICE_STEP = 2

# Grave Coin per Blood Boon at the exchange, and how much that climbs per wave cleared.
# Deliberately steeper than the XP rate: gold has a shop to compete with, XP only buys
# levels the Jester can re-earn by fighting.
const GOLD_PER_COIN_BASE = 14
const GOLD_PER_COIN_GROWTH = 4

# XP per Blood Boon, same shape. Paying in XP can drop the Jester back a level or two —
# that is the whole point of the trade, and the exchange UI shows the resulting level
# before anything is spent.
const XP_PER_COIN_BASE = 9
const XP_PER_COIN_GROWTH = 3

# Cashing a whole pending level-up in at the boon screen instead of taking an upgrade.
const COINS_PER_TRADED_LEVEL_BASE = 4
const COINS_PER_TRADED_LEVEL_GROWTH = 1


static func get_spin_cost(wave_number: int) -> int:
	var step: int = int(maxi(1, wave_number) - 1) / WAVES_PER_PRICE_STEP
	return SPIN_BASE_COST + step


static func get_gold_price(coins: int, wave_number: int) -> int:
	return maxi(0, coins) * (GOLD_PER_COIN_BASE + GOLD_PER_COIN_GROWTH * maxi(0, wave_number - 1))


static func get_xp_price(coins: int, wave_number: int) -> int:
	return maxi(0, coins) * (XP_PER_COIN_BASE + XP_PER_COIN_GROWTH * maxi(0, wave_number - 1))


# Blood Boons handed over for skipping one moon-boon pick.
static func get_level_trade_payout(wave_number: int) -> int:
	return COINS_PER_TRADED_LEVEL_BASE + COINS_PER_TRADED_LEVEL_GROWTH * maxi(0, wave_number - 1)


# ------------------------------------------------------------------------- scaling

# Every damage number on the wheel rides on this. Luck is the Jester's whole build —
# it buys better odds and bigger hits at once — and the wave term keeps a wheel that
# one-shot wave 1 trash still relevant against wave 15 hordes.
static func damage_scale(luck: float, wave_number: int) -> float:
	return (1.0 + maxf(0.0, luck) * 0.04) * (1.0 + 0.15 * float(maxi(1, wave_number) - 1))


static func scaled_damage(base: float, luck: float, wave_number: int) -> int:
	return maxi(1, roundi(base * damage_scale(luck, wave_number)))


# ---------------------------------------------------------------------------- faces

# Base weight of each face before Luck. Every entry is also the tooltip row the shop
# draws, so the odds the player reads are computed from the exact table the spin rolls on
# rather than a hand-written copy that can drift out of sync.
static var _base_weights: Dictionary = {
	Face.SEVEN: 3.0,
	Face.SKULL: 9.0,
	Face.BELL: 14.0,
	Face.BAT: 16.0,
	Face.VIAL: 20.0,
	Face.COIN: 16.0,
	Face.SIX: 22.0,
}

# How hard each face leans on Luck. Positive = Luck makes it likelier; SIX is the only
# entry Luck pushes away, and even then only slowly — the Jester can never buy the risk
# out entirely.
static var _luck_bias: Dictionary = {
	Face.SEVEN: 0.10,
	Face.SKULL: 0.05,
	Face.BELL: 0.04,
	Face.BAT: 0.03,
	Face.VIAL: 0.0,
	Face.COIN: 0.02,
	Face.SIX: -0.06,
}

# Base damage per face before damage_scale. Faces that deal none sit at 0.
static var _base_damage: Dictionary = {
	Face.SEVEN: 0.0,
	Face.SKULL: 40.0,
	Face.BELL: 90.0,
	Face.BAT: 55.0,
	Face.VIAL: 25.0,
	Face.COIN: 0.0,
	Face.SIX: 30.0,
}

# How many enemies the face reaches. 0 = everything on the map.
const BELL_TARGETS = 3
const BAT_TARGETS = 1
# Fraction of the BAT face's damage returned to the Jester as health.
const BAT_HEAL_FRACTION = 0.25
# VIAL's slow: multiplier applied to enemy move speed, and for how long.
const VIAL_SLOW_MULTIPLIER = 0.6
const VIAL_SLOW_SECONDS = 3.0
# COIN's payout, plus the growth per wave, and the spin cost it hands back.
const COIN_GOLD_BASE = 25
const COIN_GOLD_GROWTH = 5


static func all_faces() -> Array:
	return [Face.SEVEN, Face.SKULL, Face.BELL, Face.BAT, Face.VIAL, Face.COIN, Face.SIX]


static func face_name(face: int) -> String:
	match face:
		Face.SEVEN: return "JACKPOT"
		Face.SKULL: return "REAPER'S CUT"
		Face.BELL: return "TOLLING"
		Face.BAT: return "BLOOD BITE"
		Face.VIAL: return "SPILLED VIAL"
		Face.COIN: return "BLOOD TITHE"
		Face.SIX: return "THE BEAST"
		_: return "?"


# Short ASCII glyph for the reel. The Nightbane font is a bitmap sheet, so anything
# outside plain ASCII renders as nothing.
static func face_glyph(face: int) -> String:
	match face:
		Face.SEVEN: return "7"
		Face.SKULL: return "X"
		Face.BELL: return "O"
		Face.BAT: return "V"
		Face.VIAL: return "U"
		Face.COIN: return "$"
		Face.SIX: return "6"
		_: return "?"


static func face_icon_path(face: int) -> String:
	match face:
		Face.SEVEN: return "res://Assets/UI/icon_star.png"
		Face.SKULL: return "res://Assets/UI/icon_skull.png"
		Face.BELL: return "res://Assets/UI/icon_time.png"
		Face.BAT: return "res://Assets/UI/icon_speed.png"
		Face.VIAL: return "res://Assets/UI/icon_potion.png"
		Face.COIN: return "res://Assets/UI/icon_coin.png"
		Face.SIX: return "res://Assets/UI/icon_damage.png"
		_: return "res://Assets/UI/icon_star.png"


static func face_color(face: int) -> Color:
	match face:
		Face.SEVEN: return Color(1.0, 0.86, 0.35)
		Face.SKULL: return Color(0.85, 0.85, 0.95)
		Face.BELL: return Color(0.75, 0.88, 1.0)
		Face.BAT: return Color(0.9, 0.55, 0.75)
		Face.VIAL: return Color(0.6, 0.95, 0.65)
		Face.COIN: return Color(1.0, 0.82, 0.45)
		Face.SIX: return Color(1.0, 0.35, 0.35)
		_: return Color.WHITE


static func face_damage(face: int, luck: float, wave_number: int) -> int:
	var base: float = _base_damage.get(face, 0.0)
	if base <= 0.0:
		return 0
	return scaled_damage(base, luck, wave_number)


static func coin_face_gold(wave_number: int) -> int:
	return COIN_GOLD_BASE + COIN_GOLD_GROWTH * maxi(0, wave_number - 1)


# One line describing what the face does at the player's current Luck and wave, used by
# both the in-run result banner and the shop's odds tooltip.
static func face_effect_text(face: int, luck: float, wave_number: int) -> String:
	var damage := face_damage(face, luck, wave_number)
	match face:
		Face.SEVEN:
			return "Executes the highest-HP enemy on the map"
		Face.SKULL:
			return "%d damage to every enemy" % damage
		Face.BELL:
			return "%d damage to the nearest %d" % [damage, BELL_TARGETS]
		Face.BAT:
			return "%d damage to the nearest, heals %d" % [damage, maxi(1, roundi(damage * BAT_HEAL_FRACTION))]
		Face.VIAL:
			return "%d damage to every enemy, slows them %d%%" % [damage, roundi((1.0 - VIAL_SLOW_MULTIPLIER) * 100.0)]
		Face.COIN:
			return "%dg and the spin's Blood Boon back" % coin_face_gold(wave_number)
		Face.SIX:
			return "%d damage TO YOU" % damage
		_:
			return ""


# ----------------------------------------------------------------------------- odds

# Luck-adjusted weight of one face. Never returns zero, so no outcome is ever fully
# bought out of the wheel.
static func face_weight(face: int, luck: float) -> float:
	var base: float = _base_weights.get(face, 0.0)
	var bias: float = _luck_bias.get(face, 0.0)
	var safe_luck: float = maxf(0.0, luck)

	if bias >= 0.0:
		return base * (1.0 + safe_luck * bias)

	# Negative bias divides rather than subtracts: 666 gets rarer and rarer without
	# ever reaching impossible.
	return base / (1.0 + safe_luck * absf(bias))


# Chance [0,1] of each face at the given Luck, keyed by Face.
static func face_odds(luck: float) -> Dictionary:
	var weights: Dictionary = {}
	var total := 0.0
	for face in all_faces():
		var weight := face_weight(face, luck)
		weights[face] = weight
		total += weight

	var odds: Dictionary = {}
	for face in all_faces():
		odds[face] = (weights[face] / total) if total > 0.0 else 0.0
	return odds


# Weighted roll over the Luck-adjusted table. Always returns a face — the wheel cannot
# come up empty.
static func roll_face(luck: float) -> int:
	var faces := all_faces()
	var total := 0.0
	var weights: Array[float] = []
	for face in faces:
		var weight := face_weight(face, luck)
		weights.append(weight)
		total += weight

	var roll := randf() * total
	for i in range(faces.size()):
		roll -= weights[i]
		if roll <= 0.0:
			return faces[i]

	return faces[faces.size() - 1]
