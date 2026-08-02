extends Node
class_name XpGemSpawner

# Scene-resident node (one per Arena, not an autoload — needs GetTree().CurrentScene as its
# pool container) that pools and drops soul shards wherever an enemy dies. Listens directly to
# EventBus.OnEnemyKilled rather than routing through GameManager/WaveManager, keeping "who
# drops pickups" decoupled from "who tracks currency/waves".
#
# A kill's whole reward — experience and coin — leaves the body as shards. Fat
# rewards break into several so a boss showers loot instead of leaving one
# pixel behind; the totals still add up exactly to what the enemy was worth.

@export var gem_scene: PackedScene
@export var pool_prewarm: int = 24
@export var max_shards_per_kill: int = 5
@export var reward_per_shard: int = 4
@export var scatter_radius: float = 26.0

var _pool


func _ready() -> void:
	if gem_scene == null:
		gem_scene = load("res://Scenes/Items/XpGem.tscn")
	_pool = ObjectPool.new(gem_scene, get_tree().current_scene if get_tree().current_scene != null else self, pool_prewarm)

	EventBus.enemy_killed.connect(_on_enemy_killed)


func _on_enemy_killed(enemy: Node, currency_reward: int, experience_reward: int) -> void:
	if not enemy is Node2D:
		return

	var xp = maxi(0, experience_reward)
	var gold = maxi(0, currency_reward)
	if xp <= 0 and gold <= 0:
		return

	var origin = (enemy as Node2D).global_position
	var shards = clampi(
		int(ceil(float(maxi(xp, gold)) / float(maxi(1, reward_per_shard)))),
		1, max_shards_per_kill)

	# Integer split with the remainder pushed onto the first shards, so the
	# payout is exact no matter how it divides.
	for i in range(shards):
		var shard_xp = xp / shards + (1 if i < xp % shards else 0)
		var shard_gold = gold / shards + (1 if i < gold % shards else 0)
		if shard_xp <= 0 and shard_gold <= 0:
			continue

		var angle = TAU * (float(i) / shards) + randf() * 0.6
		var spread = scatter_radius * (0.35 + randf() * 0.65) if shards > 1 else 0.0
		var drop_at = origin + Vector2(cos(angle), sin(angle)) * spread

		var shard = _pool.acquire()
		shard.launch(drop_at, shard_xp, shard_gold, _pool)
