extends Control
class_name RemoteShopPane

# Read-only copy of another hunter's boon/shop screen, drawn at 1280×720 and
# scaled down inside a split-screen cell.

var _title: Label
var _subtitle: Label
var _gold: Label
var _ready_stamp: Label
var _boon_row: HBoxContainer
var _offer_row: HBoxContainer
var _weapon_row: HBoxContainer
var _relic_row: HBoxContainer
var _shop_block: VBoxContainer
var _boon_block: VBoxContainer
var _pending: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build.call_deferred()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.015, 0.045, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_gold = Label.new()
	_gold.theme_type_variation = &"GoldLabel"
	header.add_child(_gold)

	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"SubtitleLabel"
	col.add_child(_subtitle)

	_boon_block = VBoxContainer.new()
	_boon_block.add_theme_constant_override("separation", 10)
	col.add_child(_boon_block)
	var boon_h := Label.new()
	boon_h.text = "THE MOON GRANTS A BOON"
	boon_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boon_h.theme_type_variation = &"TitleLabel"
	_boon_block.add_child(boon_h)
	_boon_row = HBoxContainer.new()
	_boon_row.add_theme_constant_override("separation", 16)
	_boon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_boon_block.add_child(_boon_row)

	_shop_block = VBoxContainer.new()
	_shop_block.add_theme_constant_override("separation", 12)
	col.add_child(_shop_block)
	var shop_h := Label.new()
	shop_h.text = "THE OSSUARY"
	shop_h.theme_type_variation = &"TitleLabel"
	_shop_block.add_child(shop_h)
	_offer_row = HBoxContainer.new()
	_offer_row.add_theme_constant_override("separation", 10)
	_offer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_block.add_child(_offer_row)
	var loadout := Label.new()
	loadout.text = "LOADOUT"
	loadout.theme_type_variation = &"SubtitleLabel"
	_shop_block.add_child(loadout)
	_weapon_row = HBoxContainer.new()
	_weapon_row.add_theme_constant_override("separation", 8)
	_shop_block.add_child(_weapon_row)
	_relic_row = HBoxContainer.new()
	_relic_row.add_theme_constant_override("separation", 6)
	_shop_block.add_child(_relic_row)

	_ready_stamp = Label.new()
	_ready_stamp.text = "READY"
	_ready_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_stamp.theme_type_variation = &"GoldLabel"
	_ready_stamp.add_theme_font_size_override("font_size", 42)
	col.add_child(_ready_stamp)
	if not _pending.is_empty():
		apply_state(_pending)

func apply_state(st: Dictionary) -> void:
	_pending = st
	if _title == null:
		return
	var who := str(st.get("char", "Hunter"))
	_title.text = who
	_gold.text = "%dg" % int(st.get("gold", 0))
	var phase := str(st.get("phase", "shop"))
	_subtitle.text = "picking a moon boon" if phase == "boon" else ("ready for the next wave" if phase == "ready" else "in the Ossuary")
	_boon_block.visible = phase == "boon"
	_shop_block.visible = phase == "shop" or phase == "ready"
	_ready_stamp.visible = phase == "ready"
	if phase == "boon":
		_fill_boons(st.get("boons", []))
	if phase == "shop" or phase == "ready":
		_fill_offers(st.get("offers", []))
		_fill_icons(_weapon_row, st.get("weapons", []), Vector2(48, 48))
		_fill_relics(st.get("relics", []))

func _fill_boons(rows: Variant) -> void:
	_clear(_boon_row)
	if typeof(rows) != TYPE_ARRAY:
		return
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(280, 200)
		card.theme_type_variation = &"OrnatePanel"
		var box := VBoxContainer.new()
		card.add_child(box)
		var n := Label.new()
		n.text = str(row.get("n", ""))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.theme_type_variation = &"GoldLabel"
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(n)
		var d := Label.new()
		d.text = str(row.get("d", ""))
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.theme_type_variation = &"StatLabel"
		box.add_child(d)
		_boon_row.add_child(card)

func _fill_offers(rows: Variant) -> void:
	_clear(_offer_row)
	if typeof(rows) != TYPE_ARRAY:
		return
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(196, 240)
		card.theme_type_variation = &"InsetPanel"
		if bool(row.get("sold", false)):
			card.modulate.a = 0.35
		else:
			card.modulate.a = float(row.get("a", 1.0))
		var box := VBoxContainer.new()
		card.add_child(box)
		if bool(row.get("l", false)):
			var lock := Label.new()
			lock.text = "HELD"
			lock.theme_type_variation = &"GoldLabel"
			box.add_child(lock)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(72, 72)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var ipath := str(row.get("i", ""))
		if not ipath.is_empty() and ResourceLoader.exists(ipath):
			icon.texture = load(ipath)
		box.add_child(icon)
		var n := Label.new()
		n.text = "Sold" if bool(row.get("sold", false)) else str(row.get("n", ""))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(n)
		var s := Label.new()
		s.text = str(row.get("s", ""))
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.theme_type_variation = &"StatLabel"
		box.add_child(s)
		var c := Label.new()
		c.text = str(row.get("c", ""))
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.theme_type_variation = &"GoldLabel"
		box.add_child(c)
		_offer_row.add_child(card)

func _fill_icons(row: HBoxContainer, names: Variant, size: Vector2) -> void:
	_clear(row)
	if typeof(names) != TYPE_ARRAY:
		return
	for raw in names:
		var label := Label.new()
		label.text = str(raw)
		label.theme_type_variation = &"StatLabel"
		row.add_child(label)

func _fill_relics(rows: Variant) -> void:
	_clear(_relic_row)
	if typeof(rows) != TYPE_ARRAY:
		return
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(32, 32)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var ipath := str(row.get("i", ""))
			if not ipath.is_empty() and ResourceLoader.exists(ipath):
				icon.texture = load(ipath)
			icon.tooltip_text = str(row.get("n", ""))
			_relic_row.add_child(icon)

func _clear(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()
