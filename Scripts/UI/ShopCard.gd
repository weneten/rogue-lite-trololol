extends PanelContainer
class_name ShopCard

# One thing for sale in the Ossuary.
#
# Built in code rather than authored as a scene: the shelf mixes weapons and
# relics, the offer count is a designer dial, and the card has to restyle
# itself to the offer's rarity on every reroll. Six near-identical subtrees in
# a .tscn would have to be kept in sync by hand for none of that.
#
# The card owns presentation only. Price, affordability and what buying does
# all live in ShopUI/ShopEconomy; this asks for a purchase and is told how to
# look.

signal buy_requested
signal lock_toggled(locked: bool)

const FRAME_PATH := "res://Assets/UI/frame_rarity_%d.png"
const COIN_PATH := "res://Assets/UI/icon_coin.png"
const LOCK_PATH := "res://Assets/UI/icon_lock.png"

const CARD_SIZE := Vector2(196.0, 268.0)
const ICON_SIZE := Vector2(72.0, 72.0)

const RARITY_NAME := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLOR := [
	Color(0.49, 0.45, 0.53),
	Color(0.31, 0.62, 0.42),
	Color(0.25, 0.50, 0.77),
	Color(0.63, 0.35, 0.83),
	Color(0.88, 0.63, 0.20),
]

var _icon: TextureRect
var _name_label: Label
var _kind_label: Label
var _stats_label: Label
var _flavour_label: Label
var _lock_button: Button
var _locked: bool = false

# The purchase control, exposed so the shop can hand it keyboard focus.
var buy_button: Button

# What this card is currently offering. null once the offer has been bought.
var offer = null
var is_weapon: bool = false

var locked: bool:
	get:
		return _locked


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()


func apply_pane_size(size: Vector2) -> void:
	if size.x < 8.0 or size.y < 8.0:
		custom_minimum_size = CARD_SIZE
		size_flags_horizontal = Control.SIZE_FILL
		size_flags_vertical = Control.SIZE_FILL
		_set_icon_px(ICON_SIZE.y)
		if _flavour_label != null:
			_flavour_label.visible = true
		return
	custom_minimum_size = size
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var compact := size.y < 230.0 or size.x < 170.0
	if _flavour_label != null:
		_flavour_label.visible = not compact
	var icon_px := ICON_SIZE.y
	if size.y < 190.0:
		icon_px = 40.0
	elif size.y < 230.0:
		icon_px = 52.0
	_set_icon_px(icon_px)


func _set_icon_px(icon_px: float) -> void:
	if _icon != null:
		_icon.custom_minimum_size = Vector2(icon_px, icon_px)
	var frame := _icon.get_parent() as Control if _icon != null else null
	if frame != null:
		frame.custom_minimum_size = Vector2(0, icon_px + 8.0)


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	root.add_child(header)

	_kind_label = Label.new()
	_kind_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kind_label.theme_type_variation = &"StatLabel"
	header.add_child(_kind_label)

	# Locking a card holds it through rerolls — the one control that makes
	# rerolling a decision rather than a slot machine.
	_lock_button = Button.new()
	_lock_button.theme_type_variation = &"FlatButton"
	_lock_button.icon = _load(LOCK_PATH)
	_lock_button.custom_minimum_size = Vector2(28, 28)
	_lock_button.tooltip_text = "Hold through rerolls"
	_lock_button.pressed.connect(_on_lock_pressed)
	header.add_child(_lock_button)

	var icon_frame := CenterContainer.new()
	icon_frame.custom_minimum_size = Vector2(0, ICON_SIZE.y + 8)
	root.add_child(icon_frame)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = ICON_SIZE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Icons are 32px art shown at 72px. Without nearest filtering the whole
	# shelf goes soft.
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_frame.add_child(_icon)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.theme_type_variation = &"SubtitleLabel"
	root.add_child(_name_label)

	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.theme_type_variation = &"StatLabel"
	root.add_child(_stats_label)

	_flavour_label = Label.new()
	_flavour_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flavour_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flavour_label.theme_type_variation = &"TooltipLabel"
	_flavour_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_flavour_label)

	buy_button = Button.new()
	buy_button.icon = _load(COIN_PATH)
	buy_button.pressed.connect(func(): buy_requested.emit())
	root.add_child(buy_button)
	UIAnim.juice_button(buy_button)


