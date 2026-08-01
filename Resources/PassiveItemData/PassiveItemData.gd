extends Resource
class_name PassiveItemData

# What stat a passive item permanently boosts on purchase. Mirrors UpgradeType's numeric
# effects (no Passive/relic-placeholder case here since these ARE the relics).
enum PassiveEffectType {
	DAMAGE_BOOST,
	MOVE_SPEED_BOOST,
	MAX_HEALTH_BOOST
}

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
