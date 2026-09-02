extends PanelContainer
class_name BloodBoonExchange

# The Jester's half of the Ossuary: the between-waves counter where Blood Boons are bought.
#
# Two currencies buy them. Grave Coin is the safe trade — it only competes with the shelf.
# XP is the interesting one: it comes out of the run's banked total and can drop the Jester
# back a level, so the slider spells out the level he will land on *before* he commits,
# which is the whole reason this is a slider and not a fixed "trade level" button.
#
# The machine preview above the sliders carries the full odds table on hover: every face,
# its chance at the Jester's current Luck, what it does for how much — including 666's
# damage to the Jester himself, with a lethality warning when that number would kill him.
#
# Built in code and added to ShopUI's left column only when a Jester is in the run, the
# same way SlotMachineUI is spawned only by the passive that needs it.

var _passive: BloodBoonSlotsPassive

var _balance_label: Label
var _machine_panel: PanelContainer
var _machine_warning: Label
var _gold_slider: HSlider
var _gold_label: Label
var _gold_button: Button
var _xp_slider: HSlider
var _xp_label: Label
var _xp_button: Button

# Nothing stops a Jester from buying a hundred Boons at once except patience; the slider
# is capped so it stays readable and so one trade can never zero out a whole run's XP.
const MAX_COINS_PER_TRADE = 20

func _init() -> void:
	theme_type_variation = &"BloodPanel"

func _ready() -> void:
	_passive = BloodBoonSlotsPassive.instance
	_build()

	if _passive != null:
		_passive.coins_changed.connect(func(_c: int): refresh())
	if EventBus != null:
		EventBus.currency_changed.connect(func(_c: int): refresh())
		EventBus.xp_changed.connect(func(_xp: int, _next: int, _level: int): refresh())

	refresh()

# ---------------------------------------------------------------------------- layout

func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	var heading := Label.new()
	heading.text = "BLEEDING WHEEL"
	heading.theme_type_variation = &"StatLabel"
	heading.modulate = Color(1.0, 0.82, 0.45, 0.75)
	column.add_child(heading)

	_balance_label = Label.new()
	_balance_label.theme_type_variation = &"GoldLabel"
	column.add_child(_balance_label)

	column.add_child(_build_machine_preview())

	_machine_warning = Label.new()
	_machine_warning.theme_type_variation = &"DangerLabel"
	_machine_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_machine_warning.visible = false
	column.add_child(_machine_warning)

	var gold_row := _add_trade_row(column, "BUY", _on_gold_buy_pressed)
	_gold_slider = gold_row["slider"]
	_gold_label = gold_row["label"]
	_gold_button = gold_row["button"]

	var xp_row := _add_trade_row(column, "TRADE", _on_xp_trade_pressed)
	_xp_slider = xp_row["slider"]
	_xp_label = xp_row["label"]
	_xp_button = xp_row["button"]

# The three reels as they sit in the corner, purely as a hover target: the odds table,
# every face's damage at the current Luck, and the 666 warning all live in its tooltip.
func _build_machine_preview() -> Control:
	_machine_panel = PanelContainer.new()
	_machine_panel.theme_type_variation = &"InsetPanel"
	_machine_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var reels := HBoxContainer.new()
	reels.alignment = BoxContainer.ALIGNMENT_CENTER
	reels.add_theme_constant_override("separation", 4)
	_machine_panel.add_child(reels)

	for i in range(3):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var path := BloodBoonEconomy.face_icon_path(BloodBoonEconomy.Face.SEVEN)
		if ResourceLoader.exists(path):
			icon.texture = load(path)
		icon.modulate = BloodBoonEconomy.face_color(BloodBoonEconomy.Face.SEVEN)
		reels.add_child(icon)

	return _machine_panel

# Shared shape for both trades: a slider, a line of text spelling out what the trade costs
# and what it leaves behind, and the button that commits it.
func _add_trade_row(column: VBoxContainer, button_text: String, handler: Callable) -> Dictionary:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	column.add_child(spacer)

	var label := Label.new()
	label.theme_type_variation = &"SmallLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)

	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = MAX_COINS_PER_TRADE
	slider.step = 1
	slider.value = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(_v: float): refresh())
	row.add_child(slider)

	var button := Button.new()
	button.text = button_text
	button.theme_type_variation = &"FlatButton"
	button.pressed.connect(handler)
	UIAnim.juice_button(button)
	row.add_child(button)

	return {"slider": slider, "label": label, "button": button}

# --------------------------------------------------------------------------- trading

