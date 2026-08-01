extends Node
class_name ScreenShake

# Camera2D offset shake driven by a decaying trauma value (0..1). Bind a camera once,
# then call add_trauma / shake from combat juice hooks. Offset is restored when trauma hits 0.

# Max pixel offset at full trauma (trauma^2 * MaxOffset).
@export var max_offset: float = 10.0
# How fast trauma drains per second.
@export var trauma_decay_per_second: float = 1.6

var _camera: Camera2D
var _base_offset: Vector2
var _trauma: float

func bind(camera: Camera2D) -> void:
	# Drop any residual offset on the previous camera before rebinding.
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = _base_offset

	_camera = camera
	_base_offset = camera.offset if camera != null else Vector2.ZERO
	_trauma = 0.0

# Adds trauma clamped to [0,1]. Small hits ~0.15–0.25; big hits ~0.4–0.7.
func add_trauma(amount: float) -> void:
	if amount <= 0.0:
		return

	_trauma = clampf(_trauma + amount, 0.0, 1.0)

# Convenience: map a strength/duration pair into trauma (duration only soft-caps decay feel).
func shake(strength: float, duration_seconds: float = 0.2) -> void:
	# Duration stretches decay slightly so a longer call doesn't vanish in one frame.
	if duration_seconds > 0.0 and trauma_decay_per_second > 0.0:
		var needed = strength / maxf(0.01, duration_seconds * trauma_decay_per_second)
		add_trauma(clampf(maxf(strength, needed * 0.15), 0.0, 1.0))
	else:
		add_trauma(strength)

func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return

	if _trauma <= 0.0:
		_camera.offset = _base_offset
		return

	_trauma = maxf(0.0, _trauma - trauma_decay_per_second * delta)
	# Quadratic falloff: low trauma barely moves the cam, high trauma punches hard.
	var shake_amount = _trauma * _trauma
	var ox = randf_range(-1.0, 1.0) * max_offset * shake_amount
	var oy = randf_range(-1.0, 1.0) * max_offset * shake_amount
	_camera.offset = _base_offset + Vector2(ox, oy)
