class_name ShopEconomy

# Pure, static Grave Coin pricing formulas for the shop phase. Isolated from ShopUI/GameManager
# so every price/refund/reroll/bonus number in the game lives in exactly one tunable place
# instead of being scattered as magic numbers across UI code.
# TODO: rebalance vs kill-payouts/wave density once EnemyScaling (Enemy roster) is final — do not
# edit EnemyScaling from here.

# Flat Grave Coin added on top of a rarity's base cost, indexed by RarityTier
# (Common..Legendary). Keeps high-tier offers expensive without per-item hardcoding.
static var _rarity_cost_bonus: Array[int] = [0, 6, 14, 26, 45]

# WeaponData/PassiveItemData.ShopCost (designer dial ~1-5) * this + rarity bonus
# → actual Grave Coin price. Sample Common ShopCost 5 weapon = 15g; Uncommon passive 3 = 18g.
const WEAPON_COST_MULTIPLIER = 3
const PASSIVE_COST_MULTIPLIER = 4

# Fraction of a weapon's current shop price refunded when sold back.
const WEAPON_SELL_REFUND_FRACTION = 0.5

# Reroll: base + growth * rerollsThisVisit (reset each shop open).
# First reroll costs RerollBaseCost (never free); 5→7→9… discourages infinite fishing.
const REROLL_BASE_COST = 5
const REROLL_GROWTH_PER_REROLL = 2

# End-of-wave bonus: base + growth * (wave - 1). Wave 1 = 10g, wave 5 = 18g, etc.
# Stacks on top of per-kill currency so a cleared wave always pays something.
const WAVE_END_BONUS_BASE = 10
const WAVE_END_BONUS_GROWTH_PER_WAVE = 2


static func get_weapon_price(data) -> int:
	if data == null:
		return 0

	return maxi(1, data.shop_cost * WEAPON_COST_MULTIPLIER + _rarity_bonus(data.rarity_tier))


static func get_weapon_sell_value(data) -> int:
	return roundi(get_weapon_price(data) * WEAPON_SELL_REFUND_FRACTION)


static func get_passive_price(data) -> int:
	if data == null:
		return 0

	return maxi(1, data.shop_cost * PASSIVE_COST_MULTIPLIER + _rarity_bonus(data.rarity_tier))


# How many times the shop has already been rerolled since it opened.
static func get_reroll_cost(rerolls_this_visit: int) -> int:
	return REROLL_BASE_COST + REROLL_GROWTH_PER_REROLL * maxi(0, rerolls_this_visit)


# The wave number that just ended.
static func get_wave_end_bonus(wave_number_completed: int) -> int:
	return WAVE_END_BONUS_BASE + WAVE_END_BONUS_GROWTH_PER_WAVE * maxi(0, wave_number_completed - 1)


static func _rarity_bonus(tier: int) -> int:
	var index = clampi(tier, 0, _rarity_cost_bonus.size() - 1)
	return _rarity_cost_bonus[index]
