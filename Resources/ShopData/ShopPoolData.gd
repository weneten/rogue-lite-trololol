extends Resource
class_name ShopPoolData

# Data-driven container for everything ShopUI can roll for sale — mirrors WaveData.EnemyPool /
# UpgradePoolData.Upgrades: one resource serves indefinitely, add more WeaponData/PassiveItemData
# .tres entries to the arrays to expand the shop without touching code.

@export var weapon_pool: Array[WeaponData] = []
@export var passive_pool: Array[PassiveItemData] = []
