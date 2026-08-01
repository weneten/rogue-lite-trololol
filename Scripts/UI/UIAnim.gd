extends Object
class_name UIAnim

# Shared motion vocabulary for every menu and HUD element.
#
# The rules are deliberately narrow so the whole game moves the same way:
# panels rise and fade in, cards pop with a small overshoot, values roll
# instead of snapping, and anything that hurts shakes. Timings are short —
# menus in an action roguelite should never make you wait.

const FAST := 0.12
const NORMAL := 0.22
const SLOW := 0.38

const OVERSHOOT := 1.06


static func _kill(node: Node, key: String) -> void:
	# One tween per purpose per node, so a re-trigger restarts cleanly instead
	# of fighting the previous one.
	var meta_key = "_tw_" + key
	if node.has_meta(meta_key):
		var old = node.get_meta(meta_key)
		if old is Tween and old.is_valid():
			old.kill()


static func _track(node: Node, key: String, tween: Tween) -> Tween:
	node.set_meta("_tw_" + key, tween)
	return tween


# ---------------------------------------------------------------------------
# Entrances / exits
# ---------------------------------------------------------------------------

# Fade up while settling into place. The default for panels and list rows.
#
# Deliberately does NOT animate `position`: inside a Container the layout pass
# owns that property, and tweening it makes freshly-built lists pile up at the
# top-left. Scale and modulate survive a re-sort, so the entrance uses those.
static func rise_in(control: Control, delay: float = 0.0, distance: float = 14.0) -> Tween:
	if control == null or not control.is_inside_tree():
		return null

	_kill(control, "enter")
	control.pivot_offset = Vector2(control.size.x * 0.5, control.size.y)
	control.scale = Vector2(1.0, 0.86)
	control.modulate.a = 0.0
	control.visible = true

	var tween = control.create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(control, "modulate:a", 1.0, NORMAL).set_delay(delay)
	tween.tween_property(control, "scale", Vector2.ONE, SLOW).set_delay(delay)
	return _track(control, "enter", tween)


# Scale pop with a slight overshoot — for cards, rewards, level-up choices.
static func pop_in(control: Control, delay: float = 0.0) -> Tween:
	if control == null or not control.is_inside_tree():
		return null

	_kill(control, "enter")
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(0.82, 0.82)
	control.modulate.a = 0.0
	control.visible = true

	var tween = control.create_tween().set_parallel(true)
	tween.tween_property(control, "modulate:a", 1.0, FAST).set_delay(delay)
	tween.tween_property(control, "scale", Vector2.ONE * OVERSHOOT, NORMAL)\
		.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.chain().tween_property(control, "scale", Vector2.ONE, FAST)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	return _track(control, "enter", tween)


# Slide in from a screen edge: -1 left, 1 right, used by the shop and pause.
static func slide_in(control: Control, from_x: float, duration: float = SLOW) -> Tween:
	if control == null or not control.is_inside_tree():
		return null

	_kill(control, "enter")
	var target = control.position
	control.position = Vector2(target.x + from_x, target.y)
	control.modulate.a = 0.0
	control.visible = true

	var tween = control.create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	tween.tween_property(control, "position", target, duration)
	tween.tween_property(control, "modulate:a", 1.0, duration * 0.6)
	return _track(control, "enter", tween)


static func fade_out(control: Control, duration: float = NORMAL, hide_after: bool = true) -> Tween:
	if control == null or not control.is_inside_tree():
		return null

	_kill(control, "enter")
	var tween = control.create_tween()
	tween.tween_property(control, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	if hide_after:
		tween.tween_callback(func(): control.visible = false)
	return _track(control, "enter", tween)


# Stagger a container's children so lists assemble instead of appearing.
static func cascade(container: Node, step: float = 0.045, use_pop: bool = false) -> void:
	if container == null:
		return

	var index = 0
	for child in container.get_children():
		if child is Control and child.visible:
			if use_pop:
				pop_in(child, index * step)
			else:
				rise_in(child, index * step, 10.0)
			index += 1


# ---------------------------------------------------------------------------
# Feedback
# ---------------------------------------------------------------------------

# Attach hover/press motion to a button. Safe to call once per button.
static func juice_button(button: BaseButton, lift: float = 1.08) -> void:
	if button == null or button.has_meta("_juiced"):
		return

	button.set_meta("_juiced", true)
	button.pivot_offset = button.size * 0.5
	button.resized.connect(func(): button.pivot_offset = button.size * 0.5)

	button.mouse_entered.connect(func(): _scale_to(button, Vector2.ONE * lift, FAST))
	button.mouse_exited.connect(func(): _scale_to(button, Vector2.ONE, FAST))
	button.focus_entered.connect(func(): _scale_to(button, Vector2.ONE * lift, FAST))
	button.focus_exited.connect(func(): _scale_to(button, Vector2.ONE, FAST))
	button.button_down.connect(func(): _scale_to(button, Vector2.ONE * 0.94, 0.06))
	button.button_up.connect(func(): _scale_to(button, Vector2.ONE * lift, 0.08))


static func _scale_to(control: Control, target: Vector2, duration: float) -> void:
	if control == null or not control.is_inside_tree():
		return

	_kill(control, "scale")
	var tween = control.create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(control, "scale", target, duration)
	_track(control, "scale", tween)


# Quick punch outward and back — good for "you gained something".
static func punch(control: Control, amount: float = 1.18) -> void:
	if control == null or not control.is_inside_tree():
		return

	_kill(control, "punch")
	control.pivot_offset = control.size * 0.5
	var tween = control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * amount, 0.07)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "scale", Vector2.ONE, 0.16)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_track(control, "punch", tween)


