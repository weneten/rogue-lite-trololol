extends Control
class_name CharacterSelect

# Character-select: scans CharacterDataFolder, greys out locked hunters, unlock-purchase via
# meta-currency (MetaSave). Confirm stashes pick on GameManager and loads Arena.

@export var character_data_folder: String = "res://Resources/CharacterData/Data"
@export var arena_scene_path: String = "res://Scenes/Arena/Arena.tscn"

# Optional inspector override. If empty, uses BuiltInCharacterPaths then folder scan.
# DirAccess alone is unreliable (empty list in some editor/play configs).
@export var character_roster: Array[CharacterData]

@export_group("Wiring")
@export var roster_container_path: NodePath
@export var name_label_path: NodePath
@export var lore_label_path: NodePath
@export var stats_label_path: NodePath
@export var passive_label_path: NodePath
@export var difficulty_label_path: NodePath
@export var begin_button_path: NodePath
@export var back_button_path: NodePath
@export var meta_currency_label_path: NodePath
@export var unlock_button_path: NodePath
@export var unlock_status_label_path: NodePath

@export_group("Portrait")
# Box the selected Hunter's sprite is drawn in (also used to centre it on resize).
@export var portrait_panel_path: NodePath
@export var portrait_sprite_path: NodePath
# Shown instead of the sprite for Hunters whose CharacterData has no sheet yet.
@export var portrait_placeholder_path: NodePath
# Sprites are 64px; 3x keeps them chunky-but-crisp with Nearest filtering.
@export var portrait_zoom: float = 3.0

# Hardcoded paths so roster never depends solely on DirAccess listing.
const BUILT_IN_CHARACTER_PATHS: Array[String] = [
	"res://Resources/CharacterData/Data/WitchHunter.tres",
	"res://Resources/CharacterData/Data/TheReaper.tres",
	"res://Resources/CharacterData/Data/SilverPriest.tres",
	"res://Resources/CharacterData/Data/Bloodletter.tres",
	"res://Resources/CharacterData/Data/BloodstainedCrusader.tres",
	"res://Resources/CharacterData/Data/Pyromancer.tres",
	"res://Resources/CharacterData/Data/GraveWarden.tres",
	"res://Resources/CharacterData/Data/MoonlitDuelist.tres",
	"res://Resources/CharacterData/Data/Alchemist.tres",
	"res://Resources/CharacterData/Data/CursedNoble.tres",
]

var _roster_container: VBoxContainer
var _name_label: Label
var _lore_label: Label
var _stats_label: Label
var _passive_label: Label
var _difficulty_label: Label
var _begin_button: Button
var _back_button: Button
var _meta_currency_label: Label
var _unlock_button: Button
var _unlock_status_label: Label
var _empty_roster_label: Label
var _portrait_panel: Control
var _portrait_sprite: AnimatedSprite2D
var _portrait_placeholder: Label
var _portrait_procedural: TextureRect

var _roster: Array[CharacterData] = []
var _roster_buttons: Dictionary = {}
var _selected: CharacterData
var _roster_button_group: ButtonGroup

func _ready() -> void:
	MetaSave.ensure_loaded()

	_roster_container = get_node_or_null(roster_container_path)
	_name_label = get_node_or_null(name_label_path)
	_lore_label = get_node_or_null(lore_label_path)
	_stats_label = get_node_or_null(stats_label_path)
	_passive_label = get_node_or_null(passive_label_path)
	_difficulty_label = get_node_or_null(difficulty_label_path)
	_begin_button = get_node_or_null(begin_button_path)
	_back_button = get_node_or_null(back_button_path)
	_meta_currency_label = get_node_or_null(meta_currency_label_path)
	_unlock_button = get_node_or_null(unlock_button_path)
	_unlock_status_label = get_node_or_null(unlock_status_label_path)
	_portrait_panel = get_node_or_null(portrait_panel_path)
	_portrait_sprite = get_node_or_null(portrait_sprite_path)
	_portrait_placeholder = get_node_or_null(portrait_placeholder_path)

	if _portrait_sprite != null:
		# Pixel art must never be filtered — linear turns 64px sprites to mush.
		_portrait_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_portrait_sprite.centered = true
		_portrait_sprite.scale = Vector2.ONE * (portrait_zoom if portrait_zoom > 0.0 else 1.0)

	if _portrait_panel != null:
		_portrait_panel.resized.connect(_center_portrait)
		_center_portrait()

	# Code-built labels if scene wiring omitted (placeholder-friendly).
	_ensure_meta_ui()

	if _begin_button != null:
		_begin_button.disabled = true
		_begin_button.pressed.connect(_on_begin_pressed)

	if _back_button != null:
		_back_button.pressed.connect(_on_back_pressed)

	if _unlock_button != null:
		_unlock_button.pressed.connect(_on_unlock_pressed)

	_refresh_meta_label()
	_load_roster()
	_build_roster_buttons()

