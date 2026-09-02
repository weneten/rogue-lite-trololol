extends CanvasLayer
class_name SlotMachineUI

# The Jester's one-armed bandit, bottom-right of the screen for the whole run.
#
# Built entirely in code and spawned by BloodBoonSlotsPassive rather than authored as a
# .tscn, because it only exists for one Hunter — a scene instanced into Arena.tscn would
# have to hide itself for the other ten.
#
# The chrome is the slot_cabinet / slot_lever / slot_blood art from tools/pixelforge/slots.py,
# laid out by hand against that file's source geometry (mirrored in the constants below) at
# DISPLAY_SCALE. Containers are deliberately not used here: a slot machine has a shape, and
# the reels have to land inside the windows painted on the cabinet, not wherever a VBox
# decides to put them.
#
# The wheel is decided the instant the lever is paid for (see BloodBoonSlotsPassive.request_spin);
# everything here is theatre around that decision. The arm drops, the reels rattle through
# random faces for BloodBoonSlotsPassive.REEL_SECONDS, land on the face that was already
# rolled, and only then does the passive apply the effect.

# ------------------------------------------------------------------ art geometry
# Source-pixel geometry of Assets/UI/slot_cabinet.png and slot_lever.png. These mirror
# tools/pixelforge/slots.py — change one and change the other, or the reels drift out of
# their windows.
const DISPLAY_SCALE = 2

const CAB_W = 100
const CAB_H = 88
const WINDOW_X: Array[int] = [8, 38, 68]
const WINDOW_Y = 24
const WINDOW_W = 22
const WINDOW_H = 28
const MOUNT = Vector2(95, 34)

const LEVER_W = 52
const LEVER_H = 64
const LEVER_PIVOT = Vector2(8, 56)
const LEVER_FRAMES = 5

const BLOOD_CELL = 12
const BLOOD_DROPLET_FRAMES: Array[int] = [0, 1]
const BLOOD_SPLAT_FRAME = 3

# ------------------------------------------------------------------------ timing
# How fast the reels flick through faces while spinning.
const REEL_TICK_SECONDS = 0.07
# Reels stop left to right, so the third one landing is the beat the outcome reads on.
const REEL_STOP_STAGGER = 0.14
# The arm's drop, and the slower climb back once the outcome has landed.
const LEVER_PULL_SECONDS = 0.16
const LEVER_RETURN_SECONDS = 0.45
# How often the idle poll re-checks whether a spin is currently allowed.
const IDLE_REFRESH_SECONDS = 0.25
# Input action bound to Q in project.godot, and the letter printed on the cabinet.
# Spinning by key is the point: reaching for the mouse mid-wave costs a Hunter
# more than the spin does.
const SPIN_ACTION = &"spin_wheel"
const SPIN_KEY_HINT = "Q"

# A pull throws a few beads, not a fountain. Six is enough to read as a splash at
# this size and few enough that it never covers the reels.
const BLOOD_DROPLETS = 6
const BLOOD_FLIGHT_SECONDS = 0.5
const BLOOD_SPLAT_SECONDS = 1.6

var _passive: BloodBoonSlotsPassive

var _root: Control
var _machine: Control
var _cabinet: TextureRect
var _lever: TextureRect
var _lever_atlas: AtlasTexture
var _blood_texture: Texture2D
var _coins_label: Label
var _cost_label: Label
var _hint_label: Label
var _result_label: Label
var _reel_icons: Array[TextureRect] = []
var _reel_glyphs: Array[Label] = []

var _spinning: bool = false
var _spin_elapsed: float = 0.0
var _tick_accumulator: float = 0.0
var _target_face: int = -1
var _idle_refresh_cooldown: float = 0.0
var _can_spin_cached: bool = false

func _ready() -> void:
	layer = 6
	# Keeps ticking while the tree is paused so the lever can grey itself out during
	# the shop/boon screens instead of freezing mid-state.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_passive = BloodBoonSlotsPassive.instance
	_build()

	if _passive != null:
		_passive.coins_changed.connect(_on_coins_changed)
		_passive.spin_resolved.connect(_on_spin_resolved)

	if EventBus != null:
		# The spin price climbs every couple of waves; the cabinet has to say so.
		EventBus.wave_start.connect(func(_wave: int): _refresh())

	_refresh()

# ---------------------------------------------------------------------------- layout

func _px(value: float) -> float:
	return value * DISPLAY_SCALE

