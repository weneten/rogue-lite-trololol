extends CanvasLayer
class_name ShopUI

# The Ossuary: the between-wave shop.
#
# Opens on EventBus.wave_end, pauses the run, and offers one shelf of cards
# mixing weapons and relics — the Brotato shape, where a shop visit is a single
# spending decision rather than two separate lists. Cards can be locked so a
# reroll is a choice about what to keep, not a slot pull.
#
# The shelf, the loadout tray and the stat panel are all built in code from the
# .tscn's static chrome. The alternative — authoring every card, weapon slot
# and relic pip as a node — meant six copies of everything to keep in sync
# whenever a count changed.
#
# All pricing/reroll maths is delegated to the static ShopEconomy so no number
# here is a magic constant.

@export var shop_pool: ShopPoolData

# One shelf, mixed. Weighted toward weapons early because a run with no damage
# is unrecoverable, then settling once the player has a loadout.
@export var offer_count: int = 4

@export_group("Wiring")
@export var root_panel_path: NodePath
@export var currency_label_path: NodePath
@export var wave_label_path: NodePath
@export var shelf_path: NodePath
@export var reroll_button_path: NodePath
@export var reroll_cost_label_path: NodePath
@export var next_wave_button_path: NodePath
@export var weapon_tray_path: NodePath
@export var relic_tray_path: NodePath
@export var stats_list_path: NodePath
@export var empty_relics_label_path: NodePath

# Selling the last weapon would leave the player unable to fight; block it.
@export var min_weapons_kept: int = 1

var _root_panel: Control
var _currency_label: Label
var _wave_label: Label
var _shelf: HBoxContainer
var _reroll_button: Button
var _reroll_cost_label: Label
var _next_wave_button: Button
var _weapon_tray: Container
var _relic_tray: Container
var _stats_list: VBoxContainer
var _empty_relics_label: Label

var _cards: Array[ShopCard] = []
var _rerolls_this_visit: int = 0
var _open: bool = false

func _ready() -> void:
	# Lets the shop's own buttons respond while get_tree().paused is true,
	# exactly like LevelUpUI.
	process_mode = Node.PROCESS_MODE_ALWAYS

	shop_pool = shop_pool if shop_pool != null else load("res://Resources/ShopData/Data/StandardShopPool.tres")

	_root_panel = get_node_or_null(root_panel_path)
	_currency_label = get_node_or_null(currency_label_path)
	_wave_label = get_node_or_null(wave_label_path)
	_shelf = get_node_or_null(shelf_path)
	_reroll_button = get_node_or_null(reroll_button_path)
	_reroll_cost_label = get_node_or_null(reroll_cost_label_path)
	_next_wave_button = get_node_or_null(next_wave_button_path)
	_weapon_tray = get_node_or_null(weapon_tray_path)
	_relic_tray = get_node_or_null(relic_tray_path)
	_stats_list = get_node_or_null(stats_list_path)
	_empty_relics_label = get_node_or_null(empty_relics_label_path)

	_build_shelf()

	if _reroll_button != null:
		_reroll_button.pressed.connect(_on_reroll_pressed)
		UIAnim.juice_button(_reroll_button)
	if _next_wave_button != null:
		_next_wave_button.pressed.connect(_on_next_wave_pressed)
		UIAnim.juice_button(_next_wave_button)

	if _root_panel != null:
		_root_panel.visible = false

	EventBus.wave_end.connect(_on_wave_end)
	EventBus.currency_changed.connect(_on_currency_changed)

func _build_shelf() -> void:
	if _shelf == null:
		push_error("[ShopUI] No shelf wired; nothing can be sold.")
		return

	for i in range(offer_count):
		var card := ShopCard.new()
		card.name = "Card%d" % i
		_shelf.add_child(card)
		_cards.append(card)

		var index := i
		card.buy_requested.connect(func(): _on_buy(index))

# ------------------------------------------------------------------- lifecycle

func _on_wave_end(wave_number: int) -> void:
	_open_shop(wave_number)

func _open_shop(wave_number: int) -> void:
	_open = true
	_rerolls_this_visit = 0

	for card in _cards:
		card.set_locked(false)

	if _wave_label != null:
		_wave_label.text = "WAVE %d CLEARED" % wave_number

	_roll_offers(true)
	_refresh_trays()
	_refresh_stats()
	_refresh_reroll_cost()
	_on_currency_changed(GameManager.currency if GameManager != null else 0)

	if _root_panel != null:
		_root_panel.visible = true
		_root_panel.modulate.a = 0.0
		var tween := _root_panel.create_tween()
		tween.tween_property(_root_panel, "modulate:a", 1.0, 0.22)

	_deal_cards()
	get_tree().paused = true
	_focus_default_control()

