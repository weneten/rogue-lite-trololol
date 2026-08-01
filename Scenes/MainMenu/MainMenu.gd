extends Control
class_name MainMenu

# Main menu: Start -> CharacterSelect, Settings overlay, Quit. Shows Blood Marks balance.

@export var start_button_path: NodePath
@export var quit_button_path: NodePath
@export var settings_button_path: NodePath
@export var meta_currency_label_path: NodePath
@export var settings_menu_path: NodePath

# "Begin the Hunt" leads to Hunter selection; Arena loads from CharacterSelect.
@export var character_select_scene_path: String = "res://Scenes/UI/CharacterSelect.tscn"

var _start_button: Button
var _quit_button: Button
var _settings_button: Button
var _meta_currency_label: Label
var _settings_menu: SettingsMenu

func _ready() -> void:
	MetaSave.ensure_loaded()

	_start_button = get_node_or_null(start_button_path)
	_quit_button = get_node_or_null(quit_button_path)
	_settings_button = get_node_or_null(settings_button_path)
	_meta_currency_label = get_node_or_null(meta_currency_label_path)
	_settings_menu = get_node_or_null(settings_menu_path)

	# Build missing Settings button / meta label if scene not yet extended.
	_ensure_chrome()

	if _start_button != null:
		_start_button.pressed.connect(_on_start_pressed)

	if _quit_button != null:
		_quit_button.pressed.connect(_on_quit_pressed)

	if _settings_button != null:
		_settings_button.pressed.connect(_on_settings_pressed)

	_refresh_meta_label()

func _ensure_chrome() -> void:
	var vbox = get_node_or_null("CenterContainer/VBoxContainer")

	if _meta_currency_label == null:
		_meta_currency_label = Label.new()
		_meta_currency_label.name = "MetaCurrencyLabel"
		_meta_currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_meta_currency_label.text = "Blood Marks: 0"
		_meta_currency_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.25))
		if vbox != null:
			# Insert under subtitle if present.
			vbox.add_child(_meta_currency_label)
			var subtitle_idx = -1
			for i in range(vbox.get_child_count()):
				if vbox.get_child(i).name == "Subtitle":
					subtitle_idx = i
					break

			if subtitle_idx >= 0:
				vbox.move_child(_meta_currency_label, subtitle_idx + 1)
		else:
			add_child(_meta_currency_label)

	if _settings_button == null and vbox != null:
		_settings_button = Button.new()
		_settings_button.name = "SettingsButton"
		_settings_button.text = "Settings"
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
	if _meta_currency_label != null:
		_meta_currency_label.text = "Blood Marks: %d" % MetaSave.get_meta_currency()

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(character_select_scene_path)

func _on_settings_pressed() -> void:
	if _settings_menu != null:
		_settings_menu.open()

func _on_quit_pressed() -> void:
	get_tree().quit()
