extends Resource
class_name UpgradePoolData

# Simple data-driven container for the pool LevelUpUI draws random, non-repeating choices
# from — mirrors WaveData.EnemyPool: one resource can serve indefinitely, add more UpgradeData
# .tres files to the array to expand the pool without touching code.

@export var upgrades: Array[UpgradeData] = []