func _on_gold_buy_pressed() -> void:
	if _passive == null:
		return

	if _passive.try_buy_with_gold(int(_gold_slider.value)):
		AudioManager.play_sfx("ui_purchase")
		UIAnim.punch(self)
	else:
		UIAnim.shake(self)
	refresh()

func _on_xp_trade_pressed() -> void:
	if _passive == null:
		return

	if _passive.try_buy_with_xp(int(_xp_slider.value)):
		AudioManager.play_sfx("ui_purchase")
		UIAnim.punch(self)
	else:
		UIAnim.shake(self)
	refresh()

# -------------------------------------------------------------------------- refresh

static func _boon_word(count: int) -> String:
	return "Boon" if count == 1 else "Boons"

func refresh() -> void:
	if _passive == null:
		visible = false
		return

	var wave: int = _passive.current_wave()
	var stats := PlayerStats.instance

	_balance_label.text = "%d Blood Boons   ·   %d per spin" % [_passive.coins, BloodBoonEconomy.get_spin_cost(wave + 1)]

	_refresh_machine_tooltip(wave)
	_refresh_gold_row(wave)
	_refresh_xp_row(wave, stats)

func _refresh_machine_tooltip(wave: int) -> void:
	var luck: float = _passive.luck()
	var odds := BloodBoonEconomy.face_odds(luck)

	var lines: Array[String] = []
	lines.append("THE BLEEDING WHEEL — Luck %d" % roundi(luck))
	lines.append("Every spin lands three of a kind.")
	lines.append("")

	for face in BloodBoonEconomy.all_faces():
		lines.append("%s  %.1f%%" % [BloodBoonEconomy.face_name(face), float(odds[face]) * 100.0])
		lines.append("   %s" % BloodBoonEconomy.face_effect_text(face, luck, wave))

	lines.append("")
	lines.append("Luck bends the odds toward the good faces and scales every")
	lines.append("damage number on the wheel — 666 included.")

	var self_damage: int = _passive.projected_self_damage()
	var lethal: bool = _passive.is_self_damage_lethal()
	if lethal:
		lines.append("")
		lines.append("!! 666 WOULD DEAL %d AND KILL YOU !!" % self_damage)

	_machine_panel.tooltip_text = "\n".join(lines)

	# The tooltip only exists on hover; a spin that can kill the Jester outright is
	# worth saying out loud on the panel itself.
	_machine_warning.visible = lethal
	if lethal:
		_machine_warning.text = "666 deals %d — lethal at your current health." % self_damage

func _refresh_gold_row(wave: int) -> void:
	var gold: int = GameManager.currency if GameManager != null else 0
	var per_coin: int = BloodBoonEconomy.get_gold_price(1, wave)
	var affordable: int = clampi(int(gold / maxi(1, per_coin)), 0, MAX_COINS_PER_TRADE)

	# A slider whose whole range is unaffordable teaches nothing; clamp it to what the
	# purse can actually cover, keeping 1 as a floor so the row never collapses.
	_gold_slider.max_value = maxi(1, affordable)
	_gold_slider.editable = affordable > 0
	var count: int = mini(int(_gold_slider.value), int(_gold_slider.max_value))
	if count != int(_gold_slider.value):
		_gold_slider.set_value_no_signal(count)

	var price: int = BloodBoonEconomy.get_gold_price(count, wave)
	_gold_label.text = "Gold: %d %s for %dg  (have %dg)" % [count, _boon_word(count), price, gold]
	_gold_button.disabled = affordable <= 0 or gold < price

func _refresh_xp_row(wave: int, stats: PlayerStats) -> void:
	if stats == null:
		_xp_label.text = "XP: unavailable"
		_xp_button.disabled = true
		return

	var banked: int = stats.total_xp_banked()
	var per_coin: int = BloodBoonEconomy.get_xp_price(1, wave)
	var affordable: int = clampi(int(banked / maxi(1, per_coin)), 0, MAX_COINS_PER_TRADE)

	_xp_slider.max_value = maxi(1, affordable)
	_xp_slider.editable = affordable > 0
	var count: int = mini(int(_xp_slider.value), int(_xp_slider.max_value))
	if count != int(_xp_slider.value):
		_xp_slider.set_value_no_signal(count)

	var price: int = BloodBoonEconomy.get_xp_price(count, wave)
	var resulting_level: int = stats.preview_level_after_spending(price)

	var level_text := "stay Level %d" % stats.level
	if resulting_level < stats.level:
		level_text = "drop to Level %d (from %d)" % [resulting_level, stats.level]

	_xp_label.text = "XP: %d %s for %d XP — %s" % [count, _boon_word(count), price, level_text]
	_xp_button.disabled = affordable <= 0 or banked < price
