extends CanvasLayer
class_name HUD

# Always-on in-run HUD: HP/XP bars, wave number + timer, currency, and off-screen enemy
# direction arrows. Syncs initial state from autoloads then listens to EventBus.

@export_group("Wiring")
@export var health_bar_path: NodePath
@export var xp_bar_path: NodePath
@export var wave_label_path: NodePath
@export var timer_label_path: NodePath
@export var currency_label_path: NodePath
@export var arrow_layer_path: NodePath

@export_group("Offscreen Arrows")
@export var max_offscreen_arrows: int = 12
@export var arrow_edge_padding: float = 28.0
@export var arrow_min_distance: float = 40.0

var _health_bar: ProgressBar
var _xp_bar: ProgressBar
var _wave_label: Label
var _timer_label: Label
var _currency_label: Label
var _arrow_layer: Control
var _arrow_pool: Array[Label] = []

func _ready() -> void:
	_health_bar = get_node_or_null(health_bar_path)
	_xp_bar = get_node_or_null(xp_bar_path)
	_wave_label = get_node_or_null(wave_label_path)
	_timer_label = get_node_or_null(timer_label_path)
	_currency_label = get_node_or_null(currency_label_path)
	_arrow_layer = get_node_or_null(arrow_layer_path)

	_ensure_arrow_layer()
	_build_arrow_pool()

	EventBus.player_health_changed.connect(_on_player_health_changed)
	EventBus.xp_changed.connect(_on_xp_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.wave_start.connect(_on_wave_start)

	_sync_initial_state()

func _process(delta: float) -> void:
	_update_wave_timer()
	_update_offscreen_arrows()

func _ensure_arrow_layer() -> void:
	if _arrow_layer != null:
		return

	_arrow_layer = Control.new()
	_arrow_layer.name = "OffscreenArrows"
	_arrow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrow_layer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_arrow_layer.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_arrow_layer)

func _build_arrow_pool() -> void:
	for i in range(max_offscreen_arrows):
		var arrow = Label.new()
		arrow.text = "◆"
		arrow.visible = false
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arrow.add_theme_color_override("font_color", Color(0.85, 0.15, 0.18, 0.9))
		arrow.add_theme_font_size_override("font_size", 18)
		arrow.pivot_offset = Vector2(10, 10)
		arrow.size = Vector2(20, 20)
		_arrow_layer.add_child(arrow)
		_arrow_pool.append(arrow)

func _sync_initial_state() -> void:
	if GameManager != null:
		_on_currency_changed(GameManager.currency)
		_on_wave_start(GameManager.wave_number)

	if PlayerStats.instance != null:
		_on_xp_changed(PlayerStats.instance.current_xp, PlayerStats.instance.xp_to_next_level, PlayerStats.instance.level)

	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player != null:
		var health = player.get_node_or_null("HealthComponent") as HealthComponent
		if health != null:
			_on_player_health_changed(health.current_health, health.max_health)

func _update_wave_timer() -> void:
	if _timer_label == null or WaveManager == null:
		return

	if WaveManager.is_wave_active:
		_timer_label.text = "%.0fs" % maxf(0.0, WaveManager.wave_time_remaining)
	else:
		_timer_label.text = "Next wave in %.0fs" % maxf(0.0, WaveManager.time_until_next_wave)

func _update_offscreen_arrows() -> void:
	if _arrow_layer == null or _arrow_pool.is_empty():
		return

	# Hide all first.
	for i in range(_arrow_pool.size()):
		_arrow_pool[i].visible = false

	var player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return

	var viewport = get_viewport()
	if viewport == null:
		return

	var visible = viewport.get_visible_rect()
	var screen_center = visible.position + visible.size * 0.5
	var pad = arrow_edge_padding
	var inner = Rect2(
		visible.position + Vector2(pad, pad),
		visible.size - Vector2(pad * 2.0, pad * 2.0))

	var arrow_index = 0
	for node in get_tree().get_nodes_in_group("Enemy"):
		if arrow_index >= _arrow_pool.size():
			break

		if not (node is Node2D):
			continue
		var enemy = node as Node2D
		if not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue

		# Skip inactive/pooled (common pattern: hidden or process disabled).
		if not enemy.visible or enemy.get_parent() == null:
			continue

		var screen_pos = enemy.get_global_transform_with_canvas().origin
		if inner.has_point(screen_pos):
			continue

		var dir = screen_pos - screen_center
		if dir.length_squared() < arrow_min_distance * arrow_min_distance:
			continue

		dir = dir.normalized()
		var edge = _clamp_to_rect_edge(screen_center, dir, inner)
		var arrow = _arrow_pool[arrow_index]
		arrow_index += 1
		arrow.position = edge - arrow.size * 0.5
		arrow.rotation = dir.angle() + PI * 0.5  # diamond tip toward threat
		arrow.visible = true

# Ray from center along dir hits the padded rect edge.
static func _clamp_to_rect_edge(center: Vector2, dir: Vector2, rect: Rect2) -> Vector2:
	var t_min = INF

	# Intersect with each of the 4 edges of the rect, keep nearest positive hit.
	if absf(dir.x) > 0.0001:
		var t_left = (rect.position.x - center.x) / dir.x
		if t_left > 0:
			var p = center + dir * t_left
			if p.y >= rect.position.y and p.y <= rect.end.y:
				t_min = minf(t_min, t_left)

		var t_right = (rect.end.x - center.x) / dir.x
		if t_right > 0:
			var p = center + dir * t_right
			if p.y >= rect.position.y and p.y <= rect.end.y:
				t_min = minf(t_min, t_right)

	if absf(dir.y) > 0.0001:
		var t_top = (rect.position.y - center.y) / dir.y
		if t_top > 0:
			var p = center + dir * t_top
			if p.x >= rect.position.x and p.x <= rect.end.x:
				t_min = minf(t_min, t_top)

		var t_bottom = (rect.end.y - center.y) / dir.y
		if t_bottom > 0:
			var p = center + dir * t_bottom
			if p.x >= rect.position.x and p.x <= rect.end.x:
				t_min = minf(t_min, t_bottom)

	if t_min == INF:
		return center + dir * 100.0

	return center + dir * t_min

func _on_player_health_changed(current_health: int, max_health: int) -> void:
	if _health_bar == null:
		return

	_health_bar.max_value = max_health
	_health_bar.value = current_health

func _on_xp_changed(current_xp: int, xp_to_next_level: int, level: int) -> void:
	if _xp_bar == null:
		return

	_xp_bar.max_value = xp_to_next_level
	_xp_bar.value = current_xp

func _on_currency_changed(current_currency: int) -> void:
	if _currency_label != null:
		_currency_label.text = "%d" % current_currency

func _on_wave_start(wave_number: int) -> void:
	if _wave_label != null:
		_wave_label.text = "Wave %d" % wave_number
