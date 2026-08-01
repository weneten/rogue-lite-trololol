extends CanvasLayer
class_name PauseMenu

# In-run pause overlay: Resume / Settings / Quit to Main Menu. ESC (ui_cancel) toggles.
# ProcessMode Always so it still runs while the tree is paused.

@export var root_panel_path: NodePath
@export var resume_button_path: NodePath
@export var settings_button_path: NodePath
@export var quit_button_path: NodePath
@export var settings_menu_path: NodePath
@export var main_menu_scene_path: String = "res://Scenes/MainMenu/MainMenu.tscn"
@export var card_path: NodePath

var _card: Control
var _root_panel: Control
var _resume_button: Button
var _settings_button: Button
var _quit_button: Button
var _settings_menu: SettingsMenu
var _open: bool

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80

	_root_panel = get_node_or_null(root_panel_path)
	_card = get_node_or_null(card_path)
	_resume_button = get_node_or_null(resume_button_path)
	_settings_button = get_node_or_null(settings_button_path)
	_quit_button = get_node_or_null(quit_button_path)
	_settings_menu = get_node_or_null(settings_menu_path)

	if _resume_button != null:
		_resume_button.pressed.connect(close)

	if _settings_button != null:
		_settings_button.pressed.connect(_on_settings_pressed)

	if _quit_button != null:
		_quit_button.pressed.connect(_on_quit_pressed)

	for button in [_resume_button, _settings_button, _quit_button]:
		if button != null:
			UIAnim.juice_button(button)

	if _root_panel != null:
		_root_panel.visible = false

	_open = false

func _unhandled_input(event: InputEvent) -> void:
	# Don't steal ESC while death screen owns the run end.
	if DeathScreen.is_showing:
		return

	if event.is_action_pressed("ui_cancel"):
		if _settings_menu != null and _settings_menu.is_open:
			_settings_menu.close()
			get_viewport().set_input_as_handled()
			return

		if _open:
			close()
		else:
			open()

		get_viewport().set_input_as_handled()

func open() -> void:
	if _open:
		return

	_open = true
	if _root_panel != null:
		_root_panel.visible = true
		_root_panel.modulate.a = 0.0
		var tween = _root_panel.create_tween()
		tween.tween_property(_root_panel, "modulate:a", 1.0, 0.14)

	UIAnim.pop_in(_card)
	if _resume_button != null:
		_resume_button.grab_focus()

	get_tree().paused = true

func close() -> void:
	if not _open:
		return

	_open = false
	if _root_panel != null:
		_root_panel.visible = false

	if _settings_menu != null:
		_settings_menu.close()
	get_tree().paused = false

func _on_settings_pressed() -> void:
	if _settings_menu != null:
		_settings_menu.open()

func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(main_menu_scene_path)
