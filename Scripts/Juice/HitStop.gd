extends Node
class_name HitStop

# Brief Engine.TimeScale dip for impactful hits. Uses a SceneTreeTimer with ignoreTimeScale
# so the freeze always ends in real time even while scaled. Stacking calls extend/refresh
# rather than nesting multiple scale restores.

# Softer default — 0.08 felt like full freeze and stacked into permanent slowmo.
@export var default_time_scale: float = 0.35
@export var default_duration_seconds: float = 0.03

var _active: bool
var _restore_scale: float = 1.0
var _token: int

func _ready() -> void:
	# Survive tree pauses (level-up/shop) so a hitstop started on the same frame still restores.
	process_mode = Node.PROCESS_MODE_ALWAYS

# Dips TimeScale for durationSeconds, then restores the pre-dip scale.
func freeze(duration_seconds: float = -1.0, time_scale: float = -1.0) -> void:
	if duration_seconds < 0.0:
		duration_seconds = default_duration_seconds

	if time_scale < 0.0:
		time_scale = default_time_scale

	if duration_seconds <= 0.0:
		return

	# First freeze captures the real scale; stacked freezes just refresh the timer.
	if not _active:
		_restore_scale = Engine.time_scale
		if _restore_scale <= 0.001:
			_restore_scale = 1.0

	_active = true
	_token += 1
	var my_token = _token
	Engine.time_scale = time_scale

	# processAlways + ignoreTimeScale: timer runs in wall-clock seconds, not game time.
	var timer = get_tree().create_timer(duration_seconds, true, true)
	await timer.timeout

	# Only the latest Freeze owns the restore (older awaits no-op).
	if my_token != _token:
		return

	Engine.time_scale = _restore_scale
	_active = false
