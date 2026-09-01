extends CanvasLayer
class_name DebugMenu

# In-run admin panel: jump waves, resize the horde, pick a boss to fight, try
# any weapon, and edit the Hunter's stats live. F1 toggles it.
#
# The whole UI is built in code rather than authored as a .tscn. It is a
# workbench, not shipped screen art — it changes whenever a system gains a
# knob worth poking, and a scene file would mean editing two places every time.
#
# Everything it touches goes through public API (WaveManager.debug_*,
# BossManager.debug_*, PlayerStats, WeaponInventory). Nothing here reaches into
# another system's privates, so a refactor over there breaks this loudly at the
# call site instead of quietly doing the wrong thing.
#
# Off in release builds unless available_in_release is set: this is a cheat
# menu, and the project exports to the web.

@export var toggle_key: Key = KEY_F1
@export var available_in_release: bool = false

const THEME_PATH := "res://Assets/UI/nightbane_theme.tres"
const BOSS_DATA_DIR := "res://Resources/BossData/Data"
const WEAPON_DATA_DIR := "res://Resources/WeaponData/Data"
const SHOP_POOL_PATH := "res://Resources/ShopData/Data/StandardShopPool.tres"

const DIM := Color(0.62, 0.58, 0.68)
const GOOD := Color(0.55, 0.85, 0.6)
const WARN := Color(0.95, 0.62, 0.35)

var is_open: bool

var _root: Control
var _tabs: TabContainer
var _status: Label
var _headline: Label
var _pause_check: CheckBox
var _was_paused: bool

# One content box per tab, repopulated on every open so the panel always shows
# live values instead of whatever was true when the Arena loaded.
var _tab_bodies: Dictionary = {}

# Restores dodge_chance when god mode is switched back off.
var _god_mode: bool
var _saved_dodge: float

# PlayerStats as it looked the first time the panel was opened this run, so a
# session of poking at multipliers can be undone without restarting.
var _stat_snapshot: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 95

	if not _is_available():
		# Nothing built, nothing listening — a release build carries an inert node.
		set_process(false)
		set_process_input(false)
		return

	_build_shell()
	_root.visible = false
	set_process(false)

func _is_available() -> bool:
	return available_in_release or OS.is_debug_build()

func _input(event: InputEvent) -> void:
	if not _is_available():
		return

	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == toggle_key:
		toggle()
		get_viewport().set_input_as_handled()
		return

	# Handled here rather than in _unhandled_input so ESC closes this panel
	# instead of opening the pause menu underneath it.
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	if is_open or not _is_available():
		return

	is_open = true
	_root.visible = true
	_was_paused = get_tree().paused
	_capture_snapshot()
	_rebuild_all_tabs()
	_say("Admin panel open — F1 or ESC to close.", DIM)

	if _pause_check != null:
		_pause_check.button_pressed = true

	get_tree().paused = true
	set_process(true)
	UIAnim.pop_in(_root.get_node_or_null("Panel"))

func close() -> void:
	if not is_open:
		return

	is_open = false
	_root.visible = false
	set_process(false)
	# Never unpause a run that was already paused when the panel came up —
	# opening the admin panel from the pause menu must not resume the fight.
	get_tree().paused = _was_paused

func _process(_delta: float) -> void:
	_refresh_headline()

# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------
func _build_shell() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var theme_res := load(THEME_PATH) as Theme
	if theme_res != null:
		_root.theme = theme_res
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -430
	panel.offset_right = 430
	panel.offset_top = -290
	panel.offset_bottom = 290
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	column.add_child(_build_header())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)

	for tab_name in ["Waves", "Bosses", "Weapons", "Hunter"]:
		_tab_bodies[tab_name] = _add_tab(tab_name)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 22)
	column.add_child(_status)

func _build_header() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "ADMIN"
	bar.add_child(title)

	_headline = Label.new()
	_headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_headline.modulate = DIM
	bar.add_child(_headline)

	_pause_check = CheckBox.new()
	_pause_check.text = "Pause world"
	_pause_check.button_pressed = true
	_pause_check.toggled.connect(func(on: bool):
		get_tree().paused = on
		_say("World %s." % ("paused" if on else "running — the fight continues behind the panel")))
	bar.add_child(_pause_check)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	UIAnim.juice_button(close_button)
	bar.add_child(close_button)

	return bar

