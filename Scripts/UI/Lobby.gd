extends Control
class_name Lobby

# Host shows a 4-letter code; joiners type it. Host starts the hunt for everyone.

@export var arena_scene_path: String = "res://Scenes/Arena/Arena.tscn"

var _status: Label
var _code_label: Label
var _code_entry: LineEdit
var _start_button: Button
var _join_button: Button
var _back_button: Button
var _roster: Label
var _mode_host: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_mode_host = NetSession.lobby_intent != "join"
	NetSession.roster_changed.connect(_on_roster)
	NetSession.lobby_ready.connect(_on_ready_code)
	NetSession.match_starting.connect(_on_start)
	NetSession.lobby_failed.connect(_on_fail)
	_assemble.call_deferred()

func _assemble() -> void:
	_build()
	if GameManager.selected_character == null:
		_on_back()
		return

	var hunter := GameManager.selected_character.character_name
	if _mode_host:
		_status.text = "Opening a lobby…"
		NetSession.host_lobby(hunter)
	else:
		_status.text = "Enter the host's code."

func setup_host() -> void:
	_mode_host = true

func setup_join() -> void:
	_mode_host = false

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.06, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -220
	col.offset_right = 220
	col.offset_top = -180
	col.offset_bottom = 180
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var title := Label.new()
	title.text = "COVEN LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_font_size_override("font_size", 36)
	col.add_child(_code_label)

	_code_entry = LineEdit.new()
	_code_entry.placeholder_text = "CODE"
	_code_entry.max_length = 5
	_code_entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_entry.visible = not _mode_host
	col.add_child(_code_entry)

	_join_button = Button.new()
	_join_button.text = "JOIN"
	_join_button.visible = not _mode_host
	_join_button.pressed.connect(_on_join_pressed)
	col.add_child(_join_button)

	_start_button = Button.new()
	_start_button.text = "BEGIN THE HUNT"
	_start_button.visible = _mode_host
	_start_button.disabled = true
	_start_button.pressed.connect(_on_start_pressed)
	col.add_child(_start_button)

	_roster = Label.new()
	_roster.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_roster)

	_back_button = Button.new()
	_back_button.text = "BACK"
	_back_button.pressed.connect(_on_back)
	col.add_child(_back_button)

func _on_ready_code(lobby_code: String) -> void:
	_code_label.text = lobby_code
	_status.text = "Share this code. Start when the coven is gathered." if _mode_host else "Waiting for the host…"
	if _mode_host:
		_start_button.disabled = false

func _on_roster(players: Array) -> void:
	var lines: PackedStringArray = PackedStringArray()
	for p in players:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var tag := "HOST" if bool(p.get("host", false)) else "HUNTER"
		lines.append("%s  %s  (%s)" % [tag, str(p.get("char", "?")), str(p.get("pid", "?"))])
	_roster.text = "\n".join(lines)

func _on_join_pressed() -> void:
	if GameManager.selected_character == null:
		return
	_status.text = "Joining…"
	NetSession.join_lobby(_code_entry.text, GameManager.selected_character.character_name)

func _on_start_pressed() -> void:
	NetSession.start_match()

func _on_start(_seed: int) -> void:
	GameManager.start_new_run(_seed)
	get_tree().change_scene_to_file(arena_scene_path)

func _on_fail(message: String) -> void:
	_status.text = message

func _on_back() -> void:
	NetSession.reset()
	get_tree().change_scene_to_file("res://Scenes/UI/CharacterSelect.tscn")
