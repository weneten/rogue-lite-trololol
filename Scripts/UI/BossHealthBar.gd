extends CanvasLayer
class_name BossHealthBar

# Souls-style boss bar: a wide, thin strip low on the screen with the boss's
# name over it. Rises when the encounter starts, stays for the fight, and gets
# a moment of its own when the boss dies.
#
# Two bars are stacked. The one behind is the damage trail — it holds where the
# health was, then drains down to meet it a beat later. That lag is the whole
# reason the style reads: a single bar tells you how much is left, the pair
# tells you how much you just took off, which is the number a player actually
# wants after a hit lands.
#
# It listens to EventBus for the encounter and to the boss's own
# HealthComponent for the value, so nothing in the fight has to know the bar
# exists.

@export var root_path: NodePath
@export var name_label_path: NodePath
@export var trail_bar_path: NodePath
@export var health_bar_path: NodePath
@export var bars_path: NodePath
@export var frame_path: NodePath

# How long the trail holds before it starts giving ground.
const TRAIL_HOLD := 0.45
# Fraction of the remaining gap the trail closes per second once it moves.
const TRAIL_SPEED := 1.9
const FADE_SECONDS := 0.35
# How long the emptied bar stays up after the kill, so the moment lands.
const DEATH_HOLD := 1.6

var _root: Control
var _name_label: Label
var _trail_bar: ProgressBar
var _health_bar: ProgressBar
var _bars: Control
var _frame: Control

var _boss: Boss
var _health: HealthComponent
var _fraction: float = 1.0
var _trail: float = 1.0
var _hold_remaining: float
var _shown: bool

func _ready() -> void:
	_root = get_node_or_null(root_path)
	_name_label = get_node_or_null(name_label_path)
	_trail_bar = get_node_or_null(trail_bar_path)
	_health_bar = get_node_or_null(health_bar_path)
	_bars = get_node_or_null(bars_path)
	_frame = get_node_or_null(frame_path)

	if _root != null:
		_root.visible = false

	if EventBus != null:
		EventBus.boss_encounter_start.connect(_on_encounter_start)
		EventBus.boss_encounter_end.connect(_on_encounter_end)

	set_process(false)

func _exit_tree() -> void:
	if EventBus != null:
		EventBus.boss_encounter_start.disconnect(_on_encounter_start)
		EventBus.boss_encounter_end.disconnect(_on_encounter_end)

	_disconnect_health()

func _process(delta: float) -> void:
	if _hold_remaining > 0.0:
		_hold_remaining -= delta
	elif _trail > _fraction:
		_trail = maxf(_fraction, _trail - (_trail - _fraction) * TRAIL_SPEED * delta - 0.02 * delta)

	# A trail that healed back up would be a second health bar, so it only ever
	# comes down; a boss that heals just pushes the red back under it.
	_trail = maxf(_trail, _fraction)

	if _trail_bar != null:
		_trail_bar.value = _trail

	if _health_bar != null:
		_health_bar.value = _fraction

# ---------------------------------------------------------------------------
# Encounter
# ---------------------------------------------------------------------------
func _on_encounter_start(boss_name: String, _wave_number: int) -> void:
	# The boss is added to the tree in the same frame this fires, so the node
	# is fetched a frame later rather than raced for here.
	_bind_boss.call_deferred(boss_name)

func _bind_boss(boss_name: String) -> void:
	_disconnect_health()

	_boss = BossManager.get_active_boss() if BossManager != null else null
	_health = _boss.get_node_or_null("HealthComponent") if _boss != null else null

	if _health != null:
		_health.health_changed.connect(_on_health_changed)
		_fraction = _hp_fraction(_health.current_health, _health.max_health)
	else:
		_fraction = 1.0

	_trail = _fraction
	_hold_remaining = 0.0

	if _name_label != null:
		# Upper case rather than a small-caps font: the bitmap font has no
		# small-caps variant, and the shout is the point.
		_name_label.text = boss_name.to_upper()

	_show()

func _on_encounter_end(_boss_name: String, defeated: bool) -> void:
	_disconnect_health()

	if not _shown:
		return

	if defeated:
		# Let the empty bar sit for a moment before it goes.
		_fraction = 0.0
		var tree := get_tree()
		if tree != null:
			tree.create_timer(DEATH_HOLD).timeout.connect(_hide)
			return

	_hide()

func _on_health_changed(current_health: int, max_health: int) -> void:
	var next := _hp_fraction(current_health, max_health)
	if next < _fraction:
		# Only damage refreshes the hold; a heal should not freeze the trail.
		_hold_remaining = TRAIL_HOLD
		# Flash rather than shake: the bar lives in a VBoxContainer, which
		# rewrites its children's positions every layout pass, so a positional
		# nudge would be fought by the container. Modulate is nobody else's.
		if _health_bar != null:
			UIAnim.flash(_health_bar, Color(1.7, 1.35, 1.35), 0.14)

	_fraction = next

func _disconnect_health() -> void:
	if _health != null and is_instance_valid(_health) and _health.health_changed.is_connected(_on_health_changed):
		_health.health_changed.disconnect(_on_health_changed)

	_health = null
	_boss = null

# ---------------------------------------------------------------------------
# Show / hide
# ---------------------------------------------------------------------------
func _show() -> void:
	if _root == null:
		return

	_shown = true
	set_process(true)
	_root.visible = true
	_root.modulate.a = 0.0

	var tween := _root.create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, FADE_SECONDS)

	# Rises into place rather than appearing: the encounter is an event.
	if _frame != null:
		var rest := _frame.position
		_frame.position = rest + Vector2(0, 20)
		var slide := _frame.create_tween()
		slide.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		slide.tween_property(_frame, "position", rest, FADE_SECONDS * 1.4)

func _hide() -> void:
	if _root == null or not _shown:
		return

	_shown = false
	var tween := _root.create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func():
		if _root != null:
			_root.visible = false

		set_process(false))

static func _hp_fraction(current_health: int, max_health: int) -> float:
	if max_health <= 0:
		return 0.0

	return clampf(float(current_health) / float(max_health), 0.0, 1.0)