# Opens on the leftmost card the player can actually buy, so the keyboard
# lands somewhere useful. Falls through to NEXT WAVE when nothing is
# affordable — focusing a disabled button would leave the screen unnavigable.
func _focus_default_control() -> void:
	for card in _cards:
		if card.offer != null and card.buy_button != null:
			UIAnim.grab_focus_safe(card.buy_button)
			if card.buy_button.has_focus():
				return

	UIAnim.grab_focus_safe(_next_wave_button)

func _on_next_wave_pressed() -> void:
	if not _open:
		return

	_open = false
	AudioManager.play_sfx("ui_click")

	if _root_panel != null:
		_root_panel.visible = false

	UIAnim.release_focus(get_tree())
	get_tree().paused = false
	WaveManager.start_next_wave()

# Offers pop in left to right, on open and on every reroll, so new stock reads
# as new stock rather than as a text swap.
func _deal_cards() -> void:
	if _shelf != null:
		UIAnim.cascade(_shelf, 0.06, true)

# --------------------------------------------------------------------- rolling

func _on_reroll_pressed() -> void:
	var cost := ShopEconomy.get_reroll_cost(_rerolls_this_visit)
	if not GameManager.try_spend_currency(cost):
		return

	AudioManager.play_sfx("ui_click")
	_rerolls_this_visit += 1
	_roll_offers(false)
	_deal_cards()
	_refresh_reroll_cost()
	_update_affordability()

# Fills every unlocked card. Weapons and relics come from one draw so a shelf
# can legitimately be all weapons or all relics — a fixed 3-and-2 split made
# every visit feel identical.
func _roll_offers(fresh: bool) -> void:
	var weapons: Array = []
	var relics: Array = []

	if shop_pool != null:
		weapons = shop_pool.weapon_pool.duplicate()
		for candidate in shop_pool.passive_pool:
			if candidate != null and not GameManager.is_passive_item_owned(candidate.id):
				relics.append(candidate)

	# A locked card keeps its offer, and its offer must not be drawn again for
	# a neighbour.
	for card in _cards:
		if card.locked and card.offer != null:
			if card.is_weapon:
				weapons.erase(card.offer)
			else:
				relics.erase(card.offer)

	for card in _cards:
		if card.locked and card.offer != null and not fresh:
			continue

		var pick_weapon := _should_pick_weapon(weapons, relics)
		if pick_weapon and not weapons.is_empty():
			var weapon = weapons[randi_range(0, weapons.size() - 1)]
			weapons.erase(weapon)
			card.show_weapon(weapon, ShopEconomy.get_weapon_price(weapon))
		elif not relics.is_empty():
			var relic = relics[randi_range(0, relics.size() - 1)]
			relics.erase(relic)
			card.show_relic(relic, ShopEconomy.get_passive_price(relic))
		else:
			card.clear()

	_update_affordability()

# Roughly 60/40 in favour of weapons, but never offers a kind that has run out.
func _should_pick_weapon(weapons: Array, relics: Array) -> bool:
	if weapons.is_empty():
		return false
	if relics.is_empty():
		return true
	return randf() < 0.6

# ------------------------------------------------------------------- purchases

func _on_buy(card_index: int) -> void:
	if card_index >= _cards.size():
		return

	var card := _cards[card_index]
	if card.offer == null:
		return

	if card.is_weapon:
		_buy_weapon(card)
	else:
		_buy_relic(card)

func _buy_weapon(card: ShopCard) -> void:
	var data: WeaponData = card.offer
	if WeaponInventory.instance == null or not WeaponInventory.instance.has_free_slot:
		UIAnim.shake(card)
		return

	if not GameManager.try_spend_currency(ShopEconomy.get_weapon_price(data)):
		UIAnim.shake(card)
		return

	WeaponInventory.instance.try_add_weapon(data)
	AudioManager.play_sfx("ui_purchase")
	UIAnim.punch(card)
	card.clear()
	_refresh_trays()
	_refresh_stats()
	_update_affordability()