func _add_tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	return body

func _refresh_headline() -> void:
	if _headline == null:
		return

	var wave := WaveManager.current_wave if WaveManager != null else 0
	var alive := WaveManager.count_alive_enemies() if WaveManager != null else 0
	var cap := WaveManager.get_max_alive_for_wave(wave) if WaveManager != null else 0
	var coin := GameManager.currency if GameManager != null else 0
	var boss := BossManager.get_active_boss_name() if BossManager != null else ""

	var line := "wave %d · %d/%d alive · %d coin" % [wave, alive, cap, coin]
	if not boss.is_empty():
		line += " · fighting %s" % boss

	_headline.text = line

func _say(message: String, color: Color = Color.WHITE) -> void:
	if _status != null:
		_status.text = message
		_status.modulate = color

	print("[DebugMenu] %s" % message)

# ---------------------------------------------------------------------------
# Widget helpers
# ---------------------------------------------------------------------------
func _section(body: VBoxContainer, title: String) -> void:
	if body.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 6)
		body.add_child(spacer)

	var label := Label.new()
	label.text = title.to_upper()
	label.modulate = DIM
	body.add_child(label)
	body.add_child(HSeparator.new())

func _row(body: VBoxContainer, controls: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for control in controls:
		row.add_child(control)

	body.add_child(row)
	return row

func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	UIAnim.juice_button(button)
	return button

func _label(text: String, color: Color = Color.WHITE, expand: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = color
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	return label

func _spin(minimum: float, maximum: float, step: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(96, 0)
	return spin

# A labelled number bound to one field. Reads through `getter` so the row shows
# the live value, writes through `setter` on every edit.
func _number_row(body: VBoxContainer, caption: String, getter: Callable, setter: Callable,
		minimum: float, maximum: float, step: float) -> void:
	var spin := _spin(minimum, maximum, step, float(getter.call()))
	spin.value_changed.connect(func(value: float):
		setter.call(value)
		_say("%s = %.2f" % [caption, value]))
	_row(body, [_label(caption, Color.WHITE, true), spin])

# ---------------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------------
func _rebuild_all_tabs() -> void:
	var selected := _tabs.current_tab
	_build_waves_tab(_clear(_tab_bodies["Waves"]))
	_build_bosses_tab(_clear(_tab_bodies["Bosses"]))
	_build_weapons_tab(_clear(_tab_bodies["Weapons"]))
	_build_hunter_tab(_clear(_tab_bodies["Hunter"]))
	_tabs.current_tab = clampi(selected, 0, _tabs.get_tab_count() - 1)

func _clear(body: VBoxContainer) -> VBoxContainer:
	for child in body.get_children():
		child.queue_free()
		body.remove_child(child)

	return body

# -- Waves ------------------------------------------------------------------
func _build_waves_tab(body: VBoxContainer) -> void:
	if _warn_if_client(body):
		return

	_section(body, "Jump")
	var wave_spin := _spin(1, 999, 1, maxi(1, WaveManager.current_wave))
	_row(body, [
		_label("Go to wave", Color.WHITE, true),
		wave_spin,
		_button("Start it", func():
			WaveManager.debug_jump_to_wave(int(wave_spin.value))
			_say("Jumped to wave %d." % int(wave_spin.value), GOOD)),
	])
	_row(body, [
		_button("End wave now", func():
			WaveManager.end_wave()
			_say("Wave %d ended — intermission should follow." % WaveManager.current_wave)),
		_button("Start next wave", func():
			WaveManager.start_next_wave()
			_say("Wave %d started." % WaveManager.current_wave, GOOD)),
	])

	_section(body, "Horde")
	# enemy_density_multiplier is the one dial that scales both halves of the
	# pressure: the concurrent-alive cap and the spawn interval.
	var stats := PlayerStats.instance
	var density := _spin(0.5, 3.0, 0.1, stats.enemy_density_multiplier if stats != null else 1.0)
	var cap_label := _label("", DIM, true)
	var refresh_cap := func():
		cap_label.text = "max alive this wave: %d" % WaveManager.get_max_alive_for_wave(WaveManager.current_wave)
	density.value_changed.connect(func(value: float):
		if PlayerStats.instance != null:
			PlayerStats.instance.enemy_density_multiplier = value

		refresh_cap.call()
		_say("Horde density = %.1f×." % value))
	refresh_cap.call()
	_row(body, [_label("Density (0.5–3.0)", Color.WHITE, true), density])
	body.add_child(cap_label)

	var spawn_count := _spin(1, 100, 1, 10)
	_row(body, [
		_label("Spawn extra enemies", Color.WHITE, true),
		spawn_count,
		_button("Spawn", func():
			WaveManager.debug_spawn_enemies(int(spawn_count.value))
			_say("Spawned %d enemies." % int(spawn_count.value), GOOD)),
	])

	var freeze := CheckBox.new()
	freeze.text = "Freeze spawns (wave timer keeps running)"
	freeze.button_pressed = WaveManager.spawns_paused
	freeze.toggled.connect(func(on: bool):
		WaveManager.spawns_paused = on
		_say("Spawns %s." % ("frozen" if on else "running")))
	body.add_child(freeze)

	_row(body, [
		_button("Kill all enemies", func():
			var killed := _kill_all_enemies(false)
			_say("Killed %d enemies." % killed, GOOD)),
		_button("Kill all + boss", func():
			var killed := _kill_all_enemies(true)
			_say("Killed %d (boss included)." % killed, GOOD)),
	])

# -- Bosses -----------------------------------------------------------------
func _build_bosses_tab(body: VBoxContainer) -> void:
	if _warn_if_client(body):
		return

	_section(body, "Encounters")
	var roster := _boss_catalogue()
	if roster.is_empty():
		body.add_child(_label("No BossData found under %s." % BOSS_DATA_DIR, WARN))
		return

	for data in roster:
		var boss: BossData = data
		var phases := boss.phases.size() if boss.phases != null else 0
		_row(body, [
			_label(boss.boss_name, Color.WHITE, true),
			_label("wave %d · %d HP · %d phases" % [boss.wave_trigger, boss.max_health, phases], DIM),
			_button("Fight", func():
				BossManager.debug_force_spawn(boss)
				_say("Spawned %s." % boss.boss_name, GOOD)
				close()),
		])

	_section(body, "Live fight")
	_row(body, [
		_button("Despawn boss (no rewards)", func():
			BossManager.debug_end_encounter()
			_say("Boss encounter cleared.")),
		_button("Kill boss (pays out)", func():
			var killed := _kill_bosses()
			_say("Killed %d boss(es)." % killed, GOOD)),
	])
	body.add_child(_label(
		"\"Fight\" closes the panel so you land straight in the encounter.", DIM))

# -- Weapons ----------------------------------------------------------------
func _build_weapons_tab(body: VBoxContainer) -> void:
	var inventory := WeaponInventory.instance
	if inventory == null:
		body.add_child(_label("No WeaponInventory — is a Player in the arena?", WARN))
		return

	_section(body, "Equipped (%d / %d)" % [inventory.equipped_weapons.size(), inventory.max_weapon_slots])
	if inventory.equipped_weapons.is_empty():
		body.add_child(_label("Nothing equipped.", DIM))

	for i in range(inventory.equipped_weapons.size()):
		var weapon: Weapon = inventory.equipped_weapons[i]
		var weapon_name: String = weapon.data.name if weapon.data != null else "(no data)"
		var index := i
		_row(body, [
			_label(weapon_name, Color.WHITE, true),
			_button("Remove", func():
				inventory.remove_weapon_at(index)
				_say("Removed %s." % weapon_name)
				_rebuild_all_tabs.call_deferred()),
		])

	_row(body, [
		_button("Clear loadout", func():
			inventory.clear_all_weapons()
			_say("Loadout cleared.")
			_rebuild_all_tabs.call_deferred()),
	])

	_section(body, "Catalogue")
	for data in _weapon_catalogue():
		var weapon_data: WeaponData = data
		_row(body, [
			_label(weapon_data.name, Color.WHITE, true),
			_label("%.0f dmg · %.2f/s" % [weapon_data.damage, weapon_data.attack_speed], DIM),
			_button("Equip", func():
				if WeaponInventory.instance.try_add_weapon(weapon_data):
					_say("Equipped %s." % weapon_data.name, GOOD)
					_rebuild_all_tabs.call_deferred()
				else:
					_say("No free slot — remove one first.", WARN)),
		])

# -- Hunter -----------------------------------------------------------------
func _build_hunter_tab(body: VBoxContainer) -> void:
	var stats := PlayerStats.instance
	var health := _player_health()
	if stats == null or health == null:
		body.add_child(_label("No Player in the arena.", WARN))
		return

	_section(body, "Survival")
	body.add_child(_label("HP %d / %d · armor %d · dodge %.0f%%" % [
		health.current_health, health.max_health, health.armor, health.dodge_chance * 100.0], DIM))

	var god := CheckBox.new()
	god.text = "God mode (dodge everything)"
	god.button_pressed = _god_mode
	god.toggled.connect(func(on: bool): _set_god_mode(on))
	body.add_child(god)

	var heal_amount := _spin(1, 9999, 10, 100)
	_row(body, [
		_button("Full heal", func():
			health.heal(health.max_health)
			_say("Healed to full.", GOOD)
			_rebuild_all_tabs.call_deferred()),
		_label("Max HP +", Color.WHITE, true),
		heal_amount,
		_button("Add", func():
			health.increase_max_health(int(heal_amount.value))
			_say("Max HP now %d." % health.max_health, GOOD)
			_rebuild_all_tabs.call_deferred()),
	])
	_number_row(body, "Armor", func(): return health.armor,
		func(v: float): health.armor = int(v), 0, 500, 1)

	_section(body, "Offence")
	_number_row(body, "Damage multiplier", func(): return stats.damage_multiplier,
		func(v: float): stats.damage_multiplier = v, 0.1, 100.0, 0.1)
	_number_row(body, "Attack speed multiplier", func(): return stats.attack_speed_multiplier,
		func(v: float): stats.attack_speed_multiplier = v, 0.1, 20.0, 0.1)
	_number_row(body, "Extra crit chance", func(): return stats.extra_crit_chance,
		func(v: float): stats.extra_crit_chance = v, 0.0, 1.0, 0.05)
	_number_row(body, "Extra crit multiplier", func(): return stats.extra_crit_multiplier,
		func(v: float): stats.extra_crit_multiplier = v, 0.0, 20.0, 0.5)
	_number_row(body, "Lifesteal fraction", func(): return stats.lifesteal_fraction,
		func(v: float): stats.lifesteal_fraction = v, 0.0, 1.0, 0.05)

	_section(body, "Mobility & pickup")
	_number_row(body, "Move speed multiplier", func(): return stats.move_speed_multiplier,
		func(v: float): stats.move_speed_multiplier = v, 0.1, 10.0, 0.1)
	_number_row(body, "Pickup radius bonus", func(): return stats.pickup_radius_bonus,
		func(v: float): stats.pickup_radius_bonus = v, 0.0, 2000.0, 25.0)
	_number_row(body, "Luck", func(): return stats.luck,
		func(v: float): stats.luck = v, 0.0, 100.0, 1.0)

	_section(body, "Progression")
	var xp_amount := _spin(1, 100000, 50, 250)
	_row(body, [
		_label("Grant XP", Color.WHITE, true),
		xp_amount,
		_button("Add", func():
			stats.add_xp(int(xp_amount.value))
			_say("Level %d, %d/%d XP, %d boons queued." % [
				stats.level, stats.current_xp, stats.xp_to_next_level, stats.pending_boons], GOOD)),
	])
	var coin_amount := _spin(1, 100000, 50, 500)
	_row(body, [
		_label("Grant Grave Coin", Color.WHITE, true),
		coin_amount,
		_button("Add", func():
			GameManager.add_currency(int(coin_amount.value))
			_say("Balance %d." % GameManager.currency, GOOD)),
	])
	_row(body, [
		_button("Open a boon pick", func():
			stats.pending_boons += 1
			if stats.pop_next_boon():
				_say("Boon screen queued.", GOOD)
				close()),
	])

	_section(body, "Reset")
	_row(body, [
		_label("Undo every stat edit made since the panel first opened.", DIM, true),
		_button("Restore snapshot", func():
			_restore_snapshot()
			_say("Stats restored.", GOOD)
			_rebuild_all_tabs.call_deferred()),
	])

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
func _warn_if_client(body: VBoxContainer) -> bool:
	if NetSession == null or not NetSession.is_client():
		return false

	body.add_child(_label(
		"Connected as a client. Waves and bosses are the host's to drive — "
		+ "changing them here would only desync you.", WARN))
	return true

func _kill_all_enemies(include_bosses: bool) -> int:
	var killed := 0
	for node in get_tree().get_nodes_in_group("Enemy"):
		if not is_instance_valid(node):
			continue

		if not include_bosses and node.is_in_group("Boss"):
			continue

		var health: HealthComponent = node.get_node_or_null("HealthComponent")
		if health == null or health.is_dead:
			continue

		health.take_damage(health.current_health + health.armor + 1, self)
		killed += 1

	return killed

func _kill_bosses() -> int:
	var killed := 0
	for node in get_tree().get_nodes_in_group("Boss"):
		if not is_instance_valid(node):
			continue

		var health: HealthComponent = node.get_node_or_null("HealthComponent")
		if health == null or health.is_dead:
			continue

		health.take_damage(health.current_health + health.armor + 1, self)
		killed += 1

	return killed

# Full dodge rather than a damage multiplier: HealthComponent floors every hit
# at 1 damage on purpose, so mitigation can never reach invulnerability — but a
# dodge is checked before any of that and skips the hit outright.
func _set_god_mode(on: bool) -> void:
	var health := _player_health()
	if health == null:
		return

	if on and not _god_mode:
		_saved_dodge = health.dodge_chance

	_god_mode = on
	health.dodge_chance = 1.0 if on else _saved_dodge
	_say("God mode %s." % ("ON" if on else "off"), GOOD if on else Color.WHITE)

func _player() -> Node2D:
	return get_tree().get_first_node_in_group("Player") as Node2D

func _player_health() -> HealthComponent:
	var player := _player()
	return player.get_node_or_null("HealthComponent") if player != null else null

func _capture_snapshot() -> void:
	if not _stat_snapshot.is_empty():
		return

	var stats := PlayerStats.instance
	if stats == null:
		return

	_stat_snapshot = {
		"damage_multiplier": stats.damage_multiplier,
		"move_speed_multiplier": stats.move_speed_multiplier,
		"attack_speed_multiplier": stats.attack_speed_multiplier,
		"extra_crit_chance": stats.extra_crit_chance,
		"extra_crit_multiplier": stats.extra_crit_multiplier,
		"lifesteal_fraction": stats.lifesteal_fraction,
		"pickup_radius_bonus": stats.pickup_radius_bonus,
		"luck": stats.luck,
		"enemy_density_multiplier": stats.enemy_density_multiplier,
	}

func _restore_snapshot() -> void:
	var stats := PlayerStats.instance
	if stats == null or _stat_snapshot.is_empty():
		return

	for key in _stat_snapshot:
		stats.set(key, _stat_snapshot[key])

	_set_god_mode(false)

# ---------------------------------------------------------------------------
# Catalogues
# ---------------------------------------------------------------------------
func _boss_catalogue() -> Array:
	# Every BossData on disk, not just BossManager's roster: the point of the
	# tab is to reach the ones the wave loop will not hand you.
	var out: Array = []
	for path in _list_resources(BOSS_DATA_DIR):
		var data := load(path) as BossData
		if data != null:
			out.append(data)

	out.sort_custom(func(a: BossData, b: BossData): return a.wave_trigger < b.wave_trigger)
	return out

func _weapon_catalogue() -> Array:
	var out: Array = []
	var pool := load(SHOP_POOL_PATH) as ShopPoolData
	if pool != null:
		for weapon in pool.weapon_pool:
			if weapon != null and not out.has(weapon):
				out.append(weapon)

	# Anything on disk but not in the shop pool still shows up — a weapon you
	# cannot buy yet is exactly the one worth trying here.
	for path in _list_resources(WEAPON_DATA_DIR):
		var data := load(path) as WeaponData
		if data != null and not out.has(data):
			out.append(data)

	out.sort_custom(func(a: WeaponData, b: WeaponData): return a.name < b.name)
	return out

func _list_resources(dir_path: String) -> Array:
	var seen := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[DebugMenu] Cannot open %s." % dir_path)
		return []

	for file in dir.get_files():
		# Exported builds list "Foo.tres.remap"; the loadable path is the stem.
		if file.ends_with(".remap"):
			file = file.trim_suffix(".remap")

		if file.ends_with(".tres"):
			seen[dir_path + "/" + file] = true

	var paths := seen.keys()
	paths.sort()
	return paths
