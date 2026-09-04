extends CharacterBody2D
class_name DarkMage

# A warden the night sends after a Hunter who has outrun it.
#
# It never closes. It arrives at the edge of the ordinary spawn ring and backs
# away from there, dragging on the player the whole time — the tether is drawn
# all the way to him, at any distance, because the whole point is that you have
# to go and put a stop to it. Which you have to do slowed, and against something
# that is walking off while you do, which is the cost of having been that fast.
#
# It retreats at a fraction of its own speed while the tether is up, so a Hunter
# always outruns it by a wide margin. Backing away is not an escape; it is a
# handful of extra seconds of the slow, and that is all it is meant to be.
#
# It is a plain member of the "Enemy" group with a HealthComponent under the
# name every other actor uses, so weapons target it, the HUD gives it an
# off-screen arrow, and killing it pays out. Nothing here has to know about it.
#
# The slow itself is not applied here. DarkMages owns that number, because how
# several of them stack is a decision that has to be made in one place — see
# DarkMages.combined_slow.

# Its own figure, drawn by the same rig as the rest of the roster and on the
# Magus's colours — see the dark_warden entry in tools/pixelforge/cast.py.
#
# It wore the boss's own artwork before this, on the argument that the thing
# planting wardens is the same figure drawn larger. The argument was sound and
# the picture was not: that sheet is a painted 160px boss, and shrinking it
# gives a small boss rather than a servant, so a wave of these read as four
# Witchfire Magi standing around the arena. Whose they are now comes from the
# hood and the purple; what they are comes from being half the mass and holding
# a staff.
const SHEET_PATH := "res://Assets/sprites/enemies/dark_warden/dark_warden.png"
const SHEET_JSON := "res://Assets/sprites/enemies/dark_warden/dark_warden.json"

# The roster's own scale on the roster's own 64px cells, so a warden stands
# beside a ghoul at the size a ghoul expects — and well under the boss, which is
# the whole point of not sharing his sheet any more.
const SPRITE_SCALE := 2.0

# Both sheets here are built from source in this repo, so this is a guard
# against a checkout that has never run tools/build_art.py rather than against
# missing artwork. The wraith rig is still a hooded caster, and a warden drawn
# in the wrong robe beats a warden that is a shadow and a tether with nothing
# in between.
const FALLBACK_SHEET_PATH := "res://Assets/sprites/enemies/wraith/wraith.png"
const FALLBACK_SHEET_JSON := "res://Assets/sprites/enemies/wraith/wraith.json"

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

# How fast it backs off. Well under any Hunter's move speed even before the
# channel cost below, because a warden that could be lost is not a warden.
@export var flee_speed: float = 170.0

# What holding the tether costs it. Channelling covers its whole life right now
# (see get_is_channelling), so the speed actually seen is the product of the two
# — the split exists so the penalty stays legible if it ever stops channelling.
const CHANNEL_SPEED_MULTIPLIER := 0.42

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
	velocity = _retreat_velocity()
	move_and_slide()
	_drive_locomotion()

	_age += delta
	if _dismissing:
		_dismiss_age += delta
		modulate.a = 1.0 - clampf(_dismiss_age / FADE_SECONDS, 0.0, 1.0)
		if _dismiss_age >= FADE_SECONDS:
			queue_free()
			return

	_update_visuals(delta)

# Straight away from the Hunter. Deliberately not pathfinding and not dodging: it is
# retreating, not escaping, and anything cleverer would turn a guaranteed catch into a
# chase the Hunter can lose.
func _retreat_velocity() -> Vector2:
	if _dead or _dismissing:
		return Vector2.ZERO

	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return Vector2.ZERO

	# The world loops, but everything has been folded around the Hunter by now, so this
	# is already the short way apart. See ArenaLoop.
	var away := global_position - player.global_position
	if away.length_squared() < 1.0:
		# Standing on him: every direction is away, so pick one that does not jitter.
		away = Vector2.RIGHT.rotated(_age)

	var speed := flee_speed
	if get_is_channelling():
		speed *= CHANNEL_SPEED_MULTIPLIER

	return away.normalized() * speed

func _drive_locomotion() -> void:
	var animator: EnemySpriteAnimator = get_node_or_null("SpriteAnimator")
	if animator == null:
		return

	var moving := velocity.length_squared() > 1.0
	animator.update_locomotion(moving)
	if moving:
		animator.set_facing(velocity.x)

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

	# Local space, so the tether stays anchored to it while it backs away.
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

	# Barely tinted: the rig already drew this figure in the Magus's purple, and
	# a full colour key over it would flatten the arcane trim back into the
	# robe. The lift is only enough to keep it off the floor under
	# CanvasModulate. "attack" is an alias of the cast row, so it resolves.
	if animator.configure(SHEET_PATH, SHEET_JSON, "attack", SPRITE_SCALE,
			Color(1.05, 0.98, 1.12, 1.0)):
		_sprite = animator.get_sprite()
		return

	# The wraith rig, drowned in violet, at the size it was drawn for.
	if animator.configure(FALLBACK_SHEET_PATH, FALLBACK_SHEET_JSON, "attack", 1.6,
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
