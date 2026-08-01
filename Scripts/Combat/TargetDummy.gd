extends CharacterBody2D
class_name TargetDummy

# Stationary punching bag used to verify weapons actually land hits: logs every hit via
# HealthComponent.damaged and auto-resets its HP (instead of staying dead) so it can be
# hit repeatedly during manual testing. Belongs to the "Enemy" group so Weapon.cs's
# nearest-target search and Projectile.cs's overlap check both pick it up like a real enemy.

@export var health_component_path: NodePath
@export var auto_reset_on_death: bool = true
@export var reset_delay_seconds: float = 1.5

# Knockback velocity applied by weapon hits, decayed each physics frame.
@export var knockback_friction: float = 900.0

var _health: HealthComponent
var _knockback_velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("Enemy")

	_health = get_node_or_null(health_component_path) as HealthComponent
	if _health == null:
		push_warning("[TargetDummy] HealthComponentPath not wired; dummy cannot take damage.")
		return

	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)

func _physics_process(delta: float) -> void:
	if _knockback_velocity.length_squared() < 1.0:
		_knockback_velocity = Vector2.ZERO
		return

	velocity = _knockback_velocity
	move_and_slide()
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, knockback_friction * delta)

# Called by Weapon.cs (melee) and Projectile.cs (ranged) on a successful hit.
func apply_knockback(impulse: Vector2) -> void:
	_knockback_velocity += impulse

func _on_damaged(amount: int, source: Node) -> void:
	print("[TargetDummy] Hit for %d dmg by %s -> %d/%d HP" % [amount, source.name if source else "unknown", _health.current_health, _health.max_health])

func _on_died(source: Node) -> void:
	print("[TargetDummy] Destroyed. Resetting for further testing.")
	if auto_reset_on_death:
		get_tree().create_timer(reset_delay_seconds).timeout.connect(_reset_health)

func _reset_health() -> void:
	_health.revive()
