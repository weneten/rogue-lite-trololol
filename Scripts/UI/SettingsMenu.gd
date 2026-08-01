extends CanvasLayer
class_name SettingsMenu

# Volume sliders + key-rebind stub. Talks to AudioManager only via public API
# (SetMasterVolume/SetMusicVolume/SetSfxVolume methods OR MasterVolume/MusicVolume/SfxVolume
# properties) with null-checks — Audio stage owns AudioManager internals.

@export var root_panel_path: NodePath
@export var master_slider_path: NodePath
@export var music_slider_path: NodePath
@export var sfx_slider_path: NodePath
@export var close_button_path: NodePath
@export var rebind_stub_button_path: NodePath
@export var rebind_status_label_path: NodePath
@export var card_path: NodePath

var _root_panel: Control
var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _close_button: Button
var _rebind_stub_button: Button
var _rebind_status_label: Label

var is_open: bool
var _card: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90

	_root_panel = get_node_or_null(root_panel_path)
	_master_slider = get_node_or_null(master_slider_path)
	_music_slider = get_node_or_null(music_slider_path)
	_sfx_slider = get_node_or_null(sfx_slider_path)
	_close_button = get_node_or_null(close_button_path)
	_rebind_stub_button = get_node_or_null(rebind_stub_button_path)
	_rebind_status_label = get_node_or_null(rebind_status_label_path)
	_card = get_node_or_null(card_path)

	_configure_slider(_master_slider, _get_audio_volume("Master"), _on_master_changed)
	_configure_slider(_music_slider, _get_audio_volume("Music"), _on_music_changed)
	_configure_slider(_sfx_slider, _get_audio_volume("Sfx"), _on_sfx_changed)

	if _close_button != null:
		_close_button.pressed.connect(close)

	if _rebind_stub_button != null:
		_rebind_stub_button.pressed.connect(_on_rebind_stub_pressed)

	for button in [_close_button, _rebind_stub_button]:
		if button != null:
			UIAnim.juice_button(button)

	if _root_panel != null:
		_root_panel.visible = false

	is_open = false

func open() -> void:
	if _root_panel != null:
		_root_panel.visible = true
		_root_panel.modulate.a = 0.0
		var tween = _root_panel.create_tween()
		tween.tween_property(_root_panel, "modulate:a", 1.0, 0.14)

	UIAnim.pop_in(_card)
	_sync_sliders_from_audio()
	is_open = true

	if _close_button != null:
		_close_button.grab_focus()

func close() -> void:
	if _root_panel != null:
		UIAnim.fade_out(_root_panel, 0.14)

	is_open = false

func _configure_slider(slider: HSlider, value: float, on_changed: Callable) -> void:
	if slider == null:
		return

	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.value_changed.connect(func(v): on_changed.call(float(v)))

func _sync_sliders_from_audio() -> void:
	if _master_slider != null:
		_master_slider.value = _get_audio_volume("Master")
	if _music_slider != null:
		_music_slider.value = _get_audio_volume("Music")
	if _sfx_slider != null:
		_sfx_slider.value = _get_audio_volume("Sfx")

func _on_master_changed(value: float) -> void:
	_set_audio_volume("Master", value)

func _on_music_changed(value: float) -> void:
	_set_audio_volume("Music", value)

func _on_sfx_changed(value: float) -> void:
	_set_audio_volume("Sfx", value)

func _on_rebind_stub_pressed() -> void:
	if _rebind_status_label != null:
		_rebind_status_label.text = "Key rebinding coming soon."

# Prefer SetXVolume(float) if present; else assign XVolume property. Silent no-op if neither.
static func _set_audio_volume(channel: String, value: float) -> void:
	var audio = AudioManager
	if audio == null:
		return

	value = clampf(value, 0.0, 1.0)
	var method = "Set%sVolume" % channel
	if audio.has_method(method):
		audio.call(method, value)
		return

	match channel:
		"Master":
			audio.master_volume = value
		"Music":
			audio.music_volume = value
		"Sfx":
			audio.sfx_volume = value

static func _get_audio_volume(channel: String) -> float:
	var audio = AudioManager
	if audio == null:
		return 1.0

	match channel:
		"Master":
			return audio.master_volume
		"Music":
			return audio.music_volume
		"Sfx":
			return audio.sfx_volume
		_:
			return 1.0
