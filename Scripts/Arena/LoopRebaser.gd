extends Node
class_name LoopRebaser

# Folds the world around the local Hunter once per physics frame, so the seam of the
# torus is never on screen and never in anybody's arithmetic. See ArenaLoop.
#
# Runs last, so it sees the positions every other node settled on this frame. The
# Hunter is folded onto his canonical copy, then everything else is moved to whichever
# copy of itself lies nearest to him. Both halves of that are exact multiples of the
# world size, so the frame is pixel-identical before and after: he crosses the seam
# without a hitch, and the enemy chasing him keeps chasing him.
#
# What this buys the rest of the codebase is that no other script has to know the world
# loops. After this pass every node within half a world of the Hunter carries ordinary
# coordinates, so the 40-odd distance_to / direction_to calls across the AI, weapons
# and bosses stay exactly as they were.
#
# Two roots are walked, not one. Enemies and bosses are parented under World, but XP
# gems, projectiles, traps, familiars, damage numbers and every boss VFX are pooled
# under the scene root instead. Sweeping both means a new spawner is covered wherever
# it decides to park its nodes — and a missed one would strand its gems a whole world
# away from the Hunter the first time he crossed the seam.
#
# Nodes in the ArenaBackdrop group are skipped: World itself (its children are handled
# one level down), the CanvasModulate, and ArenaVisuals, which places its own ground
# and props relative to the Hunter already and would fight this pass.

const BACKDROP_GROUP := &"ArenaBackdrop"

@export var world_root_path: NodePath = ^"../World"

func _ready() -> void:
	# Godot runs low priorities first, so a high one means "after everyone else".
	process_priority = 1000

func _physics_process(_delta: float) -> void:
	var world := get_node_or_null(world_root_path) as Node2D
	if world == null:
		return

	var hunter := _local_hunter()
	if hunter == null:
		return

	var anchor := ArenaLoop.wrap_point(hunter.global_position)
	if not anchor.is_equal_approx(hunter.global_position):
		hunter.global_position = anchor
		_cut_camera(hunter)

	_fold_children(world, hunter, anchor)

	var scene := get_tree().current_scene
	if scene != null and scene != world:
		_fold_children(scene, hunter, anchor)

func _fold_children(root: Node, hunter: Node2D, anchor: Vector2) -> void:
	for child in root.get_children():
		var node := child as Node2D
		if node == null or node == hunter:
			continue

		if node.is_in_group(BACKDROP_GROUP):
			continue

		node.global_position = ArenaLoop.rebase(anchor, node.global_position)

# The Hunter this client is actually playing. Co-op ghosts share the Player group but
# must not anchor the fold: anchoring on somebody else's Hunter would swing the local
# camera across the world every time they crossed the seam.
func _local_hunter() -> Node2D:
	for node in get_tree().get_nodes_in_group("Player"):
		if node is RemoteHunter or not is_instance_valid(node):
			continue

		var hunter := node as Node2D
		if hunter != null:
			return hunter

	return null

# A smoothed camera would read the fold as a real move and pan the whole world width.
static func _cut_camera(hunter: Node2D) -> void:
	var camera := hunter.get_node_or_null("Camera2D") as Camera2D
	if camera != null and camera.position_smoothing_enabled:
		camera.reset_smoothing()
