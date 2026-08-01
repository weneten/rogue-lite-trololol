extends Resource
class_name WaveData

# Data-driven definition of the enemy spawn pool WaveManager draws from and the formulas it
# scales per-wave. One WaveData can serve indefinitely — WaveManager keeps advancing
# CurrentWave and re-evaluating the growth formulas rather than requiring one resource per wave.

# Enemy archetypes this wave can spawn. Selection is weighted by EnemyData.SpawnWeight
# and filtered by EnemyData.MinWaveToAppear.
@export var enemy_pool: Array[EnemyData] = []

@export var base_duration: float = 30.0

# Seconds added to BaseDuration per wave past the first, before the 20-90s clamp.
@export var duration_growth_per_wave: float = 2.0
@export var spawn_interval: float = 1.2

# Starting concurrent-alive pressure (not a total spawn quota). WaveManager keeps
# spawning on SpawnInterval for the whole wave duration until this cap (scaled by wave).
@export var base_enemy_count: int = 8
@export var enemy_count_growth_per_wave: float = 1.5
