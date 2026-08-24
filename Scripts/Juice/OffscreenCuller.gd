extends Node
class_name OffscreenCuller

# Draw-only culling for far enemies: toggles CanvasItem.Visible based on distance from the
# player. Does NOT stop physics/AI (would desync chase). Lives as its own node so Enemy.cs
# (Enemy roster stage) stays untouched.

# Hide when farther than this from the player.
@export var cull_distance: float = 920.0
# Re-show when closer than CullDistance - Hysteresis (avoids edge flicker).
@export var hysteresis: float = 80.0
# Only re-evaluate every N process frames (cheap at high enemy counts).
@export var update_every_n_frames: int = 4

var _frame_counter: int

func _process(delta: float) -> void:
	_frame_counter += 1
	if _frame_counter < maxi(1, update_every_n_frames):
		return

	_frame_counter = 0

	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	var cull_sq = cull_distance * cull_distance
	var show_sq = maxf(0.0, cull_distance - hysteresis)
	show_sq *= show_sq
	var player_pos = player.global_position

	for node in get_tree().get_nodes_in_group("Enemy"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue

		var enemy = node as Node2D

		# Co-op ghosts are StaticBody2D copies; hiding them made joiners
		# lose every target.
		if enemy is EnemyProxy:
			continue

		# Skip fully inactive pooled instances (already invisible + not processing).
		if not enemy.is_physics_processing() and not enemy.visible:
			continue

		var dist_sq = player_pos.distance_squared_to(enemy.global_position)
		if enemy.visible:
			if dist_sq > cull_sq:
				enemy.visible = false
		else:
			if dist_sq < show_sq:
				enemy.visible = true
