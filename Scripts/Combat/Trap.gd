extends Area2D
class_name Trap

# Pooled placed hazard spawned by Weapon.place_trap for WeaponClass.Trap weapons (Iron Bear
# Trap): sits armed and invisible-to-logic until a live TargetGroup body walks over it, then
# deals damage and roots it via Enemy.apply_movement_modifier before returning to the pool — same
# spawn/despawn contract as Projectile, so it never has to be re-instantiated.

var _damage: float
var _crit_chance: float
var _crit_multiplier: float
var _target_group: String
var _root_duration_seconds: float
var _instigator: Node
var _pool: ObjectPool
var _on_damage_dealt: Callable

var _life_remaining: float
var _armed: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

# Arms/positions the trap. Called by Weapon.cs immediately after ObjectPool.acquire().
func arm(position: Vector2, pool: ObjectPool, instigator: Node, damage: float,
	crit_chance: float, crit_multiplier: float, target_group: String, root_duration_seconds: float,
	lifetime_seconds: float, on_damage_dealt: Callable = Callable()) -> void:
	global_position = position
	_pool = pool
	_instigator = instigator
	_damage = damage
	_crit_chance = crit_chance
	_crit_multiplier = crit_multiplier
	_target_group = target_group
	_root_duration_seconds = root_duration_seconds
	_on_damage_dealt = on_damage_dealt

	_life_remaining = lifetime_seconds
	_armed = true

func _physics_process(delta: float) -> void:
	if not _armed:
		return

	_life_remaining -= delta
	if _life_remaining <= 0:
		_despawn()

func _on_body_entered(body: Node2D) -> void:
	if not _armed or not body.is_in_group(_target_group):
		return

	var health = body.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.is_dead:
		return

	var is_crit = randf() < _crit_chance
	var final_damage = roundi(_damage * (_crit_multiplier if is_crit else 1.0))
	health.take_damage(final_damage, _instigator)
	if _on_damage_dealt:
		_on_damage_dealt.call(final_damage, body)

	if body is Enemy:
		var enemy = body as Enemy
		enemy.apply_movement_modifier(0.0, _root_duration_seconds)

	_despawn()

func _despawn() -> void:
	_armed = false
	if _pool:
		_pool.return_instance(self)

func on_spawn() -> void:
	visible = true
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	set_physics_process(true)

func on_despawn() -> void:
	_armed = false
	visible = false
	# Deferred: these are released from inside a collision callback, and Godot
	# forbids changing an Area2D's monitoring flags mid physics-signal flush.
	# The _active/_armed guard already stops any further processing, so the
	# one-frame lag on the flag itself changes no behaviour.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_physics_process(false)