func _buy_relic(card: ShopCard) -> void:
	var data: PassiveItemData = card.offer
	if not GameManager.try_spend_currency(ShopEconomy.get_passive_price(data)):
		UIAnim.shake(card)
		return

	AudioManager.play_sfx("ui_purchase")
	UIAnim.punch(card)
	_apply_passive_effect(data)
	GameManager.register_passive_item(data)
	card.clear()
	_refresh_trays()
	_refresh_stats()
	_update_affordability()

func _sell_weapon(slot_index: int) -> void:
	var inventory := WeaponInventory.instance
	if inventory == null:
		return

	var equipped := inventory.equipped_weapons
	if slot_index >= equipped.size() or equipped.size() <= min_weapons_kept:
		return

	var data: WeaponData = equipped[slot_index].data
	var refund := ShopEconomy.get_weapon_sell_value(data)

	if inventory.remove_weapon_at(slot_index):
		AudioManager.play_sfx("ui_click")
		GameManager.add_currency(refund)
		_refresh_trays()
		_refresh_stats()
		_update_affordability()

# ---------------------------------------------------------------------- trays

# Rebuilt wholesale on every change. The trays hold at most six weapons and a
# couple of dozen relics, so diffing them would be more code than it saves.
func _refresh_trays() -> void:
	_refresh_weapon_tray()
	_refresh_relic_tray()

func _refresh_weapon_tray() -> void:
	if _weapon_tray == null:
		return

	for child in _weapon_tray.get_children():
		child.queue_free()

	var inventory := WeaponInventory.instance
	if inventory == null:
		return

	var equipped := inventory.equipped_weapons
	var can_sell := equipped.size() > min_weapons_kept

	for i in range(equipped.size()):
		var data: WeaponData = equipped[i].data
		if data == null:
			continue

		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 2)
		_weapon_tray.add_child(slot)

		var icon := TextureRect.new()
		icon.texture = data.icon
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.tooltip_text = "%s\n%d dmg" % [data.name, roundi(data.damage)]
		slot.add_child(icon)

		var sell := Button.new()
		sell.text = "%dg" % ShopEconomy.get_weapon_sell_value(data)
		sell.theme_type_variation = &"FlatButton"
		sell.disabled = not can_sell
		sell.tooltip_text = "Sell %s" % data.name
		slot.add_child(sell)

		var index := i
		sell.pressed.connect(func(): _sell_weapon(index))
		UIAnim.juice_button(sell)

	# Empty slots, so the player can see how much room is left. Sized to match a
	# filled slot (icon plus its sell button) or the flow row jumps height.
	for i in range(equipped.size(), inventory.max_weapon_slots):
		var blank := Panel.new()
		blank.theme_type_variation = &"InsetPanel"
		blank.custom_minimum_size = Vector2(48, 78)
		blank.modulate.a = 0.4
		_weapon_tray.add_child(blank)

func _refresh_relic_tray() -> void:
	if _relic_tray == null:
		return

	for child in _relic_tray.get_children():
		child.queue_free()

	var owned: Array[PassiveItemData] = GameManager.owned_passive_items if GameManager != null else []

	if _empty_relics_label != null:
		_empty_relics_label.visible = owned.is_empty()

	for item in owned:
		if item == null:
			continue

		var icon := TextureRect.new()
		icon.texture = item.icon
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.tooltip_text = "%s\n%s" % [item.display_name, item.stat_line()]
		_relic_tray.add_child(icon)

# ---------------------------------------------------------------------- stats

# The left column answers "what did all that shopping actually do", which is
# the question a between-wave screen exists to answer.
func _refresh_stats() -> void:
	if _stats_list == null:
		return

	for child in _stats_list.get_children():
		child.queue_free()

	var stats := PlayerStats.instance
	if stats == null:
		return

	var health := stats.get_node_or_null("../HealthComponent") as HealthComponent

	_add_stat("Damage", "%d%%" % roundi(stats.damage_multiplier * 100.0))
	_add_stat("Attack Speed", "%d%%" % roundi(stats.attack_speed_multiplier * 100.0))
	_add_stat("Move Speed", "%d%%" % roundi(stats.move_speed_multiplier * 100.0))

	if health != null:
		_add_stat("Health", "%d / %d" % [health.current_health, health.max_health])
		if health.armor > 0:
			_add_stat("Armour", str(health.armor))
		if health.dodge_chance > 0.0:
			_add_stat("Dodge", "%d%%" % roundi(health.dodge_chance * 100.0))

	if stats.extra_crit_chance > 0.0:
		_add_stat("Crit Chance", "+%d%%" % roundi(stats.extra_crit_chance * 100.0))
	if stats.extra_crit_multiplier > 0.0:
		_add_stat("Crit Damage", "+%.1fx" % stats.extra_crit_multiplier)
	if stats.lifesteal_fraction > 0.0:
		_add_stat("Lifesteal", "%d%%" % roundi(stats.lifesteal_fraction * 100.0))
	if stats.health_regen_per_second > 0.0:
		_add_stat("Regen", "%.1f/s" % stats.health_regen_per_second)
	if stats.currency_gain_multiplier > 1.0:
		_add_stat("Gold Gain", "%d%%" % roundi(stats.currency_gain_multiplier * 100.0))
	if stats.xp_gain_multiplier > 1.0:
		_add_stat("XP Gain", "%d%%" % roundi(stats.xp_gain_multiplier * 100.0))

