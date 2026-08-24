extends CanvasLayer
class_name CovenBoard

# Strip along the top during intermission so each hunter can see what the
# others are doing — boon pick, ossuary, or ready — without sharing one cursor.

var _bar: ColorRect
var _label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	visible = false
	if NetSession != null:
		NetSession.intermission_view.connect(_on_view)
		NetSession.all_hunters_ready.connect(hide_board)
	EventBus.wave_end.connect(_on_wave_end)
	_build.call_deferred()

func _build() -> void:
	_bar = ColorRect.new()
	_bar.color = Color(0.04, 0.02, 0.06, 0.92)
	_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_bottom = 52.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 16
	_label.offset_right = -16
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_label)
	if visible and NetSession != null:
		_on_view(NetSession.intermission_states)

func _on_wave_end(_wave: int) -> void:
	if NetSession == null or not NetSession.is_active:
		return
	visible = true
	_on_view(NetSession.intermission_states)

func hide_board() -> void:
	visible = false

func _on_view(states: Dictionary) -> void:
	if _label == null:
		return
	if states.is_empty():
		_label.text = "COVEN — waiting for the other hunter…"
		return
	var bits: PackedStringArray = PackedStringArray()
	for pid in states.keys():
		var st: Dictionary = states[pid]
		var who := str(st.get("char", "Hunter"))
		if int(pid) == (NetSession.local_pid if NetSession != null else -1):
			who += " (you)"
		var phase := str(st.get("phase", ""))
		var gold := int(st.get("gold", 0))
		var phase_text := "in the Ossuary"
		if phase == "boon":
			phase_text = "choosing a moon boon"
		elif phase == "ready":
			phase_text = "ready"
		var weapons: Variant = st.get("weapons", [])
		var loadout := ""
		if typeof(weapons) == TYPE_ARRAY and weapons.size() > 0:
			loadout = "  ·  " + ", ".join(PackedStringArray(weapons))
		bits.append("%s — %s  %dg%s" % [who, phase_text, gold, loadout])
	_label.text = "   |   ".join(bits)
