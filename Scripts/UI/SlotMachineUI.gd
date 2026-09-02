extends CanvasLayer
class_name SlotMachineUI

# The Jester's one-armed bandit, bottom-right of the screen for the whole run.
#
# Built entirely in code and spawned by BloodBoonSlotsPassive rather than authored as a
# .tscn, because it only exists for one Hunter — a scene instanced into Arena.tscn would
# have to hide itself for the other ten.
#
# The wheel is decided the instant SPIN is paid for (see BloodBoonSlotsPassive.request_spin);
# everything here is the theatre around that decision. The reels rattle through random faces
# for BloodBoonSlotsPassive.REEL_SECONDS, land on the face that was already rolled, and only
# then does the passive apply the effect.

# How fast the reels flick through faces while spinning.
const REEL_TICK_SECONDS = 0.07
# Reels stop left to right, so the third one landing is the beat the outcome reads on.
const REEL_STOP_STAGGER = 0.14
# How often the idle poll re-checks whether a spin is currently allowed.
const IDLE_REFRESH_SECONDS = 0.25
# Input action bound to Q in project.godot, and the letter printed on the button.
# Spinning by key is the point: reaching for the mouse mid-wave costs a Hunter
# more than the spin does.
const SPIN_ACTION = &"spin_wheel"
const SPIN_KEY_HINT = "Q"

var _passive: BloodBoonSlotsPassive

var _coins_label: Label
var _cost_label: Label
var _result_label: Label
var _spin_button: Button
var _reel_icons: Array[TextureRect] = []
var _reel_glyphs: Array[Label] = []
var _panel: PanelContainer

var _spinning: bool = false
var _spin_elapsed: float = 0.0
var _tick_accumulator: float = 0.0
var _target_face: int = -1
var _idle_refresh_cooldown: float = 0.0

func _ready() -> void:
	layer = 6
	# Keeps ticking while the tree is paused so the SPIN button can grey itself out
	# during the shop/boon screens instead of freezing mid-state.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_passive = BloodBoonSlotsPassive.instance
	_build()

	if _passive != null:
		_passive.coins_changed.connect(_on_coins_changed)
		_passive.spin_resolved.connect(_on_spin_resolved)

	if EventBus != null:
		# The spin price climbs every couple of waves; the button has to say so.
		EventBus.wave_start.connect(func(_wave: int): _refresh())

	_refresh()

# ---------------------------------------------------------------------------- layout

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"BloodPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -212.0
	_panel.offset_top = -186.0
	_panel.offset_right = -16.0
	_panel.offset_bottom = -16.0
	root.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)

	var title := Label.new()
	title.text = "BLEEDING WHEEL"
	title.theme_type_variation = &"StatLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_coins_label = Label.new()
	_coins_label.theme_type_variation = &"GoldLabel"
	_coins_label.tooltip_text = "Blood Boons"
	header.add_child(_coins_label)

	var reels := HBoxContainer.new()
	reels.add_theme_constant_override("separation", 4)
	reels.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(reels)

	for i in range(3):
		reels.add_child(_build_reel())

	_result_label = Label.new()
	_result_label.theme_type_variation = &"SmallLabel"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.custom_minimum_size = Vector2(0, 28)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.text = "Pull for blood."
	column.add_child(_result_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	column.add_child(footer)

	_spin_button = Button.new()
	_spin_button.text = "SPIN  [%s]" % SPIN_KEY_HINT
	_spin_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Never focusable: Q already spins, and a focusable button in the corner would
	# eat the boon screen's keyboard navigation the moment it opened.
	_spin_button.focus_mode = Control.FOCUS_NONE
	_spin_button.pressed.connect(_on_spin_pressed)
	UIAnim.juice_button(_spin_button)
	footer.add_child(_spin_button)

	_cost_label = Label.new()
	_cost_label.theme_type_variation = &"GoldLabel"
	_cost_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_cost_label)

