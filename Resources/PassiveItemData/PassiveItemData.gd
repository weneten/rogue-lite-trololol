extends Resource
class_name PassiveItemData

# What stat a passive item permanently boosts on purchase. Mirrors UpgradeType's numeric
# effects (no Passive/relic-placeholder case here since these ARE the relics).
#
# Append only — the numeric value is what the .tres files store, so reordering
# these silently rewires every relic in the game.
enum PassiveEffectType {
	DAMAGE_BOOST,
	MOVE_SPEED_BOOST,
	MAX_HEALTH_BOOST,
	ATTACK_SPEED_BOOST,
	CRIT_CHANCE_BOOST,
	CRIT_DAMAGE_BOOST,
	LIFESTEAL_BOOST,
	ARMOR_BOOST,
	DODGE_BOOST,
	HEALTH_REGEN_BOOST,
	PICKUP_RANGE_BOOST,
	UNDEAD_DAMAGE_BOOST,
	MAGIC_DAMAGE_BOOST,
	XP_GAIN_BOOST,
	CURRENCY_GAIN_BOOST,
	LUCK_BOOST,
	ENEMY_DENSITY_BOOST,
	DAMAGE_TAKEN_REDUCTION,
}

# Short stat label shown on the shop card, keyed by effect type. Kept next to
# the enum so adding a case without a label is impossible to miss.
const EFFECT_LABEL := {
	PassiveEffectType.DAMAGE_BOOST: "Damage",
	PassiveEffectType.MOVE_SPEED_BOOST: "Move Speed",
	PassiveEffectType.MAX_HEALTH_BOOST: "Max Health",
	PassiveEffectType.ATTACK_SPEED_BOOST: "Attack Speed",
	PassiveEffectType.CRIT_CHANCE_BOOST: "Crit Chance",
	PassiveEffectType.CRIT_DAMAGE_BOOST: "Crit Damage",
	PassiveEffectType.LIFESTEAL_BOOST: "Lifesteal",
	PassiveEffectType.ARMOR_BOOST: "Armour",
	PassiveEffectType.DODGE_BOOST: "Dodge",
	PassiveEffectType.HEALTH_REGEN_BOOST: "Regen",
	PassiveEffectType.PICKUP_RANGE_BOOST: "Pickup Range",
	PassiveEffectType.UNDEAD_DAMAGE_BOOST: "vs Undead",
	PassiveEffectType.MAGIC_DAMAGE_BOOST: "Magic Damage",
	PassiveEffectType.XP_GAIN_BOOST: "XP Gain",
	PassiveEffectType.CURRENCY_GAIN_BOOST: "Gold Gain",
	PassiveEffectType.LUCK_BOOST: "Luck",
	PassiveEffectType.ENEMY_DENSITY_BOOST: "Horde Size",
	PassiveEffectType.DAMAGE_TAKEN_REDUCTION: "Damage Taken",
}

# Effects whose value is a flat amount rather than a fraction, so the card can
# print "+15 Max Health" instead of "+1500% Max Health".
const FLAT_EFFECTS := [
	PassiveEffectType.MAX_HEALTH_BOOST,
	PassiveEffectType.ARMOR_BOOST,
	PassiveEffectType.PICKUP_RANGE_BOOST,
	PassiveEffectType.LUCK_BOOST,
]

# One line of "+X Stat" for the shop card, derived from the data rather than
# retyped into every .tres description.
func stat_line() -> String:
	var label: String = EFFECT_LABEL.get(effect_type, "Bonus")
	if effect_type == PassiveEffectType.HEALTH_REGEN_BOOST:
		return "+%.1f %s/s" % [value, label]
	if effect_type in FLAT_EFFECTS:
		return "+%d %s" % [roundi(value), label]
	if effect_type == PassiveEffectType.CRIT_DAMAGE_BOOST:
		return "+%.1fx %s" % [value, label]
	# The only stat where the good direction is down, so it prints its own sign
	# rather than reading as a drawback.
	if effect_type == PassiveEffectType.DAMAGE_TAKEN_REDUCTION:
		return "-%d%% %s" % [roundi(value * 100.0), label]
	return "+%d%% %s" % [roundi(value * 100.0), label]

# Data-driven definition of a shop passive item (a permanent relic-style trinket, as opposed to
# a WeaponData). ShopUI rolls these from a ShopPoolData and, on purchase, applies Value to
# PlayerStats according to EffectType — same shape as UpgradeData/LevelUpUI but sold for
# Grave Coin instead of offered for free on level-up.

@export var id: String = "passive_id"
@export var display_name: String = "Unnamed Relic"
@export var description: String = ""
@export var icon: Texture2D
@export var effect_type: PassiveEffectType = PassiveEffectType.DAMAGE_BOOST

# Magnitude applied on purchase; meaning depends on EffectType (e.g. +0.1 damage multiplier, +15 max HP).
@export var value: float = 0.0

@export var rarity_tier: WeaponData.RarityTier = WeaponData.RarityTier.COMMON

# Small designer dial (1-5), turned into an actual Grave Coin price by ShopEconomy.
@export var shop_cost: int = 3
