extends CanvasLayer
class_name IntermissionSplit

# Local-coop intermission. Each hunter's real shop/boon UI is docked into a
# pane that fills its half (or quarter) of the screen. The shop reflows at
# native font size instead of shrinking a 1280×720 layout into a postage stamp.
# 2 players stack top/bottom; 3–4 use a 2×2 grid.

const GAP := 3.0

var _root: Control
var _layout: Control
var _cells: Dictionary = {}
var _hosts: Dictionary = {}
var _remote_shops: Dictionary = {}
var _remote_levels: Dictionary = {}
var _script_bucket: Node
var _shop_home: Node
var _level_home: Node
var _shop_root: Control
var _level_root: Control
var _hidden_layers: Array = []
var _active: bool = false
var _local_pid: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	visible = false
	EventBus.wave_end.connect(_on_wave_end)
	if NetSession != null:
		NetSession.all_hunters_ready.connect(_on_all_ready)
		NetSession.intermission_view.connect(_on_view)
	_build.call_deferred()

func _process(_delta: float) -> void:
	if _active:
		_refit()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.0, 0.02, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_script_bucket = Node.new()
	_script_bucket.name = "ReplicaScripts"
	add_child(_script_bucket)

func _on_wave_end(_wave: int) -> void:
	if NetSession == null or not NetSession.is_active:
		return
	if NetSession.roster.size() < 2:
		return
	_begin()

func _on_all_ready() -> void:
	_end()

func _begin() -> void:
	if _active:
		return
	_active = true
	visible = true
	_local_pid = NetSession.local_pid
	_capture_local_ui()
	_hide_other_layers()
	_rebuild_panes()
	_dock_local()
	call_deferred("_refit")
	var board := get_tree().current_scene.get_node_or_null("CovenBoard") as CanvasLayer
	if board != null:
		board.visible = false

func _end() -> void:
	if not _active:
		return
	_undock_local()
	_clear_panes()
	_restore_other_layers()
	_active = false
	visible = false

func _capture_local_ui() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var shop := scene.get_node_or_null("ShopUI")
	var level := scene.get_node_or_null("LevelUpUI")
	if shop != null:
		_shop_home = shop
		_shop_root = shop.get_node_or_null("RootPanel") as Control
	if level != null:
		_level_home = level
		_level_root = level.get_node_or_null("RootPanel") as Control

func _hide_other_layers() -> void:
	_hidden_layers.clear()
	var scene := get_tree().current_scene
	if scene == null:
		return
	for path in ["HUD", "UI"]:
		var node := scene.get_node_or_null(path)
		if node is CanvasLayer and (node as CanvasLayer).visible:
			(node as CanvasLayer).visible = false
			_hidden_layers.append(node)

func _restore_other_layers() -> void:
	for node in _hidden_layers:
		if node != null and is_instance_valid(node):
			node.visible = true
	_hidden_layers.clear()

func _pids() -> Array:
	var pids: Array = []
	if NetSession == null:
		return pids
	for entry in NetSession.roster:
		if typeof(entry) == TYPE_DICTIONARY:
			var pid := int(entry.get("pid", 0))
			if pid > 0:
				pids.append(pid)
	pids.sort()
	if _local_pid > 0 and pids.has(_local_pid):
		pids.erase(_local_pid)
		pids.push_front(_local_pid)
	return pids

func _label_for(pid: int) -> String:
	var who := "Hunter"
	if NetSession != null:
		for entry in NetSession.roster:
			if typeof(entry) == TYPE_DICTIONARY and int(entry.get("pid", 0)) == pid:
				who = str(entry.get("char", who))
				break
	if pid == _local_pid:
		who += "  (you)"
	return who

func _rebuild_panes() -> void:
	_clear_panes()
	var pids := _pids()
	var n: int = pids.size()
	if n <= 0:
		return

	var split := VBoxContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.offset_left = GAP
	split.offset_top = GAP
	split.offset_right = -GAP
	split.offset_bottom = -GAP
	split.add_theme_constant_override("separation", GAP)
	_root.add_child(split)
	_layout = split

	if n == 2:
		_add_pane(split, pids[0])
		_add_pane(split, pids[1])
		return

	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", GAP)
	split.add_child(top)
	var bot := HBoxContainer.new()
	bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bot.add_theme_constant_override("separation", GAP)
	split.add_child(bot)
	var slots: Array = [top, top, bot, bot]
	for i in range(4):
		if i < n:
			_add_pane(slots[i], pids[i])
		else:
			var filler := ColorRect.new()
			filler.color = Color(0.02, 0.01, 0.03, 1)
			filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
			slots[i].add_child(filler)

