extends CanvasLayer
class_name DeathScreen

# Run-end summary: player death OR wave-20 clear. Grants meta-currency via RunStats,
# shows waves/kills/damage/gold, Continue -> MainMenu.

# True while the overlay is up (PauseMenu ignores ESC while set).
static var is_showing: bool = false

@export var root_panel_path: NodePath
@export var title_label_path: NodePath
@export var stats_label_path: NodePath
@export var meta_label_path: NodePath
@export var continue_button_path: NodePath
@export var main_menu_scene_path: String = "res://Scenes/MainMenu/MainMenu.tscn"
@export var victory_wave: int = 20
@export var card_path: NodePath
@export var crest_path: NodePath

var _root_panel: Control
var _title_label: Label
var _stats_label: Label
var _meta_label: Label
var _continue_button: Button
var _card: Control
var _crest: Control
var _shown: bool = false

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 100

	_root_panel = get_node_or_null(root_panel_path)
	_title_label = get_node_or_null(title_label_path)
	_stats_label = get_node_or_null(stats_label_path)
	_meta_label = get_node_or_null(meta_label_path)
	_continue_button = get_node_or_null(continue_button_path)
	_card = get_node_or_null(card_path)
	_crest = get_node_or_null(crest_path)

	if _continue_button != null:
		_continue_button.pressed.connect(_on_continue_pressed)
		UIAnim.juice_button(_continue_button)

	if _root_panel != null:
		_root_panel.visible = false

	is_showing = false
	_shown = false

	if EventBus != null:
		EventBus.player_died.connect(_on_player_died)
		EventBus.wave_end.connect(_on_wave_end)

func _exit_tree() -> void:
	if EventBus != null:
		EventBus.player_died.disconnect(_on_player_died)
		EventBus.wave_end.disconnect(_on_wave_end)

	is_showing = false

func _on_player_died() -> void:
	if NetSession != null and NetSession.is_active:
		# Co-op: stay in the hunt until the host ends or you leave. Don't pause
		# the tree for everyone when one hunter falls.
		return
	_show_summary(false)

func _on_wave_end(wave_number: int) -> void:
	if wave_number >= victory_wave:
		_show_summary(true)

func _show_summary(run_complete: bool) -> void:
	if _shown:
		return

	_shown = true
	is_showing = true
	get_tree().paused = true

	var stats = RunStats.instance if RunStats != null else null
	var waves = (stats.waves_survived if stats != null else (GameManager.wave_number if GameManager != null else 0))
	var kills = (stats.kills if stats != null else 0)
	var damage = (stats.damage_dealt if stats != null else 0)
	var gold = (stats.gold_earned if stats != null else (GameManager.currency if GameManager != null else 0))

	var meta_granted = 0
	if stats != null:
		meta_granted = stats.finalize_and_grant_meta(run_complete)
	else:
		meta_granted = RunStats.preview_payout(waves, kills, gold, run_complete)

	if stats == null and meta_granted > 0:
		MetaSave.add_meta_currency(meta_granted)

	if _title_label != null:
		_title_label.text = "The Blood Moon Wanes" if run_complete else "You Have Fallen"

	if _stats_label != null:
		_stats_label.text = (
			"Waves Survived: %d\n" % waves +
			"Kills: %d\n" % kills +
			"Damage Dealt: %d\n" % damage +
			"Gold Earned: %d" % gold
		)

	if _meta_label != null:
		_meta_label.text = "+%d Blood Marks\nTotal: %d" % [meta_granted, MetaSave.get_meta_currency()]

	if _root_panel != null:
		_root_panel.visible = true
		# The overlay bleeds in slowly; the card and its numbers land after,
		# so the run summary reads as a verdict rather than a popup.
		_root_panel.modulate.a = 0.0
		var tween = _root_panel.create_tween()
		tween.tween_property(_root_panel, "modulate:a", 1.0, 0.5)

	UIAnim.pop_in(_card, 0.35)
	UIAnim.grab_focus_safe(_continue_button)

	if _crest != null:
		UIAnim.pulse(_crest, 0.55, 1.0, 2.6)

	if _meta_label != null and meta_granted > 0:
		UIAnim.roll_number(_meta_label, 0.0, float(meta_granted),
			"+%d Blood Marks", 0.9)
		await get_tree().create_timer(1.3).timeout
		if is_instance_valid(_meta_label):
			_meta_label.text = "+%d Blood Marks\nTotal: %d" % [meta_granted, MetaSave.get_meta_currency()]
			UIAnim.punch(_meta_label, 1.2)
		# Re-assert focus after the await in case something stole it.
		UIAnim.grab_focus_safe(_continue_button)

func _on_continue_pressed() -> void:
	is_showing = false
	get_tree().paused = false
	if NetSession != null:
		NetSession.reset()
	get_tree().change_scene_to_file(main_menu_scene_path)