func _ensure_meta_ui() -> void:
	# Prefer scene-wired nodes; otherwise attach a small bar under Title area.
	if _meta_currency_label == null:
		_meta_currency_label = Label.new()
		_meta_currency_label.name = "MetaCurrencyLabel"
		_meta_currency_label.text = "Blood Marks: 0"
		_meta_currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_meta_currency_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.25))
		_meta_currency_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_meta_currency_label.offset_top = 20
		_meta_currency_label.offset_right = -24
		_meta_currency_label.offset_bottom = 48
		add_child(_meta_currency_label)

	if _unlock_button == null or _unlock_status_label == null:
		var detail = get_node_or_null("Margin/HBox/Detail")
		if detail is VBoxContainer:
			var vbox = detail as VBoxContainer
			if _unlock_status_label == null:
				_unlock_status_label = Label.new()
				_unlock_status_label.name = "UnlockStatusLabel"
				_unlock_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_unlock_status_label.add_theme_color_override("font_color", Color(0.7, 0.55, 0.55))
				# Insert above spacer if present.
				var spacer_idx = -1
				for i in range(vbox.get_child_count()):
					if vbox.get_child(i).name == "Spacer":
						spacer_idx = i
						break

				if spacer_idx >= 0:
					vbox.add_child(_unlock_status_label)
					vbox.move_child(_unlock_status_label, spacer_idx)
				else:
					vbox.add_child(_unlock_status_label)

			if _unlock_button == null:
				_unlock_button = Button.new()
				_unlock_button.name = "UnlockButton"
				_unlock_button.text = "Unlock"
				_unlock_button.visible = false
				var button_row = vbox.get_node_or_null("ButtonRow")
				if button_row != null:
					button_row.add_child(_unlock_button)
					button_row.move_child(_unlock_button, 0)
				else:
					vbox.add_child(_unlock_button)

func _load_roster() -> void:
	_roster.clear()
	var seen: Dictionary = {}

	# 1) Inspector-assigned roster (if any).
	if character_roster != null and character_roster.size() > 0:
		for data in character_roster:
			_try_add_roster_entry(data, seen)

	# 2) Built-in explicit paths (always try — DirAccess alone often returns empty).
	for path in BUILT_IN_CHARACTER_PATHS:
		_try_load_path(path, seen)

	# 3) Folder scan as bonus for any future hunters dropped into Data/.
	_scan_character_folder(seen)

	_roster.sort_custom(func(a, b):
		if a.difficulty_rating != b.difficulty_rating:
			return a.difficulty_rating < b.difficulty_rating
		return a.character_name < b.character_name
	)

	print("[CharacterSelect] Loaded %d hunters." % _roster.size())
	if _roster.is_empty():
		push_error("[CharacterSelect] Roster empty — check CharacterData .tres + C# build.")

func _scan_character_folder(seen: Dictionary) -> void:
	var dir = DirAccess.open(character_data_folder)
	if dir == null:
		push_warning("[CharacterSelect] DirAccess failed for '%s'." % character_data_folder)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir():
			file_name = dir.get_next()
			continue

		# Editor: .tres · exported: .tres.remap
		var bare = file_name
		if bare.ends_with(".remap"):
			bare = bare.substr(0, bare.length() - 6)

		if not bare.to_lower().ends_with(".tres"):
			file_name = dir.get_next()
			continue

		_try_load_path("%s/%s" % [character_data_folder, bare], seen)
		file_name = dir.get_next()

	dir.list_dir_end()

func _try_load_path(path: String, seen: Dictionary) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("[CharacterSelect] Missing resource: %s" % path)
		return

	# IgnoreCache so a prior failed parse of broken .tres does not stick for the session.
	var raw = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if raw is CharacterData:
		_try_add_roster_entry(raw as CharacterData, seen)
		return

	var type_str = "null" if raw == null else raw.get_class()
	push_warning("[CharacterSelect] Not CharacterData (got %s): %s" % [type_str, path])

func _try_add_roster_entry(data: CharacterData, seen: Dictionary) -> void:
	if data == null or data.character_name.is_empty():
		return

	if data.character_name in seen:
		return

	seen[data.character_name] = true
	_roster.append(data)