func _add_stat(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	_stats_list.add_child(row)

	var name_label := Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.theme_type_variation = &"StatLabel"
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.theme_type_variation = &"GoldLabel"
	row.add_child(value_label)

# ----------------------------------------------------------------- affordability

func _refresh_reroll_cost() -> void:
	if _reroll_cost_label != null:
		_reroll_cost_label.text = "%dg" % ShopEconomy.get_reroll_cost(_rerolls_this_visit)

func _on_currency_changed(current_currency: int) -> void:
	if _currency_label != null:
		_currency_label.text = "%d" % current_currency

	_update_affordability()

# Greys out anything the player can no longer buy, so affordability is visible
# without adding up prices.
func _update_affordability() -> void:
	if GameManager == null:
		return

	var currency := GameManager.currency
	var slots_full: bool = WeaponInventory.instance != null and not WeaponInventory.instance.has_free_slot

	for card in _cards:
		if card.offer == null:
			continue

		if card.is_weapon:
			card.set_affordable(not slots_full and currency >= ShopEconomy.get_weapon_price(card.offer))
		else:
			card.set_affordable(currency >= ShopEconomy.get_passive_price(card.offer))

	if _reroll_button != null:
		_reroll_button.disabled = currency < ShopEconomy.get_reroll_cost(_rerolls_this_visit)

# --------------------------------------------------------------------- effects

static func _apply_passive_effect(item: PassiveItemData) -> void:
	var stats := PlayerStats.instance
	if stats == null:
		return

	match item.effect_type:
		PassiveItemData.PassiveEffectType.DAMAGE_BOOST:
			stats.apply_damage_upgrade(item.value)
		PassiveItemData.PassiveEffectType.MOVE_SPEED_BOOST:
			stats.apply_move_speed_upgrade(item.value)
		PassiveItemData.PassiveEffectType.MAX_HEALTH_BOOST:
			stats.apply_max_health_upgrade(roundi(item.value))
		PassiveItemData.PassiveEffectType.ATTACK_SPEED_BOOST:
			stats.apply_attack_speed_bonus(item.value)
		PassiveItemData.PassiveEffectType.CRIT_CHANCE_BOOST:
			stats.apply_extra_crit(item.value, 0.0)
		PassiveItemData.PassiveEffectType.CRIT_DAMAGE_BOOST:
			stats.apply_extra_crit(0.0, item.value)
		PassiveItemData.PassiveEffectType.LIFESTEAL_BOOST:
			stats.apply_lifesteal(item.value)
		PassiveItemData.PassiveEffectType.ARMOR_BOOST:
			stats.apply_armor(roundi(item.value))
		PassiveItemData.PassiveEffectType.DODGE_BOOST:
			stats.apply_dodge(item.value)
		PassiveItemData.PassiveEffectType.HEALTH_REGEN_BOOST:
			stats.apply_health_regen(item.value)
		PassiveItemData.PassiveEffectType.PICKUP_RANGE_BOOST:
			stats.apply_pickup_radius(item.value)
		PassiveItemData.PassiveEffectType.UNDEAD_DAMAGE_BOOST:
			stats.apply_undead_damage_bonus(item.value)
		PassiveItemData.PassiveEffectType.MAGIC_DAMAGE_BOOST:
			stats.apply_magic_damage_bonus(item.value)
		PassiveItemData.PassiveEffectType.XP_GAIN_BOOST:
			stats.apply_xp_gain_bonus(item.value)
		PassiveItemData.PassiveEffectType.CURRENCY_GAIN_BOOST:
			stats.apply_currency_gain_bonus(item.value)
		_:
			push_warning("[ShopUI] Relic '%s' has no effect wired for type %d." % [item.id, item.effect_type])
