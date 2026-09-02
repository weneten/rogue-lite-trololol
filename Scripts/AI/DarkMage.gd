extends CharacterBody2D
class_name DarkMage

# A warden the night sends after a Hunter who has outrun it.
#
# It never moves and it never closes. It plants itself as far across the arena
# as there is room for, and from there it drags on the player — the tether is
# drawn all the way to him, at any distance, because the whole point is that you
# have to go and put a stop to it. Which you have to do slowed, which is the
# cost of having been that fast.
#
# It is a plain member of the "Enemy" group with a HealthComponent under the
# name every other actor uses, so weapons target it, the HUD gives it an
# off-screen arrow, and killing it pays out. Nothing here has to know about it.
#
# The slow itself is not applied here. DarkMages owns that number, because how
# several of them stack is a decision that has to be made in one place — see
# DarkMages.combined_slow.

const SHEET_PATH := "res://Assets/sprites/enemies/wraith/wraith.png"
const SHEET_JSON := "res://Assets/sprites/enemies/wraith/wraith.json"

const TETHER_COLOR := Color(0.44, 0.16, 0.62, 0.72)
const TETHER_CORE := Color(0.86, 0.62, 1.0, 0.9)
const TETHER_WIDTH := 3.0
# Beads of light running up the tether toward the mage, so which end is doing
# this to which is never in question.
const BEAD_COUNT := 5
const BEAD_SPEED := 0.55
const BEAD_RADIUS := 4.0

const RING_RADIUS := 26.0
const FADE_SECONDS := 0.45

@export var currency_reward: int = 3
@export var experience_reward: int = 6

var _health: HealthComponent
var _sprite: AnimatedSprite2D
var _ring: Polygon2D
var _tether: Line2D
var _beads: Node2D
var _age: float
var _dismissing: bool
var _dismiss_age: float
var _dead: bool

func _ready() -> void:
	add_to_group("Enemy")
	add_to_group("DarkMage")
	z_index = 0

	_health = get_node_or_null("HealthComponent")
	if _health != null:
		_health.died.connect(_on_died)
		_health.damaged.connect(_on_damaged)

	_build_visuals()

# Called by DarkMages right after it drops one in.
func configure(max_health: int) -> void:
	if _health == null:
		return

	_health.max_health = maxi(1, max_health)
	_health.revive(_health.max_health)

# True while it is still doing something to the player. A mage that is dying, or
# has been called off, has already let go.
func get_is_channelling() -> bool:
	return not _dead and not _dismissing

# Called off, rather than killed: it fades out and frees itself. Used when the
# Hunter is no longer fast enough to deserve one.
func dismiss() -> void:
	if _dismissing or _dead:
		return

	_dismissing = true
	_dismiss_age = 0.0

func _physics_process(delta: float) -> void:
	# It stands exactly where it was put. Stated rather than implied, because a
	# CharacterBody2D that never calls move_and_slide still drifts if anything
	# else ever writes to velocity.
	velocity = Vector2.ZERO

	_age += delta
	if _dismissing:
		_dismiss_age += delta
		modulate.a = 1.0 - clampf(_dismiss_age / FADE_SECONDS, 0.0, 1.0)
		if _dismiss_age >= FADE_SECONDS:
			queue_free()
			return

	_update_visuals(delta)

func _update_visuals(delta: float) -> void:
	if _ring != null:
		var breath := 0.9 + 0.1 * sin(_age * 3.2)
		_ring.scale = Vector2.ONE * breath
		_ring.color = Color(0.36, 0.10, 0.52, 0.34 + 0.12 * sin(_age * 3.2))

	if _tether == null:
		return

	var player := get_tree().get_first_node_in_group("Player") as Node2D
	var live := player != null and get_is_channelling()
	_tether.visible = live
	if _beads != null:
		_beads.visible = live

	if not live:
		return

	# Local space: the mage does not move, so this is just the player's offset.
	var target := to_local(player.global_position)
	_tether.points = PackedVector2Array([Vector2.ZERO, target])
	_tether.width = TETHER_WIDTH * (0.85 + 0.15 * sin(_age * 6.0))

	for index in _beads.get_child_count():
		var bead := _beads.get_child(index) as Polygon2D
		if bead == null:
			continue

		# Travelling from the player back to the mage: the drag has a direction
		# and it is toward whatever is doing the dragging.
		var t := fposmod(1.0 - (_age * BEAD_SPEED + float(index) / BEAD_COUNT), 1.0)
		bead.position = target * t
		bead.color = Color(TETHER_CORE.r, TETHER_CORE.g, TETHER_CORE.b,
			TETHER_CORE.a * (0.35 + 0.65 * t))

func _build_visuals() -> void:
	# Under everything: a pool of shadow it is standing in.
	_ring = Polygon2D.new()
	_ring.z_index = -1
	var points := PackedVector2Array()
	for i in range(24):
		var a := TAU * i / 24
		points.append(Vector2(cos(a), sin(a) * 0.45) * RING_RADIUS)

	_ring.polygon = points
	_ring.color = Color(0.36, 0.10, 0.52, 0.34)
	add_child(_ring)

	_tether = Line2D.new()
	_tether.z_index = -1
	_tether.width = TETHER_WIDTH
	_tether.default_color = TETHER_COLOR
	_tether.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_tether.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_tether)

	_beads = Node2D.new()
	_beads.z_index = -1
	add_child(_beads)
	for i in range(BEAD_COUNT):
		var bead := Polygon2D.new()
		var shape := PackedVector2Array()
		for k in range(10):
			var a := TAU * k / 10
			shape.append(Vector2(cos(a), sin(a)) * BEAD_RADIUS)

		bead.polygon = shape
		bead.color = TETHER_CORE
		_beads.add_child(bead)

	var animator: EnemySpriteAnimator = get_node_or_null("SpriteAnimator")
	if animator == null:
		return

	# The wraith rig, drowned in violet. It is the only caster silhouette on
	# hand, and a hooded thing that does not walk is exactly what this is.
	if animator.configure(SHEET_PATH, SHEET_JSON, "attack", 1.6,
			Color(0.72, 0.55, 1.15, 1.0)):
		_sprite = animator.get_sprite()

func _on_damaged(amount: int, source: Node) -> void:
	var animator: EnemySpriteAnimator = get_node_or_null("SpriteAnimator")
	if animator != null:
		animator.play_hurt()

func _on_died(source: Node) -> void:
	if _dead:
		return

	_dead = true
	velocity = Vector2.ZERO
	if _tether != null:
		_tether.visible = false

	if _beads != null:
		_beads.visible = false

	if _ring != null:
		_ring.visible = false

	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.set_deferred("disabled", true)

	var animator: EnemySpriteAnimator = get_node_or_null("SpriteAnimator")
	if animator != null:
		animator.play_death_async()

	EventBus.enemy_killed.emit(self, currency_reward, experience_reward)

	var tree := get_tree()
	if tree != null:
		tree.create_timer(1.1).timeout.connect(func():
			if is_instance_valid(self):
				queue_free())