func _build_reel() -> Control:
	var reel := PanelContainer.new()
	reel.theme_type_variation = &"InsetPanel"
	reel.custom_minimum_size = Vector2(52, 56)

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	reel.add_child(stack)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(0, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stack.add_child(icon)
	_reel_icons.append(icon)

	var glyph := Label.new()
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.theme_type_variation = &"StatLabel"
	stack.add_child(glyph)
	_reel_glyphs.append(glyph)

	_show_face_on_reel(_reel_icons.size() - 1, BloodBoonEconomy.Face.SEVEN)
	return reel

# ----------------------------------------------------------------------------- spin

# Q spins without touching the mouse and without the button ever taking focus —
# unhandled means a menu, a text field or anything else that wants the key gets it
# first. can_spin() already refuses while the tree is paused, so the shop and the
# boon screen are safe.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(SPIN_ACTION) or event.is_echo():
		return

	_on_spin_pressed()
	get_viewport().set_input_as_handled()

func _on_spin_pressed() -> void:
	if _passive == null or _spinning:
		return

	var face := _passive.request_spin()
	if face < 0:
		UIAnim.shake(_panel)
		return

	AudioManager.play_sfx("ui_click")
	_target_face = face
	_spinning = true
	_spin_elapsed = 0.0
	_tick_accumulator = 0.0
	_result_label.text = "..."
	_refresh()

func _process(delta: float) -> void:
	if not _spinning:
		# The button also has to grey out whenever the run pauses (shop, boon screen,
		# pause menu), and no signal fires for that — a quarter-second poll is cheaper
		# than teaching every pause site about the wheel.
		_idle_refresh_cooldown -= delta
		if _idle_refresh_cooldown <= 0.0:
			_idle_refresh_cooldown = IDLE_REFRESH_SECONDS
			_refresh()
		return

	_spin_elapsed += delta
	_tick_accumulator += delta

	# Each reel keeps rattling until its own stagger point, then locks onto the face
	# that was already rolled.
	if _tick_accumulator >= REEL_TICK_SECONDS:
		_tick_accumulator = 0.0
		var faces := BloodBoonEconomy.all_faces()
		for i in range(_reel_icons.size()):
			if _spin_elapsed >= _reel_stop_time(i):
				_show_face_on_reel(i, _target_face)
			else:
				_show_face_on_reel(i, faces[randi() % faces.size()])

	if _spin_elapsed < _reel_stop_time(_reel_icons.size() - 1):
		return

	_spinning = false
	for i in range(_reel_icons.size()):
		_show_face_on_reel(i, _target_face)
	UIAnim.punch(_panel, 1.1)
	_passive.resolve_spin(_target_face)

func _reel_stop_time(reel_index: int) -> float:
	return BloodBoonSlotsPassive.REEL_SECONDS + REEL_STOP_STAGGER * float(reel_index)

func _show_face_on_reel(index: int, face: int) -> void:
	if index < 0 or index >= _reel_icons.size():
		return

	var icon_path := BloodBoonEconomy.face_icon_path(face)
	if ResourceLoader.exists(icon_path):
		_reel_icons[index].texture = load(icon_path)
	_reel_icons[index].modulate = BloodBoonEconomy.face_color(face)
	_reel_glyphs[index].text = BloodBoonEconomy.face_glyph(face)
	_reel_glyphs[index].modulate = BloodBoonEconomy.face_color(face)

# -------------------------------------------------------------------------- refresh

func _on_coins_changed(_coins: int) -> void:
	_refresh()

func _on_spin_resolved(face: int, result_text: String) -> void:
	_result_label.text = "%s — %s" % [BloodBoonEconomy.face_name(face), result_text]
	_result_label.modulate = BloodBoonEconomy.face_color(face)

	if face == BloodBoonEconomy.Face.SEVEN:
		AudioManager.play_sfx("ui_levelup")
		UIAnim.flash(_panel, Color(1.8, 1.5, 0.9))
	elif face == BloodBoonEconomy.Face.SIX:
		AudioManager.play_sfx("ui_click")
		UIAnim.shake(_panel, 12.0)
	else:
		AudioManager.play_sfx("ui_confirm")

	_refresh()

func _refresh() -> void:
	if _passive == null:
		return

	var cost := _passive.spin_cost()
	_coins_label.text = "%d" % _passive.coins
	_cost_label.text = "%d" % cost
	_cost_label.tooltip_text = "Blood Boons per spin (rises every %d waves)" % BloodBoonEconomy.WAVES_PER_PRICE_STEP
	_spin_button.disabled = _spinning or not _passive.can_spin()
	_spin_button.tooltip_text = "Spend %d Blood Boons for a spin  (%s)" % [cost, SPIN_KEY_HINT]
