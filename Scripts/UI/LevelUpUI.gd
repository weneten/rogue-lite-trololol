extends CanvasLayer
class_name LevelUpUI

# Level-up choice screen: on EventBus.OnPlayerLevelUp it rolls a few random, non-repeating
# upgrades from UpgradePool, shows RootPanel (ProcessMode.Always so its buttons still respond
# while PlayerStats has paused the tree), and applies whichever one is picked to PlayerStats.

@export var upgrade_pool: UpgradePoolData
@export var choice_count: int = 3

@export_group("Wiring")
@export var root_panel_path: NodePath
@export var choice_button_paths: Array[NodePath] = []
@export var choice_name_paths: Array[NodePath] = []
@export var choice_description_paths: Array[NodePath] = []
@export var choices_container_path: NodePath
@export var header_path: NodePath

var _root_panel: Control
var _choice_buttons: Array[Button] = []
var _choice_names: Array[Label] = []
var _choice_descriptions: Array[Label] = []
var _current_choices: Array[UpgradeData] = []
var _choices_container: Control
var _header: Control
# Only ever built for a Jester run; null for every other Hunter.
var _blood_boon_button: Button
var is_replica: bool = false

func _ready() -> void:
	# Lets the buttons still receive input/process while GetTree().Paused is true for the
	# level-up screen itself; everything else in the run stays frozen (default Pausable).
	process_mode = PROCESS_MODE_ALWAYS

	if upgrade_pool == null:
		upgrade_pool = load("res://Resources/UpgradeData/Data/StandardUpgradePool.tres")
	_root_panel = get_node_or_null(root_panel_path)
	_choices_container = get_node_or_null(choices_container_path)
	_header = get_node_or_null(header_path)

	for i in range(choice_button_paths.size()):
		_choice_buttons.append(get_node_or_null(choice_button_paths[i]))
		if i < choice_name_paths.size():
			_choice_names.append(get_node_or_null(choice_name_paths[i]))
		else:
			_choice_names.append(null)
		if i < choice_description_paths.size():
			_choice_descriptions.append(get_node_or_null(choice_description_paths[i]))
		else:
			_choice_descriptions.append(null)

		var choice_index = i  # capture by value for the closure below
		if _choice_buttons[i] != null:
			_choice_buttons[i].pressed.connect(func(): _on_choice_selected(choice_index))
			UIAnim.juice_button(_choice_buttons[i])

	if _root_panel != null:
		_root_panel.visible = false

	if is_replica:
		for button in _choice_buttons:
			if button != null:
				button.disabled = true
		return

	EventBus.player_level_up.connect(_on_player_level_up)

func _on_player_level_up(new_level: int) -> void:
	AudioManager.play_sfx("ui_levelup")
	_roll_choices()
	_refresh_blood_boon_option()

	if _root_panel != null:
		_root_panel.visible = true
		_root_panel.modulate.a = 0.0
		var tween = _root_panel.create_tween()
		tween.tween_property(_root_panel, "modulate:a", 1.0, 0.18)

	# Cards deal in one at a time — the pause before the third is what makes
	# the choice feel like a choice.
	if _header != null:
		UIAnim.rise_in(_header, 0.05, 12.0)

	if _choices_container != null:
		UIAnim.cascade(_choices_container, 0.09, true)

	_focus_first_choice()
	if NetSession != null:
		NetSession.broadcast_intermission("boon", {"boons": _boon_snapshot()})

# ------------------------------------------------------------- blood boon cash-in

# The Jester can refuse the boon entirely and take Blood Boons for it instead — the same
# XP-for-spins trade the Ossuary exchange offers, taken at the moment the level is handed
# out. Built lazily and only when a Jester is in the run; no other Hunter ever sees it.
func _refresh_blood_boon_option() -> void:
	var passive := BloodBoonSlotsPassive.instance
	if passive == null or is_replica:
		return

	var payout := BloodBoonEconomy.get_level_trade_payout(passive.current_wave())

	if _blood_boon_button == null or not is_instance_valid(_blood_boon_button):
		if _choices_container == null:
			return

		var column: VBoxContainer = _choices_container.get_parent() as VBoxContainer
		if column == null:
			return

		_blood_boon_button = Button.new()
		_blood_boon_button.name = "BloodBoonTrade"
		_blood_boon_button.pressed.connect(_on_blood_boon_trade_pressed)
		UIAnim.juice_button(_blood_boon_button)
		column.add_child(_blood_boon_button)

	_blood_boon_button.text = "REFUSE THE BOON — TAKE %d BLOOD BOONS" % payout
	_blood_boon_button.tooltip_text = "Skip this upgrade and feed the Bleeding Wheel instead."
	_blood_boon_button.visible = true

func _on_blood_boon_trade_pressed() -> void:
	var passive := BloodBoonSlotsPassive.instance
	if passive == null:
		return

	passive.add_coins(BloodBoonEconomy.get_level_trade_payout(passive.current_wave()))
	AudioManager.play_sfx("ui_purchase")

	# Same close path a normal pick takes: hide once the queue is empty, then hand the
	# intermission on so the shop still opens.
	var more_boons := PlayerStats.instance != null and PlayerStats.instance.pending_boons > 0
	if not more_boons:
		if _root_panel != null:
			_root_panel.visible = false
		UIAnim.release_focus(get_tree())

	if PlayerStats.instance != null:
		PlayerStats.instance.confirm_upgrade_selected()

