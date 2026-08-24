extends Area2D
class_name Projectile

# Pooled ranged-attack projectile. Weapon.cs pulls one from its ObjectPool<Projectile>,
# calls launch() to arm/aim it, and the projectile returns itself to the pool on hit or
# timeout — it never free()s itself, so the pool never has to re-instantiate.

@export var speed: float = 600.0
@export var max_lifetime_seconds: float = 3.0

var _damage: float
var _crit_chance: float
var _crit_multiplier: float
var _knockback: float
var _target_group: String
var _instigator: Node
# Optional hook fired with (final_damage, hit_body) after a successful hit — used by
# Weapon.cs to forward ranged hits into PlayerStats.notify_damage_dealt (lifesteal, on-hit
# passives) the same way melee hits do. Null for non-player-fired projectiles (e.g. enemies).
var _on_damage_dealt: Callable

var _direction: Vector2 = Vector2.RIGHT
var _life_remaining: float
var _pool: ObjectPool
var _active: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

# Arms and aims the projectile. Called by Weapon.cs immediately after ObjectPool.acquire().
func launch(origin_position: Vector2, direction: Vector2, pool: ObjectPool, instigator: Node,
	damage: float, crit_chance: float, crit_multiplier: float, knockback: float, target_group: String,
	on_damage_dealt: Callable = Callable()) -> void:
	global_position = origin_position
	_direction = direction.normalized()
	rotation = _direction.angle()

	_pool = pool
	_instigator = instigator
	_damage = damage
	_crit_chance = crit_chance
	_crit_multiplier = crit_multiplier
	_knockback = knockback
	_target_group = target_group
	_on_damage_dealt = on_damage_dealt

	_life_remaining = max_lifetime_seconds
	_active = true

func _physics_process(delta: float) -> void:
	if not _active:
		return

	global_position += _direction * speed * delta

	_life_remaining -= delta
	if _life_remaining <= 0:
		_despawn()

func _on_body_entered(body: Node2D) -> void:
	if not _active:
		return
	if not body.is_in_group(_target_group) and not (body is EnemyProxy):
		return

	var health = body.get_node_or_null("HealthComponent") as HealthComponent
	if health == null or health.is_dead:
		return

	var is_crit = randf() < _crit_chance
	var final_damage = roundi(_damage * (_crit_multiplier if is_crit else 1.0))
	health.take_damage(final_damage, _instigator)
	if _on_damage_dealt:
		_on_damage_dealt.call(final_damage, body)

	if body is TargetDummy:
		var dummy = body as TargetDummy
		if _knockback > 0.0:
			dummy.apply_knockback(_direction * _knockback)

	_despawn()

func _despawn() -> void:
	_active = false
	if _pool:
		_pool.return_instance(self)

func on_spawn() -> void:
	visible = true
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	set_physics_process(true)

func on_despawn() -> void:
	_active = false
	visible = false
	# Deferred: these are released from inside a collision callback, and Godot
	# forbids changing an Area2D's monitoring flags mid physics-signal flush.
	# The _active/_armed guard already stops any further processing, so the
	# one-frame lag on the flag itself changes no behaviour.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_physics_process(false)
