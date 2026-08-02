extends Control
class_name MainMenu

# Main menu: Start -> CharacterSelect, Settings overlay, Quit. Shows Blood Marks balance.
#
# The scene is assembled statically; this script only wires signals, rolls the
# Blood Marks counter, and runs the entrance/exit choreography.

@export var start_button_path: NodePath
@export var quit_button_path: NodePath
@export var settings_button_path: NodePath
@export var meta_currency_label_path: NodePath
@export var settings_menu_path: NodePath

@export_group("Presentation")
@export var title_path: NodePath
@export var subtitle_path: NodePath
@export var button_box_path: NodePath
@export var moon_path: NodePath

# "Begin the Hunt" leads to Hunter selection; Arena loads from CharacterSelect.
@export var character_select_scene_path: String = "res://Scenes/UI/CharacterSelect.tscn"

var _start_button: Button
var _quit_button: Button
var _settings_button: Button
var _meta_currency_label: Label
var _settings_menu: SettingsMenu
var _title: Label
var _subtitle: Label
var _button_box: Control
var _moon: Control
var _fade_layer: CanvasLayer
var _leaving: bool = false
var _elapsed: float = 0.0

func _ready() -> void:
	MetaSave.ensure_loaded()

	_start_button = get_node_or_null(start_button_path)
	_quit_button = get_node_or_null(quit_button_path)
	_settings_button = get_node_or_null(settings_button_path)
	_meta_currency_label = get_node_or_null(meta_currency_label_path)
	_settings_menu = get_node_or_null(settings_menu_path)
	_title = get_node_or_null(title_path)
	_subtitle = get_node_or_null(subtitle_path)
	_button_box = get_node_or_null(button_box_path)
	_moon = get_node_or_null(moon_path)

	# Build missing Settings button / meta label if scene not yet extended.
	_ensure_chrome()

	if _start_button != null:
		_start_button.pressed.connect(_on_start_pressed)

	if _quit_button != null:
		_quit_button.pressed.connect(_on_quit_pressed)

	if _settings_button != null:
		_settings_button.pressed.connect(_on_settings_pressed)

	_refresh_meta_label()
	_play_intro()

func _process(delta: float) -> void:
	_elapsed += delta

	# The moon drifts and breathes; nothing else on the menu moves once the
	# intro settles, so this is what keeps the screen from feeling like a still.
	if _moon != null:
		_moon.position.y = sin(_elapsed * 0.5) * 5.0
		_moon.modulate.a = 0.24 + 0.08 * sin(_elapsed * 0.8)

	if _title != null and not _leaving:
		_title.position.y = sin(_elapsed * 1.1) * 2.0

func _play_intro() -> void:
	if _title != null:
		UIAnim.pop_in(_title, 0.05)

	if _subtitle != null:
		UIAnim.rise_in(_subtitle, 0.22, 10.0)

	if _button_box != null:
		# Buttons assemble one after another rather than all at once.
		UIAnim.cascade(_button_box, 0.07)
		for child in _button_box.get_children():
			if child is BaseButton:
				UIAnim.juice_button(child)

	UIAnim.grab_focus_safe(_start_button)

	var fade = _get_fade_layer()
	UIAnim.screen_fade(fade, false, 0.45)

func _get_fade_layer() -> CanvasLayer:
	if _fade_layer == null or not is_instance_valid(_fade_layer):
		_fade_layer = CanvasLayer.new()
		_fade_layer.layer = 120
		add_child(_fade_layer)

	return _fade_layer

func _ensure_chrome() -> void:
	var vbox = get_node_or_null("Layout/Rows/Center/Menu/Buttons")

	if _meta_currency_label == null:
		_meta_currency_label = Label.new()
		_meta_currency_label.name = "MetaCurrencyLabel"
		_meta_currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_meta_currency_label.text = "Blood Marks: 0"
		_meta_currency_label.theme_type_variation = &"GoldLabel"
		add_child(_meta_currency_label)

	if _settings_button == null and vbox != null:
		_settings_button = Button.new()
		_settings_button.name = "SettingsButton"
		_settings_button.text = "SETTINGS"
		vbox.add_child(_settings_button)
		# Place before Quit if possible.
		var quit = vbox.get_node_or_null("QuitButton")
		if quit != null:
			vbox.move_child(_settings_button, quit.get_index())

	if _settings_menu == null:
		# Instance SettingsMenu scene if present; else build a minimal in-code shell.
		var packed = load("res://Scenes/UI/SettingsMenu.tscn")
		if packed != null:
			_settings_menu = packed.instantiate()
			add_child(_settings_menu)

func _refresh_meta_label() -> void:
	if _meta_currency_label == null:
		return

	var marks = MetaSave.get_meta_currency()
	# Roll the balance up so returning from a run visibly pays out.
	UIAnim.roll_number(_meta_currency_label, 0.0, float(marks), "Blood Marks: %d", 0.7)

func _on_start_pressed() -> void:
	if _leaving:
		return

	_leaving = true
	AudioManager.play_sfx("ui_confirm")
	UIAnim.screen_fade(_get_fade_layer(), true, 0.3)
	await get_tree().create_timer(0.32).timeout
	get_tree().change_scene_to_file(character_select_scene_path)

func _on_settings_pressed() -> void:
	if _settings_menu != null:
		_settings_menu.open()

func _unhandled_input(event: InputEvent) -> void:
	# ESC closes settings and returns focus to the menu buttons.
	if _settings_menu != null and _settings_menu.is_open and event.is_action_pressed("ui_cancel"):
		_settings_menu.close()
		UIAnim.grab_focus_safe(_start_button)
		get_viewport().set_input_as_handled()

func _on_quit_pressed() -> void:
	get_tree().quit()