# Horizontal shake for damage and refusals.
static func shake(control: Control, strength: float = 8.0, duration: float = 0.28) -> void:
	if control == null or not control.is_inside_tree():
		return

	_kill(control, "shake")
	var origin = control.position
	var tween = control.create_tween()
	var steps = 6
	for i in range(steps):
		var falloff = 1.0 - float(i) / steps
		var dir = -1.0 if i % 2 == 0 else 1.0
		tween.tween_property(control, "position",
			origin + Vector2(strength * falloff * dir, 0.0), duration / steps)
	tween.tween_property(control, "position", origin, duration / steps)
	_track(control, "shake", tween)


# Flash a control's modulate toward a colour and back.
static func flash(control: CanvasItem, color: Color = Color(1.6, 1.2, 1.2), duration: float = 0.18) -> void:
	if control == null or not control.is_inside_tree():
		return

	_kill(control, "flash")
	var tween = control.create_tween()
	tween.tween_property(control, "modulate", color, duration * 0.3)
	tween.tween_property(control, "modulate", Color.WHITE, duration * 0.7)
	_track(control, "flash", tween)


# Slow breathing glow for idle emphasis (boss banners, unlock prompts).
static func pulse(control: CanvasItem, low: float = 0.65, high: float = 1.0, period: float = 1.4) -> Tween:
	if control == null or not control.is_inside_tree():
		return null

	_kill(control, "pulse")
	var tween = control.create_tween().set_loops()
	tween.tween_property(control, "modulate:a", high, period * 0.5)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, "modulate:a", low, period * 0.5)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	return _track(control, "pulse", tween)


static func stop_pulse(control: CanvasItem) -> void:
	if control != null:
		_kill(control, "pulse")


# ---------------------------------------------------------------------------
# Values
# ---------------------------------------------------------------------------

# Ease a bar toward its new value instead of snapping. Damage reads as a
# drain; healing reads as a refill.
static func tween_bar(bar: Range, value: float, duration: float = NORMAL) -> void:
	if bar == null or not bar.is_inside_tree():
		return

	_kill(bar, "value")
	var tween = bar.create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(bar, "value", value, duration)
	_track(bar, "value", tween)


# Count a label up or down. `format` receives the rounded integer.
static func roll_number(label: Label, from_value: float, to_value: float,
		format: String = "%d", duration: float = 0.35) -> void:
	if label == null or not label.is_inside_tree():
		return

	_kill(label, "roll")
	var tween = label.create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(
		func(v: float): label.text = format % int(round(v)),
		from_value, to_value, duration)
	_track(label, "roll", tween)


# ---------------------------------------------------------------------------
# Screen transitions
# ---------------------------------------------------------------------------

# Full-screen wipe used between menu and arena. Returns the overlay so the
# caller can await its tween before switching scenes.
static func screen_fade(layer: CanvasLayer, to_black: bool, duration: float = 0.3) -> ColorRect:
	if layer == null:
		return null

	var overlay = layer.get_node_or_null("_FadeOverlay") as ColorRect
	if overlay == null:
		overlay = ColorRect.new()
		overlay.name = "_FadeOverlay"
		overlay.color = Color(0.02, 0.01, 0.03, 1.0)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(overlay)

	overlay.z_index = 100
	overlay.modulate.a = 0.0 if to_black else 1.0
	overlay.visible = true

	var tween = overlay.create_tween()
	tween.tween_property(overlay, "modulate:a", 1.0 if to_black else 0.0, duration)
	if not to_black:
		tween.tween_callback(func(): overlay.visible = false)
	return overlay