func _focus_first_choice() -> void:
	for button in _choice_buttons:
		if button != null and button.visible and not button.disabled:
			UIAnim.grab_focus_safe(button)
			return

# Weighted, non-repeating draw of ChoiceCount upgrades from the pool, then pushes the result into the choice cards.
func _roll_choices() -> void:
	_current_choices.clear()

	var remaining: Array[UpgradeData] = []
	if upgrade_pool != null and upgrade_pool.upgrades != null:
		remaining = upgrade_pool.upgrades.duplicate()
	var draw_count = mini(choice_count, remaining.size())

	for i in range(draw_count):
		var picked = _weighted_pick(remaining)
		_current_choices.append(picked)
		remaining.erase(picked)

	for i in range(_choice_buttons.size()):
		if _choice_buttons[i] == null:
			continue

		var has_choice = i < _current_choices.size()
		_choice_buttons[i].visible = has_choice
		_choice_buttons[i].disabled = not has_choice

		if has_choice:
			var upgrade = _current_choices[i]
			if _choice_names[i] != null:
				_choice_names[i].text = upgrade.display_name
			if _choice_descriptions[i] != null:
				_choice_descriptions[i].text = upgrade.description

# Weighted random pick over UpgradeData.Weight, mirroring WaveManager's enemy-pool roll.
static func _weighted_pick(pool: Array[UpgradeData]) -> UpgradeData:
	var total_weight = 0.0
	for upgrade in pool:
		total_weight += maxf(0.0, upgrade.weight)

	if total_weight <= 0.0:
		return pool[0]

	var roll = randf() * total_weight
	for upgrade in pool:
		roll -= maxf(0.0, upgrade.weight)
		if roll <= 0.0:
			return upgrade

	return pool[pool.size() - 1]

func apply_pane_layout(pane: Vector2) -> void:
	if _choices_container == null:
		return
	var solo := pane.x >= 1180.0 and pane.y >= 680.0
	var n: int = maxi(1, _choices_container.get_child_count())
	var card := Vector2(250, 220)
	if not solo and pane.x >= 8.0:
		card = Vector2(
			clampf((pane.x - 48.0) / float(n) - 18.0, 160.0, 280.0),
			clampf(pane.y - 110.0, 150.0, 240.0)
		)
	for child in _choices_container.get_children():
		if child is Control:
			(child as Control).custom_minimum_size = card


func apply_net_state(st: Dictionary) -> void:
	var phase := str(st.get("phase", ""))
	if _root_panel != null:
		_root_panel.visible = phase == "boon"
	var rows: Variant = st.get("boons", [])
	if typeof(rows) != TYPE_ARRAY:
		rows = []
	for i in range(_choice_buttons.size()):
		var has: bool = i < rows.size() and typeof(rows[i]) == TYPE_DICTIONARY
		if _choice_buttons[i] != null:
			_choice_buttons[i].visible = has
			_choice_buttons[i].disabled = true
		if has:
			if _choice_names[i] != null:
				_choice_names[i].text = str(rows[i].get("n", ""))
			if _choice_descriptions[i] != null:
				_choice_descriptions[i].text = str(rows[i].get("d", ""))

func _boon_snapshot() -> Array:
	var rows: Array = []
	for upgrade in _current_choices:
		if upgrade != null:
			rows.append({"n": upgrade.display_name, "d": upgrade.description})
	return rows

func _on_choice_selected(index: int) -> void:
	if index >= _current_choices.size():
		return

	_apply_upgrade(_current_choices[index])
	AudioManager.play_sfx("ui_confirm")

	if index < _choice_buttons.size() and _choice_buttons[index] != null:
		UIAnim.punch(_choice_buttons[index], 1.2)

	var more_boons := PlayerStats.instance != null and PlayerStats.instance.pending_boons > 0
	if not more_boons:
		if _root_panel != null:
			_root_panel.visible = false
		UIAnim.release_focus(get_tree())

	if PlayerStats.instance != null:
		PlayerStats.instance.confirm_upgrade_selected()

static func _apply_upgrade(upgrade: UpgradeData) -> void:
	var stats = PlayerStats.instance if PlayerStats != null else null
	if stats == null:
		return

	match upgrade.upgrade_type:
		UpgradeData.UpgradeType.DAMAGE_BOOST:
			stats.apply_damage_upgrade(upgrade.value)
		UpgradeData.UpgradeType.MOVE_SPEED_BOOST:
			stats.apply_move_speed_upgrade(upgrade.value)
		UpgradeData.UpgradeType.MAX_HEALTH_BOOST:
			stats.apply_max_health_upgrade(roundi(upgrade.value))
		UpgradeData.UpgradeType.PASSIVE:
			# Stage stub: no relic/passive-item system exists yet, just acknowledge the pick.
			print("[LevelUpUI] Passive relic '%s' selected (placeholder, no effect yet)." % upgrade.id)
