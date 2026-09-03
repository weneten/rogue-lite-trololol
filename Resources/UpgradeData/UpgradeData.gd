extends Resource
class_name UpgradeData

# What effect an upgrade choice applies on selection.
enum UpgradeType {
	DAMAGE_BOOST,
	MOVE_SPEED_BOOST,
	MAX_HEALTH_BOOST,
	ATTACK_SPEED_BOOST
}

# Data-driven definition of a single level-up choice. LevelUpUI rolls a few of these from an
# UpgradePoolData and, on selection, applies Value to PlayerStats according to UpgradeType.

@export var id: String = "upgrade_id"
@export var display_name: String = "Unnamed Upgrade"
@export var description: String = ""
@export var icon: Texture2D
@export var upgrade_type: UpgradeType = UpgradeType.DAMAGE_BOOST

# Magnitude applied on selection; meaning depends on UpgradeType (e.g. +0.15 damage
# multiplier, +20 max HP, +0.12 attack speed).
@export var value: float = 0.0

# Relative weight in LevelUpUI's random draw.
@export var weight: float = 1.0
