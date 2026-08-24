extends CanvasLayer
class_name IntermissionSplit

# Brotato-style intermission: 2 hunters split left/right, 3–4 use a 2×2 grid.
# Local shop/boon UI is reparented into your cell; friends get a live replica.

const VIEW_SIZE := Vector2i(1280, 720)

var _root: Control
var _grid: GridContainer
var _cells: Array[Control] = []
var _viewports: Dictionary = {}
var _remote_panes: Dictionary = {}
var _shop_home: Node
var _level_home: Node
var _shop_root: Control
var _level_root: Control
var _active: bool = false
var _local_pid: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 18
	visible = false
	EventBus.wave_end.connect(_on_wave_end)
	if NetSession != null:
		NetSession.all_hunters_ready.connect(_on_all_ready)
		NetSession.intermission_view.connect(_on_view)
	_build.call_deferred()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.0, 0.02, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_grid = GridContainer.new()
	_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	_root.add_child(_grid)

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
	_rebuild_cells()
	_dock_local()
	var board := get_tree().current_scene.get_node_or_null("CovenBoard") as CanvasLayer
	if board != null:
		board.visible = false

func _end() -> void:
	if not _active:
		return
	_undock_local()
	_clear_cells()
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

func _pids() -> Array:
	var pids: Array = []
	if NetSession == null:
		return pids
	for entry in NetSession.roster:
		if typeof(entry) == TYPE_DICTIONARY:
			pids.append(int(entry.get("pid", 0)))
	pids.sort()
	return pids

func _rebuild_cells() -> void:
	_clear_cells()
	var pids := _pids()
	var n: int = pids.size()
	_grid.columns = 2 if n >= 3 else maxi(1, n)
	var slots: int = 4 if n >= 3 else n
	for i in range(slots):
		var cell := Control.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_grid.add_child(cell)
		_cells.append(cell)
		if i >= n:
			var empty := ColorRect.new()
			empty.color = Color(0.02, 0.01, 0.03, 1)
			empty.set_anchors_preset(Control.PRESET_FULL_RECT)
			cell.add_child(empty)
			continue
		var pid: int = pids[i]
		var wrap := SubViewportContainer.new()
		wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
		wrap.stretch = true
		wrap.mouse_filter = Control.MOUSE_FILTER_STOP if pid == _local_pid else Control.MOUSE_FILTER_IGNORE
		cell.add_child(wrap)
		var vp := SubViewport.new()
		vp.size = VIEW_SIZE
		vp.handle_input_locally = pid == _local_pid
		vp.gui_disable_input = pid != _local_pid
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		wrap.add_child(vp)
		_viewports[pid] = vp
		if pid != _local_pid:
			var pane := RemoteShopPane.new()
			vp.add_child(pane)
			_remote_panes[pid] = pane
			if NetSession.intermission_states.has(pid):
				pane.apply_state(NetSession.intermission_states[pid])

func _dock_local() -> void:
	var vp: SubViewport = _viewports.get(_local_pid)
	if vp == null:
		return
	if _shop_root != null:
		_shop_root.reparent(vp)
		_fit(_shop_root)
	if _level_root != null:
		_level_root.reparent(vp)
		_fit(_level_root)

func _undock_local() -> void:
	if _shop_root != null and _shop_home != null and is_instance_valid(_shop_root):
		_shop_root.reparent(_shop_home)
		_fit(_shop_root)
	if _level_root != null and _level_home != null and is_instance_valid(_level_root):
		_level_root.reparent(_level_home)
		_fit(_level_root)

func _fit(ctrl: Control) -> void:
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0

func _clear_cells() -> void:
	_undock_local()
	_viewports.clear()
	_remote_panes.clear()
	_cells.clear()
	if _grid != null:
		for child in _grid.get_children():
			child.queue_free()

func _on_view(states: Dictionary) -> void:
	for pid in _remote_panes.keys():
		var pane: RemoteShopPane = _remote_panes[pid]
		if pane != null and states.has(pid):
			pane.apply_state(states[pid])
