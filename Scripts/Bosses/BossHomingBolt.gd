extends Area2D
class_name BossHomingBolt

# Homing curse bolt used by The Hollow Cardinal. Steers toward the Player each frame,
# damages on overlap, then frees. Not pooled (boss fights spawn few bolts).

var speed: float = 220.0
var turn_rate: float = 3.5
var max_lifetime_seconds: float = 5.0
var damage: int = 12
var instigator: Node

var _direction: Vector2 = Vector2.RIGHT
var _life_remaining: float
var _active: bool = true

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2  # Player layer
	_life_remaining = max_lifetime_seconds
	# Cleared with the round, like every other projectile — see Projectile.gd.
	if EventBus != null:
		EventBus.wave_end.connect(_on_wave_end)

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 7.0
	shape.shape = circle
	add_child(shape)

	var sprite = Polygon2D.new()
	sprite.color = Color(0.55, 0.2, 0.85, 1.0)
	sprite.polygon = PackedVector2Array([
		Vector2(-8, -4), Vector2(10, 0), Vector2(-8, 4), Vector2(-4, 0)
	])
	add_child(sprite)

func launch(origin: Vector2, initial_direction: Vector2) -> void:
	global_position = origin
	_direction = initial_direction.normalized()
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT

	rotation = _direction.angle()
	_active = true
	_life_remaining = max_lifetime_seconds

func _physics_process(delta: float) -> void:
	if not _active:
		return

	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player != null:
		var desired = (player.global_position - global_position).normalized()
		_direction = _direction.lerp(desired, turn_rate * delta).normalized()
		rotation = _direction.angle()

	global_position += _direction * speed * delta

	_life_remaining -= delta
	if _life_remaining <= 0:
		queue_free()

func _on_wave_end(_wave_number: int) -> void:
	_active = false
	queue_free()

func _on_body_entered(body: Node2D) -> void:
	if not _active or not body.is_in_group("Player"):
		return

	var health: HealthComponent = body.get_node_or_null("HealthComponent")
	if health == null or health.is_dead:
		return

	health.take_damage(damage, instigator)
	_active = false
	queue_free()

static func spawn(host: Node, origin: Vector2, direction: Vector2, speed: float, damage: int,
	instigator: Node, lifetime: float = 5.0, turn_rate: float = 3.5) -> BossHomingBolt:
	var bolt = BossHomingBolt.new()
	bolt.speed = speed
	bolt.damage = damage
	bolt.instigator = instigator
	bolt.max_lifetime_seconds = lifetime
	bolt.turn_rate = turn_rate

	var parent = host.get_tree().current_scene if host.get_tree() else host.get_parent() if host.get_parent() else host
	parent.add_child(bolt)
	bolt.launch(origin, direction)
	return bolt
