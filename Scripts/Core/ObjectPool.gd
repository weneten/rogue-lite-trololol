# Generic reuse pool for pooled Node scenes (projectiles, hit-VFX, damage numbers, ...).
# Instances are instantiated once, kept parented under a container node for their whole
# life, and toggled via on_spawn/on_despawn instead of being freed/re-instantiated
# — avoids the GC churn and instantiate() cost of spawning a fresh scene every shot.
class_name ObjectPool

var _scene: PackedScene
var _container: Node
var _available: Array = []

var count_alive: int = 0

# @param scene: Scene whose root must be (or inherit) T and implement IPoolable.
# @param container: Node all pooled instances are parented under for their lifetime.
# @param prewarm_count: Instances created up front to avoid a first-use hitch.
func _init(scene: PackedScene, container: Node, prewarm_count: int = 0) -> void:
	_scene = scene
	_container = container

	for i in range(prewarm_count):
		_available.append(_create_instance())

func _create_instance() -> Node:
	var instance = _scene.instantiate()
	_container.add_child(instance)

	if instance.has_method("on_despawn"):
		instance.on_despawn()

	return instance

# Pulls a ready instance (or creates one if the pool is empty) and arms it via on_spawn().
func acquire() -> Node:
	var instance = _available.pop_back() if _available.size() > 0 else _create_instance()

	if instance.has_method("on_spawn"):
		instance.on_spawn()

	count_alive += 1
	return instance

# Disarms an instance via on_despawn() and returns it to the pool for reuse.
func return_instance(instance: Node) -> void:
	if instance.has_method("on_despawn"):
		instance.on_despawn()

	_available.append(instance)
	count_alive = maxi(0, count_alive - 1)
