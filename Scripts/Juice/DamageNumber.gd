extends Node2D
class_name DamageNumber

# Pooled floating damage popup. JuiceController pulls one from ObjectPool, calls ShowAt(),
# and this node floats up / fades then Returns itself. Root must be Node2D with a Label child.

@export var rise_speed: float = 48.0
@export var lifetime_seconds: float = 0.55
@export var fade_start_fraction: float = 0.45
@export var label_path: NodePath = "Label"

var _label: Label
var _pool
var _remaining: float
var _lifetime: float
var _active: bool
var _drift: Vector2

func _ready() -> void:
	_label = get_node_or_null(label_path)
	if _label == null:
		push_warning("[DamageNumber] LabelPath not wired; popup will be blank.")

# Arms the popup at world position with the given amount/color. Call right after pool.Get().
func show_at(world_position: Vector2, amount: int, color: Color, pool) -> void:
	_pool = pool
	global_position = world_position + Vector2(randf_range(-6.0, 6.0), randf_range(-10.0, -2.0))
	_lifetime = lifetime_seconds
	_remaining = lifetime_seconds
	_active = true
	# Slight horizontal drift so stacked hits on the same target don't fully overlap.
	_drift = Vector2(randf_range(-12.0, 12.0), 0.0)

	if _label != null:
		_label.text = str(amount)
		_label.modulate = color

	modulate = Color.WHITE

func _process(delta: float) -> void:
	if not _active:
		return

	var dt = delta
	_remaining -= dt
	global_position += (Vector2.UP * rise_speed + _drift) * dt

	# Fade after FadeStartFraction of life is spent.
	var lived = 1.0 - clampf(_remaining / maxf(0.001, _lifetime), 0.0, 1.0)
	if lived >= fade_start_fraction:
		var fade_t = (lived - fade_start_fraction) / maxf(0.001, 1.0 - fade_start_fraction)
		modulate = Color(1.0, 1.0, 1.0, 1.0 - fade_t)

	if _remaining <= 0.0:
		_active = false
		if _pool:
			_pool.return_object(self)

func on_spawn() -> void:
	visible = true
	set_process(true)
	modulate = Color.WHITE

func on_despawn() -> void:
	_active = false
	visible = false
	set_process(false)
	if _label != null:
		_label.text = ""
