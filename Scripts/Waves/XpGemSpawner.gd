extends Node
class_name XpGemSpawner

# Scene-resident node (one per Arena, not an autoload — needs GetTree().CurrentScene as its
# pool container) that pools and drops an XpGem wherever an enemy dies. Listens directly to
# EventBus.OnEnemyKilled rather than routing through GameManager/WaveManager, keeping "who
# drops pickups" decoupled from "who tracks currency/waves".

@export var gem_scene: PackedScene
@export var pool_prewarm: int = 16

var _pool


func _ready() -> void:
	if gem_scene == null:
		gem_scene = load("res://Scenes/Items/XpGem.tscn")
	_pool = ObjectPool.new(gem_scene, get_tree().current_scene if get_tree().current_scene != null else self, pool_prewarm)

	EventBus.enemy_killed.connect(_on_enemy_killed)


func _on_enemy_killed(enemy: Node, currency_reward: int, experience_reward: int) -> void:
	if experience_reward <= 0 or not enemy is Node2D:
		return

	var enemy_position = enemy as Node2D
	var gem = _pool.acquire()
	gem.launch(enemy_position.global_position, experience_reward, _pool)
