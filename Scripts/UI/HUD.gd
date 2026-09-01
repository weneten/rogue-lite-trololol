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
@export var health_label_path: NodePath
@export var level_label_path: NodePath
@export var banner_path: NodePath
@export var banner_label_path: NodePath
@export var banner_sub_label_path: NodePath
@export var damage_flash_path: NodePath
@export var vitals_panel_path: NodePath
@export var weapon_bar_path: NodePath
@export var weapon_slots_path: NodePath

@export_group("Weapon Bar")
# The counters climb constantly during a fight; refreshing them every frame is
# both wasted work and unreadable. Four times a second is fast enough to feel
# live and slow enough to actually read.
@export var weapon_bar_refresh_seconds: float = 0.25

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
var _arrow_pool: Array[TextureRect] = []
var _health_label: Label
var _level_label: Label
var _banner: Control
var _banner_label: Label
var _banner_sub_label: Label
var _damage_flash: Control
var _vitals_panel: Control
var _last_health: int = -1
var _last_currency: int = 0
var _last_level: int = 1
var _arrow_texture: Texture2D
var _pulse_time: float = 0.0
var _weapon_bar: Control
var _weapon_slots: HBoxContainer
# One entry per equipped weapon, in slot order: the Weapon it reads and the
# Label it writes. Rebuilt only when the loadout itself changes.
var _weapon_rows: Array = []
var _weapon_bar_cooldown: float = 0.0
var _arrow_frame: int = 0

func _ready() -> void:
	_health_bar = get_node_or_null(health_bar_path)
	_xp_bar = get_node_or_null(xp_bar_path)
	_wave_label = get_node_or_null(wave_label_path)
	_timer_label = get_node_or_null(timer_label_path)
	_currency_label = get_node_or_null(currency_label_path)
	_arrow_layer = get_node_or_null(arrow_layer_path)
	_health_label = get_node_or_null(health_label_path)
	_level_label = get_node_or_null(level_label_path)
	_banner = get_node_or_null(banner_path)
	_banner_label = get_node_or_null(banner_label_path)
	_banner_sub_label = get_node_or_null(banner_sub_label_path)
	_damage_flash = get_node_or_null(damage_flash_path)
	_vitals_panel = get_node_or_null(vitals_panel_path)
	_weapon_bar = get_node_or_null(weapon_bar_path)
	_weapon_slots = get_node_or_null(weapon_slots_path)
	_arrow_texture = load("res://Assets/UI/icon_skull.png") as Texture2D

	if _banner != null:
		_banner.modulate.a = 0.0

	EventBus.player_health_changed.connect(_on_player_health_changed)
	EventBus.xp_changed.connect(_on_xp_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.wave_start.connect(_on_wave_start)

	_finish_setup.call_deferred()

func _finish_setup() -> void:
	_ensure_arrow_layer()
	_build_arrow_pool()
	_sync_initial_state()

func _process(delta: float) -> void:
	_pulse_time += delta
	_update_wave_timer()
	_arrow_frame += 1
	if _arrow_frame >= 4:
		_arrow_frame = 0
		_update_offscreen_arrows()
	_update_low_health_pulse()

	_weapon_bar_cooldown -= delta
	if _weapon_bar_cooldown <= 0.0:
		_weapon_bar_cooldown = weapon_bar_refresh_seconds
		_update_weapon_bar()

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
		# A pixel skull reads at a glance where a text glyph did not, and it
		# matches the rest of the icon set.
		var arrow = TextureRect.new()
		arrow.texture = _arrow_texture
		arrow.visible = false
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		arrow.custom_minimum_size = Vector2(20, 20)
		arrow.size = Vector2(20, 20)
		arrow.pivot_offset = Vector2(10, 10)
		arrow.modulate = Color(1.0, 0.55, 0.55, 0.85)
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
		# On difficulties where the wave waits for the boss, the timer has
		# already run out and would sit at a stuck "0s" for the whole fight.
		if BossManager != null and BossManager.is_boss_active and WaveManager.wave_time_remaining <= 0.0:
			_timer_label.text = "SLAY IT"
		else:
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
		# Bob along the bearing instead of rotating — an upright skull stays
		# readable, a spinning one does not.
		arrow.position += dir * (2.0 + sin(_pulse_time * 6.0 + arrow_index) * 2.0)
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

# --------------------------------------------------------------- weapon bar

# A strip along the bottom of the screen: every equipped weapon, and what it has
# actually done this wave. Which of six slots is carrying the run — and which is
# dead weight worth selling — is otherwise invisible, because damage numbers in
# a swarm are unattributable.
func _update_weapon_bar() -> void:
	if _weapon_slots == null:
		return

	var inventory := WeaponInventory.instance
	if inventory == null:
		if _weapon_bar != null:
			_weapon_bar.visible = false
		return

	var equipped := inventory.equipped_weapons
	if _weapon_bar != null:
		# Nothing equipped means an empty panel floating at the bottom of the
		# screen, which reads as a bug rather than as information.
		_weapon_bar.visible = not equipped.is_empty()

	if not _weapon_rows_match(equipped):
		_rebuild_weapon_rows(equipped)

	# Share of the wave's damage, so the bar answers "which weapon is pulling its
	# weight" and not just "which weapon has the biggest number", which is
	# already obvious from the numbers themselves.
	var total: int = 0
	for weapon in equipped:
		total += weapon.damage_this_wave

	for row in _weapon_rows:
		var weapon: Weapon = row["weapon"]
		if not is_instance_valid(weapon):
			continue

		var label: Label = row["label"]
		label.text = str(weapon.damage_this_wave)

		var share: float = float(weapon.damage_this_wave) / float(total) if total > 0 else 0.0
		# Top contributor burns gold, the rest fade toward grey by contribution.
		label.modulate = Color(0.62, 0.62, 0.66).lerp(Color(1.0, 0.82, 0.35), minf(1.0, share * 2.0))

# Cheap identity check so the strip is only rebuilt when the loadout actually
# changed — buying, selling, or a fresh run — rather than four times a second.
func _weapon_rows_match(equipped: Array) -> bool:
	if _weapon_rows.size() != equipped.size():
		return false

	for i in range(equipped.size()):
		if _weapon_rows[i]["weapon"] != equipped[i]:
			return false

	return true

func _rebuild_weapon_rows(equipped: Array) -> void:
	for child in _weapon_slots.get_children():
		child.queue_free()
	_weapon_rows.clear()

	for weapon in equipped:
		var data: WeaponData = weapon.data
		if data == null:
			continue

		var slot := VBoxContainer.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_constant_override("separation", 1)
		_weapon_slots.add_child(slot)

		var icon := TextureRect.new()
		icon.texture = data.icon
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)

		var label := Label.new()
		label.text = "0"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.theme_type_variation = &"StatLabel"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(label)

		_weapon_rows.append({"weapon": weapon, "label": label})