func _build_roster_buttons() -> void:
	if _roster_container == null:
		push_error("[CharacterSelect] RosterContainerPath not wired — cannot show hunters.")
		return

	for child in _roster_container.get_children():
		child.queue_free()

	_roster_buttons.clear()
	_roster_button_group = ButtonGroup.new()
	_empty_roster_label = null

	if _roster.is_empty():
		_empty_roster_label = Label.new()
		_empty_roster_label.text = "No hunters found.\nRebuild C# project, then reopen this scene."
		_empty_roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_empty_roster_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.35))
		_roster_container.add_child(_empty_roster_label)
		return

	var first_unlocked: CharacterData = null

	for data in _roster:
		var unlocked = MetaSave.is_character_unlocked(data.character_name)
		var cost = MetaSave.get_character_unlock_cost(data.difficulty_rating)

		var button = Button.new()
		button.text = "%s   %s" % [data.character_name.to_upper(), _difficulty_pips(data.difficulty_rating)] if unlocked \
			else "LOCKED   %s   %d BM" % [data.character_name.to_upper(), cost]
		button.toggle_mode = true
		button.button_group = _roster_button_group
		button.theme_type_variation = &"FlatButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.modulate = Color.WHITE if unlocked else Color(0.5, 0.48, 0.55, 1.0)
		# Ensure buttons are tall enough inside ScrollContainer.
		button.custom_minimum_size = Vector2(0, 40)
		UIAnim.juice_button(button, 1.03)

		var captured = data
		button.pressed.connect(func():
			AudioManager.play_sfx("ui_click")
			_select_character(captured)
		)
		_roster_container.add_child(button)
		_roster_buttons[data.character_name] = button

		if unlocked and first_unlocked == null:
			first_unlocked = data

	# The roster assembles top to bottom instead of appearing all at once.
	UIAnim.cascade(_roster_container, 0.035)

	var initial = first_unlocked if first_unlocked != null else _roster[0]
	_select_character(initial)
	if initial.character_name in _roster_buttons:
		var btn = _roster_buttons[initial.character_name] as Button
		btn.button_pressed = true

# Difficulty as filled/empty pips reads faster than "Diff 3/5".
static func _difficulty_pips(rating: int) -> String:
	var filled = clampi(rating, 0, 5)
	return "*".repeat(filled) + "-".repeat(5 - filled)

func _select_character(data: CharacterData) -> void:
	var changed = _selected != data
	_selected = data
	if changed and _portrait_panel != null:
		# A small kick on the portrait confirms the click landed.
		UIAnim.punch(_portrait_panel, 1.04)
	var unlocked = MetaSave.is_character_unlocked(data.character_name)
	var cost = MetaSave.get_character_unlock_cost(data.difficulty_rating)

	if _name_label != null:
		_name_label.text = "%s (LOCKED)" % data.character_name if not unlocked else data.character_name

	if _lore_label != null:
		_lore_label.text = data.lore_blurb if unlocked else "Locked. Spend Blood Marks to unlock this Hunter."

	if _difficulty_label != null:
		_difficulty_label.text = "Difficulty: %d/5" % data.difficulty_rating

	if _stats_label != null:
		_stats_label.text = (
			"HP %d   Speed %.0f   Armor %d\n" % [data.max_health, data.move_speed, data.starting_armor] +
			"Dodge %.0f%%   Crit %.0f%%   Magic x%.1f" % [data.starting_dodge_chance * 100.0, data.starting_crit_chance * 100.0, data.starting_magic_power]
		) if unlocked else "Stats hidden until unlocked."

	if _passive_label != null:
		if unlocked:
			var passive_name = data.passive_name if not data.passive_name.is_empty() else "—"
			_passive_label.text = "%s\n%s" % [passive_name, data.passive_description]
		else:
			_passive_label.text = "Passive hidden."

	_update_portrait(data, unlocked)

	if _begin_button != null:
		_begin_button.disabled = not unlocked

	if _unlock_button != null:
		_unlock_button.visible = not unlocked
		_unlock_button.disabled = unlocked or MetaSave.get_meta_currency() < cost
		_unlock_button.text = "Unlocked" if unlocked else "Unlock (%d Blood Marks)" % cost

	if _unlock_status_label != null:
		if unlocked:
			_unlock_status_label.text = "Ready to hunt."
		elif MetaSave.get_meta_currency() < cost:
			_unlock_status_label.text = "Need %d Blood Marks (have %d)." % [cost, MetaSave.get_meta_currency()]
		else:
			_unlock_status_label.text = "Unlock for %d Blood Marks." % cost