# -------------------------------------------------------------------- content

func apply_net(row: Dictionary) -> void:
	if bool(row.get("sold", true)):
		clear()
		if buy_button != null:
			buy_button.disabled = true
		return
	visible = true
	offer = self
	if _kind_label != null:
		_kind_label.text = str(row.get("k", ""))
	if _name_label != null:
		_name_label.text = str(row.get("n", ""))
	if _stats_label != null:
		_stats_label.text = str(row.get("s", ""))
	if _flavour_label != null:
		_flavour_label.text = str(row.get("f", ""))
	if buy_button != null:
		buy_button.text = str(row.get("c", ""))
		buy_button.disabled = true
	var ipath := str(row.get("i", ""))
	if _icon != null:
		_icon.texture = load(ipath) if not ipath.is_empty() and ResourceLoader.exists(ipath) else null
	modulate.a = float(row.get("a", 1.0))
	set_locked(bool(row.get("l", false)))
	if _lock_button != null:
		_lock_button.disabled = true


func to_net() -> Dictionary:
	if offer == null:
		return {"sold": true}
	var icon_path := ""
	if offer.icon != null:
		icon_path = offer.icon.resource_path
	return {
		"sold": false,
		"n": _name_label.text if _name_label != null else "",
		"k": _kind_label.text if _kind_label != null else "",
		"s": _stats_label.text if _stats_label != null else "",
		"f": _flavour_label.text if _flavour_label != null else "",
		"c": buy_button.text if buy_button != null else "",
		"l": _locked,
		"i": icon_path,
		"a": modulate.a,
	}


# `owned_level` is 0 when the Hunter is not carrying this weapon, otherwise the
# level of the one they have. A card offering an upgrade has to say so: the
# price is different, the effect is different, and it does not cost a slot.
func show_weapon(data: WeaponData, price: int, owned_level: int = 0) -> void:
	offer = data
	is_weapon = true
	visible = true

	if owned_level > 0:
		_kind_label.text = "UPGRADE - LV %d > %d" % [owned_level, owned_level + 1]
	else:
		_kind_label.text = "WEAPON - %s" % RARITY_NAME[clampi(data.rarity_tier, 0, 4)].to_upper()
	_name_label.text = data.name
	_icon.texture = data.icon
	_stats_label.text = _weapon_stats(data)
	_flavour_label.text = _class_line(data.weapon_class)
	buy_button.text = "%dg" % price
	_apply_rarity(data.rarity_tier)


# `owned_count` is how many copies the Hunter already carries. Relics stack, so
# a second one is a real purchase and the card says which copy it would be.
func show_relic(data: PassiveItemData, price: int, owned_count: int = 0) -> void:
	offer = data
	is_weapon = false
	visible = true

	if owned_count > 0:
		_kind_label.text = "RELIC - STACK %d > %d" % [owned_count, owned_count + 1]
	else:
		_kind_label.text = "RELIC - %s" % RARITY_NAME[clampi(data.rarity_tier, 0, 4)].to_upper()
	_name_label.text = data.display_name
	_icon.texture = data.icon
	_stats_label.text = data.stat_line()
	_flavour_label.text = data.description
	buy_button.text = "%dg" % price
	_apply_rarity(data.rarity_tier)


# An empty card stays in the tree so the shelf keeps its columns; hiding it
# would let the remaining cards slide sideways mid-shop.
func clear() -> void:
	offer = null
	set_locked(false)
	_kind_label.text = ""
	_name_label.text = ""
	_stats_label.text = ""
	_flavour_label.text = "Sold"
	_icon.texture = null
	buy_button.text = "-"
	buy_button.disabled = true
	modulate.a = 0.35