func _add_pane(parent: Control, pid: int) -> void:
	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.clip_contents = true
	cell.mouse_filter = Control.MOUSE_FILTER_STOP if pid == _local_pid else Control.MOUSE_FILTER_IGNORE
	parent.add_child(cell)
	_cells[pid] = cell

	var frame := ColorRect.new()
	frame.color = Color(0.07, 0.04, 0.10, 1)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(frame)

	var host := Control.new()
	host.name = "Host_%d" % pid
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP if pid == _local_pid else Control.MOUSE_FILTER_IGNORE
	host.clip_contents = true
	cell.add_child(host)
	_hosts[pid] = host

	var nameplate := Label.new()
	nameplate.text = _label_for(pid)
	nameplate.set_anchors_preset(Control.PRESET_TOP_WIDE)
	nameplate.offset_left = 12
	nameplate.offset_right = -12
	nameplate.offset_bottom = 20
	nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nameplate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nameplate.theme_type_variation = &"GoldLabel"
	nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(nameplate)

	if pid != _local_pid:
		_spawn_replicas(pid, host)

func _refit() -> void:
	for pid in _hosts.keys():
		var host: Control = _hosts[pid]
		if host == null or not is_instance_valid(host):
			continue
		var pane: Vector2 = host.size
		if pane.x < 8.0 or pane.y < 8.0:
			continue
		_layout_pid(int(pid), pane)

func _layout_pid(pid: int, pane: Vector2) -> void:
	if pid == _local_pid:
		if _shop_home is ShopUI:
			(_shop_home as ShopUI).apply_pane_layout(pane)
		if _level_home is LevelUpUI:
			(_level_home as LevelUpUI).apply_pane_layout(pane)
		return
	var shop: ShopUI = _remote_shops.get(pid)
	if shop != null:
		shop.apply_pane_layout(pane)
	var level: LevelUpUI = _remote_levels.get(pid)
	if level != null:
		level.apply_pane_layout(pane)


func _dock_local() -> void:
	var host: Control = _hosts.get(_local_pid)
	if host == null:
		return
	if _shop_root != null:
		_shop_root.reparent(host)
		_fit(_shop_root)
	if _level_root != null:
		_level_root.reparent(host)
		_fit(_level_root)

func _spawn_replicas(pid: int, host: Control) -> void:
	var shop_scene: PackedScene = load("res://Scenes/UI/ShopUI.tscn")
	var level_scene: PackedScene = load("res://Scenes/UI/LevelUpUI.tscn")
	if shop_scene != null:
		var shop: ShopUI = shop_scene.instantiate() as ShopUI
		shop.is_replica = true
		shop.name = "ReplicaShop_%d" % pid
		shop.layer = 0
		_script_bucket.add_child(shop)
		var shop_root := shop.get_node_or_null("RootPanel") as Control
		if shop_root != null:
			shop_root.reparent(host)
			_fit(shop_root)
		_remote_shops[pid] = shop
	if level_scene != null:
		var level: LevelUpUI = level_scene.instantiate() as LevelUpUI
		level.is_replica = true
		level.name = "ReplicaBoon_%d" % pid
		level.layer = 0
		_script_bucket.add_child(level)
		var level_root := level.get_node_or_null("RootPanel") as Control
		if level_root != null:
			level_root.reparent(host)
			_fit(level_root)
		_remote_levels[pid] = level
	if NetSession.intermission_states.has(pid):
		_apply_replica(pid, NetSession.intermission_states[pid])

func _apply_replica(pid: int, st: Dictionary) -> void:
	var shop: ShopUI = _remote_shops.get(pid)
	var level: LevelUpUI = _remote_levels.get(pid)
	if shop != null:
		shop.apply_net_state(st)
	if level != null:
		level.apply_net_state(st)

func _undock_local() -> void:
	if _shop_home is ShopUI:
		(_shop_home as ShopUI).apply_pane_layout(Vector2(1280, 720))
	if _level_home is LevelUpUI:
		(_level_home as LevelUpUI).apply_pane_layout(Vector2(1280, 720))
	if _shop_root != null and _shop_home != null and is_instance_valid(_shop_root):
		_shop_root.reparent(_shop_home)
		_fit(_shop_root)
	if _level_root != null and _level_home != null and is_instance_valid(_level_root):
		_level_root.reparent(_level_home)
		_fit(_level_root)

func _fit(ctrl: Control) -> void:
	ctrl.scale = Vector2.ONE
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0

func _clear_panes() -> void:
	_undock_local()
	_cells.clear()
	_hosts.clear()
	for shop in _remote_shops.values():
		if shop != null and is_instance_valid(shop):
			shop.queue_free()
	for level in _remote_levels.values():
		if level != null and is_instance_valid(level):
			level.queue_free()
	_remote_shops.clear()
	_remote_levels.clear()
	if _layout != null and is_instance_valid(_layout):
		_layout.queue_free()
		_layout = null

func _on_view(states: Dictionary) -> void:
	for pid in states.keys():
		if int(pid) == _local_pid:
			continue
		_apply_replica(int(pid), states[pid])
