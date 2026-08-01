extends Area2D
class_name XpGem

# Pooled soul-gem pickup dropped on enemy death (see XpGemSpawner). Idles in place until the
# player gets within AttractRadius, then drifts toward them (Brotato-style magnetism) and
# grants XP to PlayerStats on overlap.

@export var attract_radius: float = 90.0
@export var attract_speed: float = 500.0

var _xp_value: int
var _pool
var _active: bool

func _ready() -> void:
	body_entered.connect(_on_body_entered)

# Arms this pooled instance at the given position with the given XP payout. Called by XpGemSpawner right after ObjectPool.Get().
func launch(position: Vector2, xp_value: int, pool) -> void:
	global_position = position
	_xp_value = xp_value
	_pool = pool
	_active = true

func _physics_process(delta: float) -> void:
	if not _active:
		return

	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	if global_position.distance_to(player.global_position) <= attract_radius:
		global_position = global_position.move_toward(player.global_position, attract_speed * delta)

func _on_body_entered(body: Node2D) -> void:
	if not _active or not body.is_in_group("Player"):
		return

	PlayerStats.instance.add_xp(_xp_value)
	_despawn()

func _despawn() -> void:
	_active = false
	if _pool:
		_pool.return_object(self)

func on_spawn() -> void:
	visible = true
	monitoring = true
	monitorable = true
	set_physics_process(true)

func on_despawn() -> void:
	_active = false
	visible = false
	monitoring = false
	monitorable = false
	set_physics_process(false)