func _build() -> void:
	_blood_texture = _load_texture("res://Assets/UI/slot_blood.png")

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# The machine plus the arm swung out to its right, and the result line under both.
	var lever_left := _px(MOUNT.x - LEVER_PIVOT.x)
	var total_w := lever_left + _px(LEVER_W)
	var total_h := _px(CAB_H) + 34.0

	_machine = Control.new()
	_machine.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_machine.offset_left = -total_w - 16.0
	_machine.offset_top = -total_h - 16.0
	_machine.offset_right = -16.0
	_machine.offset_bottom = -16.0
	_machine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_machine)

	_cabinet = TextureRect.new()
	_cabinet.texture = _load_texture("res://Assets/UI/slot_cabinet.png")
	_cabinet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cabinet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cabinet.stretch_mode = TextureRect.STRETCH_SCALE
	_cabinet.position = Vector2.ZERO
	_cabinet.size = Vector2(_px(CAB_W), _px(CAB_H))
	# The whole cabinet is a click target, not just the arm: aiming at a 20-pixel
	# lever mid-fight is a worse ask than the spin itself.
	_cabinet.mouse_filter = Control.MOUSE_FILTER_STOP
	_cabinet.gui_input.connect(_on_machine_clicked)
	_machine.add_child(_cabinet)

	for i in range(3):
		_build_reel(i)

	_coins_label = _add_label(Vector2(_px(8), _px(59)), _px(44), &"GoldLabel", HORIZONTAL_ALIGNMENT_LEFT)
	_coins_label.tooltip_text = "Blood Boons"
	_cost_label = _add_label(Vector2(_px(CAB_W - 46), _px(59)), _px(38), &"GoldLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_hint_label = _add_label(Vector2(_px(14), _px(72)), _px(CAB_W - 28), &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_hint_label.text = "PULL  [%s]" % SPIN_KEY_HINT

	_build_lever(lever_left)

	_result_label = Label.new()
	_result_label.theme_type_variation = &"SmallLabel"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.position = Vector2(0, _px(CAB_H) + 2)
	_result_label.size = Vector2(total_w, 32)
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_label.text = "Pull for blood."
	_machine.add_child(_result_label)

func _add_label(pos: Vector2, width: float, variation: StringName, align: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = align
	label.position = pos
	label.size = Vector2(width, _px(10))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_machine.add_child(label)
	return label

# One reel: the face's icon inside the cabinet's painted window, its ASCII glyph under it.
# The Nightbane font is a bitmap sheet, so the glyph has to stay plain ASCII.
func _build_reel(index: int) -> void:
	var wx := float(WINDOW_X[index])

	var icon := TextureRect.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(_px(wx), _px(WINDOW_Y + 2))
	icon.size = Vector2(_px(WINDOW_W), _px(15))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_machine.add_child(icon)
	_reel_icons.append(icon)

	var glyph := Label.new()
	glyph.theme_type_variation = &"StatLabel"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.position = Vector2(_px(wx), _px(WINDOW_Y + 17))
	glyph.size = Vector2(_px(WINDOW_W), _px(10))
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_machine.add_child(glyph)
	_reel_glyphs.append(glyph)

	_show_face_on_reel(index, BloodBoonEconomy.Face.SEVEN)

# The arm rides on an AtlasTexture whose region picks the frame, so the five baked
# angles cost one texture and no runtime rotation (which fringes pixel art at every
# angle that is not a right angle).
func _build_lever(lever_left: float) -> void:
	_lever_atlas = AtlasTexture.new()
	_lever_atlas.atlas = _load_texture("res://Assets/UI/slot_lever.png")
	_lever_atlas.region = Rect2(0, 0, LEVER_W, LEVER_H)

	_lever = TextureRect.new()
	_lever.texture = _lever_atlas
	_lever.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_lever.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lever.stretch_mode = TextureRect.STRETCH_SCALE
	_lever.position = Vector2(lever_left, _px(MOUNT.y - LEVER_PIVOT.y))
	_lever.size = Vector2(_px(LEVER_W), _px(LEVER_H))
	_lever.mouse_filter = Control.MOUSE_FILTER_STOP
	_lever.gui_input.connect(_on_machine_clicked)
	_machine.add_child(_lever)

func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("[SlotMachineUI] Missing art '%s' — run tools/build_art.py slots." % path)
		return null
	return load(path) as Texture2D

# ----------------------------------------------------------------------------- spin

# Q spins without touching the mouse and without anything here taking focus —
# unhandled means a menu, a text field or anything else that wants the key gets it
# first. can_spin() already refuses while the tree is paused, so the shop and the
# boon screen are safe.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(SPIN_ACTION) or event.is_echo():
		return

	_pull()
	get_viewport().set_input_as_handled()

func _on_machine_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_pull()

func _pull() -> void:
	if _passive == null or _spinning:
		return

	var face := _passive.request_spin()
	if face < 0:
		# Refused: the arm jerks and stops. Nothing was paid.
		UIAnim.shake(_machine, 5.0)
		return

	AudioManager.play_sfx("ui_click")
	_target_face = face
	_spinning = true
	_spin_elapsed = 0.0
	_tick_accumulator = 0.0
	_result_label.text = "..."
	_result_label.modulate = Color.WHITE
	_animate_lever(true)
	_refresh()

# Drops the arm through its five frames, then lets it climb back once the outcome
# has landed. The blood is thrown at the bottom of the drop, where the arm stops.
func _animate_lever(pulling: bool) -> void:
	if _lever == null:
		return

	var from_frame := 0.0 if pulling else float(LEVER_FRAMES - 1)
	var to_frame := float(LEVER_FRAMES - 1) if pulling else 0.0
	var duration := LEVER_PULL_SECONDS if pulling else LEVER_RETURN_SECONDS

	var tween := _lever.create_tween()
	tween.tween_method(_set_lever_frame, from_frame, to_frame, duration)
	if pulling:
		tween.tween_callback(_splash_blood)

func _set_lever_frame(value: float) -> void:
	var index: int = clampi(int(round(value)), 0, LEVER_FRAMES - 1)
	_lever_atlas.region = Rect2(index * LEVER_W, 0, LEVER_W, LEVER_H)

func _process(delta: float) -> void:
	if not _spinning:
		# The lever also has to grey out whenever the run pauses (shop, boon screen,
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
	UIAnim.punch(_machine, 1.06)
	_animate_lever(false)
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

# ---------------------------------------------------------------------------- blood

# Thrown off the knob when the arm bottoms out: a handful of beads on ballistic arcs
# and one splat left drying on the cabinet. Every piece frees itself.
func _splash_blood() -> void:
	if _blood_texture == null or _lever == null:
		return

	var origin := _lever.position + Vector2(_px(LEVER_W) * 0.72, _px(LEVER_H) * 0.62)

	for i in range(BLOOD_DROPLETS):
		var drop := _new_blood_piece(BLOOD_DROPLET_FRAMES[i % BLOOD_DROPLET_FRAMES.size()])
		drop.position = origin + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
		_machine.add_child(drop)

		# Outward and mostly downward, and never far: the splash must not reach the
		# reels or it stops being a flourish and starts being an obstruction.
		var travel := Vector2(randf_range(-38.0, 14.0), randf_range(-14.0, 30.0))
		var tween := drop.create_tween()
		tween.set_parallel(true)
		tween.tween_property(drop, "position", drop.position + travel, BLOOD_FLIGHT_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(drop, "modulate:a", 0.0, BLOOD_FLIGHT_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(drop.queue_free)

	var splat := _new_blood_piece(BLOOD_SPLAT_FRAME)
	splat.position = Vector2(_px(randf_range(58.0, 84.0)), _px(randf_range(56.0, 70.0)))
	_machine.add_child(splat)
	var splat_tween := splat.create_tween()
	splat_tween.tween_property(splat, "modulate:a", 0.0, BLOOD_SPLAT_SECONDS).set_delay(0.3)
	splat_tween.tween_callback(splat.queue_free)

func _new_blood_piece(frame: int) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = _blood_texture
	atlas.region = Rect2(frame * BLOOD_CELL, 0, BLOOD_CELL, BLOOD_CELL)

	var piece := TextureRect.new()
	piece.texture = atlas
	piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	piece.stretch_mode = TextureRect.STRETCH_SCALE
	piece.size = Vector2(_px(BLOOD_CELL), _px(BLOOD_CELL))
	piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return piece

# -------------------------------------------------------------------------- refresh

func _on_coins_changed(_coins: int) -> void:
	_refresh()

func _on_spin_resolved(face: int, result_text: String) -> void:
	_result_label.text = "%s — %s" % [BloodBoonEconomy.face_name(face), result_text]
	_result_label.modulate = BloodBoonEconomy.face_color(face)

	if face == BloodBoonEconomy.Face.SEVEN:
		AudioManager.play_sfx("ui_levelup")
		UIAnim.flash(_cabinet, Color(1.8, 1.5, 0.9))
	elif face == BloodBoonEconomy.Face.SIX:
		AudioManager.play_sfx("ui_click")
		UIAnim.shake(_machine, 12.0)
		# 666 bleeds the machine as well as its owner.
		_splash_blood()
	else:
		AudioManager.play_sfx("ui_confirm")

	_refresh()

func _refresh() -> void:
	if _passive == null:
		return

	var cost := _passive.spin_cost()
	_coins_label.text = "%d" % _passive.coins
	_cost_label.text = "-%d" % cost

	_can_spin_cached = _passive.can_spin()
	# Unaffordable or paused reads as a dead machine: the arm and the price go dim
	# together, so there is never a lit lever that does nothing.
	var live: bool = _can_spin_cached or _spinning
	_lever.modulate.a = 1.0 if live else 0.45
	_cost_label.modulate.a = 1.0 if live else 0.5
	_hint_label.modulate.a = 1.0 if live else 0.4

	var tooltip := "Pull the lever: %d Blood Boons  (%s)" % [cost, SPIN_KEY_HINT]
	_lever.tooltip_text = tooltip
	_cabinet.tooltip_text = tooltip