# Shows the selected Hunter's in-game sprite (same sheet Player.cs loads) looping its idle
# animation, so the roster preview matches what you actually control. Locked Hunters are
# drawn as a dark silhouette; Hunters without a sheet fall back to the placeholder label.
func _update_portrait(data: CharacterData, unlocked: bool) -> void:
	if _portrait_sprite == null:
		return

	var frames = _load_portrait_frames(data)
	var has_art = frames != null and frames.get_animation_names().size() > 0

	if has_art:
		_portrait_sprite.sprite_frames = frames
		_portrait_sprite.offset = SpriteSheetCache.get_sprite_offset(data.sprite_sheet_path)
		_portrait_sprite.scale = Vector2.ONE * (portrait_zoom if portrait_zoom > 0.0 else 1.0)
		# Silhouette while locked — same "???" treatment the roster button gets.
		_portrait_sprite.modulate = Color.WHITE if unlocked else Color(0.12, 0.1, 0.13, 1.0)
		var idle_name = "idle" if frames.has_animation("idle") else frames.get_animation_names()[0]
		_portrait_sprite.play(idle_name)
		_center_portrait()

	_portrait_sprite.visible = has_art

	if not has_art:
		_show_procedural_portrait(data, unlocked)
	elif _portrait_procedural != null:
		_portrait_procedural.visible = false

	if _portrait_placeholder != null:
		_portrait_placeholder.visible = false

func _show_procedural_portrait(data: CharacterData, unlocked: bool) -> void:
	if _portrait_procedural == null:
		if _portrait_panel == null:
			return
		_portrait_procedural = TextureRect.new()
		_portrait_procedural.name = "ProceduralPortrait"
		_portrait_procedural.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		_portrait_procedural.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_portrait_procedural.set_anchors_preset(Control.PRESET_FULL_RECT)
		_portrait_procedural.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_portrait_panel.add_child(_portrait_procedural)

	var palette = ProceduralSprite.palette_for_name(data.character_name)
	_portrait_procedural.texture = ProceduralSprite.build(ProceduralSprite.Archetype.HUNTER, palette[0], palette[1], hash(data.character_name))
	_portrait_procedural.modulate = Color.WHITE if unlocked else Color(0.12, 0.1, 0.13, 1.0)
	_portrait_procedural.visible = true

static func _load_portrait_frames(data: CharacterData) -> SpriteFrames:
	var sheet_path = data.sprite_sheet_path
	if sheet_path.is_empty() and data.sprite_sheet != null:
		sheet_path = data.sprite_sheet.resource_path

	if data.sprite_sheet == null and sheet_path.is_empty():
		return null

	return SpriteSheetCache.get_frames(sheet_path, data.sprite_json_path, data.sprite_sheet)

# Feet-on-origin sheets: park the pivot slightly below centre so the body reads centred.
func _center_portrait() -> void:
	if _portrait_sprite == null or _portrait_panel == null:
		return

	var size = _portrait_panel.size
	_portrait_sprite.position = Vector2(size.x * 0.5, size.y * 0.62)

func _on_unlock_pressed() -> void:
	if _selected == null:
		return

	if MetaSave.is_character_unlocked(_selected.character_name):
		return

	var cost = MetaSave.get_character_unlock_cost(_selected.difficulty_rating)
	if not MetaSave.try_unlock_character(_selected.character_name, cost):
		if _unlock_status_label != null:
			_unlock_status_label.text = "Not enough Blood Marks."

		return

	_refresh_meta_label()
	_refresh_roster_button(_selected)
	_select_character(_selected)

func _refresh_roster_button(data: CharacterData) -> void:
	if not (data.character_name in _roster_buttons):
		return

	var button = _roster_buttons[data.character_name] as Button
	var unlocked = MetaSave.is_character_unlocked(data.character_name)
	button.text = "%s  (Diff %d/5)" % [data.character_name, data.difficulty_rating] if unlocked \
		else "???  %s  [%d BM]" % [data.character_name, MetaSave.get_character_unlock_cost(data.difficulty_rating)]
	button.modulate = Color.WHITE if unlocked else Color(0.45, 0.45, 0.5, 1.0)

func _refresh_meta_label() -> void:
	if _meta_currency_label != null:
		_meta_currency_label.text = "Blood Marks: %d" % MetaSave.get_meta_currency()

func _on_begin_pressed() -> void:
	if _selected == null or not MetaSave.is_character_unlocked(_selected.character_name):
		return

	GameManager.selected_character = _selected
	GameManager.start_new_run()
	get_tree().change_scene_to_file(arena_scene_path)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/MainMenu/MainMenu.tscn")