func _on_player_health_changed(current_health: int, max_health: int) -> void:
	if _health_bar == null:
		return

	_health_bar.max_value = max_health
	UIAnim.tween_bar(_health_bar, float(current_health), 0.25)

	if _health_label != null:
		_health_label.text = "%d / %d" % [current_health, max_health]

	var took_damage = _last_health >= 0 and current_health < _last_health
	var healed = _last_health >= 0 and current_health > _last_health
	_last_health = current_health

	if took_damage:
		_flash_damage()
		UIAnim.shake(_vitals_panel, 6.0, 0.22)
	elif healed and _health_label != null:
		UIAnim.punch(_health_label, 1.15)

func _flash_damage() -> void:
	if _damage_flash == null:
		return

	# Peak well below 1.0: this fires on every hit, and in a swarm that is
	# many times a second. It should read as a pulse at the edge of vision,
	# not as a colour grade over the whole arena.
	_damage_flash.modulate.a = 0.55
	var tween = _damage_flash.create_tween()
	tween.tween_property(_damage_flash, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_OUT)

# Below a quarter health the vitals panel breathes red so you feel it in
# peripheral vision without having to read the number.
func _update_low_health_pulse() -> void:
	if _vitals_panel == null or _health_bar == null or _health_bar.max_value <= 0.0:
		return

	var ratio = _health_bar.value / _health_bar.max_value
	if ratio <= 0.25:
		var beat = 0.6 + 0.4 * sin(_pulse_time * 7.0)
		_vitals_panel.modulate = Color(1.0, beat, beat, 1.0)
	else:
		_vitals_panel.modulate = Color.WHITE

func _on_xp_changed(current_xp: int, xp_to_next_level: int, level: int) -> void:
	if _xp_bar == null:
		return

	_xp_bar.max_value = xp_to_next_level
	# A level-up resets the bar to zero; sliding backwards there looks broken,
	# so snap on level change and tween within a level.
	if level != _last_level:
		_xp_bar.value = current_xp
		if _level_label != null:
			UIAnim.punch(_level_label, 1.35)
	else:
		UIAnim.tween_bar(_xp_bar, float(current_xp), 0.18)

	_last_level = level
	if _level_label != null:
		_level_label.text = "LV %d" % level

func _on_currency_changed(current_currency: int) -> void:
	if _currency_label == null:
		return

	UIAnim.roll_number(_currency_label, float(_last_currency), float(current_currency), "%d", 0.3)
	if current_currency > _last_currency:
		UIAnim.punch(_currency_label, 1.2)

	_last_currency = current_currency

func _on_wave_start(wave_number: int) -> void:
	if _wave_label != null:
		_wave_label.text = "WAVE %d" % wave_number

	_show_banner("WAVE %d" % wave_number, _wave_flavour(wave_number))

static func _wave_flavour(wave_number: int) -> String:
	if wave_number <= 1:
		return "THE HUNT BEGINS"
	if wave_number % 5 == 0:
		return "SOMETHING OLD STIRS"

	return "THEY COME AGAIN"

# Centre-screen announcement: fades up, holds, fades out. Never blocks input.
func _show_banner(title: String, subtitle: String) -> void:
	if _banner == null:
		return

	if _banner_label != null:
		_banner_label.text = title

	if _banner_sub_label != null:
		_banner_sub_label.text = subtitle

	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(0.9, 0.9)
	_banner.modulate.a = 0.0

	var tween = _banner.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tween.tween_property(_banner, "scale", Vector2.ONE, 0.4)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.chain().tween_interval(1.1)
	tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.4)