func set_affordable(affordable: bool, price: int = -1) -> void:
	if offer == null:
		return

	buy_button.disabled = not affordable
	if price >= 0:
		buy_button.text = "%dg" % price
	# Dim the whole card, not just the button: at a glance the player should
	# see what they can afford without reading five prices.
	modulate.a = 1.0 if affordable else 0.55


# A weapon you cannot buy because every slot is taken looks identical to one you
# cannot afford, and the fix is completely different — sell something, not earn
# more. So it says which.
func set_slots_full() -> void:
	if offer == null:
		return

	buy_button.disabled = true
	buy_button.text = "SLOTS FULL"
	buy_button.tooltip_text = "Sell a weapon first"
	modulate.a = 0.55


# A weapon already carried at MAX_LEVEL cannot be bought again, and that is a
# third distinct reason from "too expensive" and "no slots" — none of the three
# has the same fix.
func set_max_level() -> void:
	if offer == null:
		return

	buy_button.disabled = true
	buy_button.text = "MAX LV"
	buy_button.tooltip_text = "This weapon is fully upgraded"
	modulate.a = 0.55


func set_locked(value: bool) -> void:
	_locked = value
	_lock_button.modulate = Color(1.0, 0.85, 0.4) if value else Color(1, 1, 1, 0.45)


func _on_lock_pressed() -> void:
	if offer == null:
		return

	set_locked(not _locked)
	AudioManager.play_sfx("ui_click")
	lock_toggled.emit(_locked)


# The rarity frame is the card's background, so tier is legible from across the
# screen before any text is read.
func _apply_rarity(tier: int) -> void:
	var index := clampi(tier, 0, 4)
	var texture := _load(FRAME_PATH % index)
	if texture == null:
		return

	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = 5
	box.texture_margin_top = 5
	box.texture_margin_right = 5
	box.texture_margin_bottom = 5
	box.content_margin_left = 12
	box.content_margin_top = 10
	box.content_margin_right = 12
	box.content_margin_bottom = 10
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	add_theme_stylebox_override("panel", box)

	_kind_label.add_theme_color_override("font_color", RARITY_COLOR[index])


static func _weapon_stats(data: WeaponData) -> String:
	var lines: Array[String] = []
	lines.append("%d dmg   %.1f/s" % [roundi(data.damage), data.attack_speed])
	lines.append("%d range" % roundi(data.range))
	if data.projectile_count > 1:
		lines.append("x%d shots" % data.projectile_count)
	if data.crit_chance > 0.0:
		lines.append("%d%% crit" % roundi(data.crit_chance * 100.0))
	return "\n".join(lines)


# Weapons carry no flavour text, so the card says what the thing IS instead —
# which is the part that decides whether it fits the build.
static func _class_line(flags: int) -> String:
	var names: Array[String] = []
	for entry in [
		[WeaponData.WeaponClass.MELEE, "Melee"],
		[WeaponData.WeaponClass.RANGED, "Ranged"],
		[WeaponData.WeaponClass.FIREARM, "Firearm"],
		[WeaponData.WeaponClass.MAGIC, "Magic"],
		[WeaponData.WeaponClass.HOLY, "Holy"],
		[WeaponData.WeaponClass.CURSED, "Cursed"],
		[WeaponData.WeaponClass.AOE, "AoE"],
		[WeaponData.WeaponClass.SUMMON, "Summon"],
		[WeaponData.WeaponClass.TRAP, "Trap"],
	]:
		if (flags & int(entry[0])) != 0:
			names.append(str(entry[1]))

	return " / ".join(names)


static func _load(path: String) -> Texture2D:
	return ResourceLoader.load(path, "Texture2D") as Texture2D if ResourceLoader.exists(path) else null
