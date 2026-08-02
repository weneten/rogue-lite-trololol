extends CanvasLayer
class_name ShopUI

# Shop phase screen: opens on EventBus.OnWaveEnd (pausing the run, like LevelUpUI does for
# level-ups), offers a rolled selection of weapons/passives to buy, lists currently equipped
# weapons for sale, and lets the player reroll the offers before confirming "Next Wave" to
# unpause and hand control back to WaveManager. All pricing/reroll-cost math is delegated to
# the static ShopEconomy so none of it is a magic number here.

@export var shop_pool: ShopPoolData
@export var weapon_offer_count: int = 3
@export var passive_offer_count: int = 2

@export_group("Wiring")
@export var root_panel_path: NodePath
@export var currency_label_path: NodePath
@export var reroll_button_path: NodePath
@export var reroll_cost_label_path: NodePath
@export var next_wave_button_path: NodePath

@export_group("Weapon Offers")
@export var weapon_button_paths: Array[NodePath] = []
@export var weapon_name_paths: Array[NodePath] = []
@export var weapon_desc_paths: Array[NodePath] = []

@export_group("Passive Offers")
@export var passive_button_paths: Array[NodePath] = []
@export var passive_name_paths: Array[NodePath] = []
@export var passive_desc_paths: Array[NodePath] = []

@export_group("Equipped Weapons (Sell)")
@export var equipped_row_paths: Array[NodePath] = []
@export var equipped_name_paths: Array[NodePath] = []
@export var equipped_sell_button_paths: Array[NodePath] = []

# Selling the last weapon would leave the player unable to fight; block it.
@export var min_weapons_kept: int = 1

@export_group("Presentation")
@export var card_container_paths: Array[NodePath] = []

var _root_panel: Control
var _currency_label: Label
var _reroll_button: Button
var _reroll_cost_label: Label
var _next_wave_button: Button

var _weapon_buttons: Array[Button] = []
var _weapon_names: Array[Label] = []
var _weapon_descs: Array[Label] = []
var _weapon_offers: Array = []

var _passive_buttons: Array[Button] = []
var _passive_names: Array[Label] = []
var _passive_descs: Array[Label] = []
var _passive_offers: Array = []

var _equipped_rows: Array[Control] = []
var _equipped_names: Array[Label] = []
var _equipped_sell_buttons: Array[Button] = []

var _rerolls_this_visit: int
var _card_containers: Array[Control] = []
var _last_currency: int = 0

func _ready() -> void:
	# Lets the shop's own buttons respond while GetTree().Paused is true, exactly like LevelUpUI.
	process_mode = Node.PROCESS_MODE_ALWAYS

	shop_pool = shop_pool if shop_pool != null else load("res://Resources/ShopData/Data/StandardShopPool.tres")

	_root_panel = get_node_or_null(root_panel_path)
	_currency_label = get_node_or_null(currency_label_path)
	_reroll_button = get_node_or_null(reroll_button_path)
	_reroll_cost_label = get_node_or_null(reroll_cost_label_path)
	_next_wave_button = get_node_or_null(next_wave_button_path)

	_resolve_offer_row(weapon_button_paths, weapon_name_paths, weapon_desc_paths, _weapon_buttons, _weapon_names, _weapon_descs, _on_buy_weapon)
	_resolve_offer_row(passive_button_paths, passive_name_paths, passive_desc_paths, _passive_buttons, _passive_names, _passive_descs, _on_buy_passive)

	for i in range(equipped_row_paths.size()):
		_equipped_rows.append(get_node_or_null(equipped_row_paths[i]))
		_equipped_names.append(_get_or_null_at(equipped_name_paths, i))
		var sell_button = _get_or_null_at(equipped_sell_button_paths, i)
		_equipped_sell_buttons.append(sell_button)

		var slot_index = i
		if sell_button != null:
			sell_button.pressed.connect(func(): _sell_equipped_weapon(slot_index))

	for path in card_container_paths:
		var container = get_node_or_null(path) as Control
		if container != null:
			_card_containers.append(container)

	if _reroll_button != null:
		_reroll_button.pressed.connect(_on_reroll_pressed)
	if _next_wave_button != null:
		_next_wave_button.pressed.connect(_on_next_wave_pressed)

	var juiced: Array = []
	juiced.append_array(_weapon_buttons)
	juiced.append_array(_passive_buttons)
	juiced.append_array(_equipped_sell_buttons)
	juiced.append(_reroll_button)
	juiced.append(_next_wave_button)
	for button in juiced:
		if button != null:
			UIAnim.juice_button(button)
	if _root_panel != null:
		_root_panel.visible = false

	EventBus.wave_end.connect(_on_wave_end)
	EventBus.currency_changed.connect(_on_currency_changed)

# Resolves a row of offer-slot NodePaths (button/name/desc) and wires each button's
# Pressed signal to on_buy(slot_index). Used for both the weapon and passive offer rows.
func _resolve_offer_row(button_paths: Array[NodePath], name_paths: Array[NodePath], desc_paths: Array[NodePath], buttons: Array, names: Array, descs: Array, on_buy: Callable) -> void:
	for i in range(button_paths.size()):
		var button = get_node_or_null(button_paths[i])
		buttons.append(button)
		names.append(_get_or_null_at(name_paths, i))
		descs.append(_get_or_null_at(desc_paths, i))

		var offer_index = i
		if button != null:
			button.pressed.connect(func(): on_buy.call(offer_index))

func _on_wave_end(wave_number: int) -> void:
	_open_shop()

func _open_shop() -> void:
	_rerolls_this_visit = 0
	_roll_offers()
	_refresh_equipped_row()
	_refresh_reroll_cost()
	_update_affordability()

	if _root_panel != null:
		_root_panel.visible = true
		_root_panel.modulate.a = 0.0
		var tween = _root_panel.create_tween()
		tween.tween_property(_root_panel, "modulate:a", 1.0, 0.2)

	_deal_cards()
	get_tree().paused = true
	_focus_default_control()

func _focus_default_control() -> void:
	for button in _weapon_buttons:
		if button != null and button.visible and not button.disabled:
			UIAnim.grab_focus_safe(button)
			return
	for button in _passive_buttons:
		if button != null and button.visible and not button.disabled:
			UIAnim.grab_focus_safe(button)
			return
	UIAnim.grab_focus_safe(_next_wave_button)

# Offers pop in left to right, both on open and on every reroll, so a reroll
# feels like new stock rather than a text swap.
func _deal_cards() -> void:
	for container in _card_containers:
		if is_instance_valid(container):
			UIAnim.cascade(container, 0.07, true)

func _on_reroll_pressed() -> void:
	var cost = ShopEconomy.get_reroll_cost(_rerolls_this_visit)
	if not GameManager.try_spend_currency(cost):
		return

	AudioManager.play_sfx("ui_click")
	_rerolls_this_visit += 1
	_roll_offers()
	_deal_cards()
	_refresh_reroll_cost()
	_update_affordability()

func _on_next_wave_pressed() -> void:
	AudioManager.play_sfx("ui_click")
	if _root_panel != null:
		_root_panel.visible = false

	UIAnim.release_focus(get_tree())
	get_tree().paused = false
	WaveManager.start_next_wave()

# Weighted, non-repeating draw of WeaponOfferCount/PassiveOfferCount items, mirroring
# LevelUpUI's roll — passives already owned this run are excluded so they never re-appear.
func _roll_offers() -> void:
	_weapon_offers.clear()
	var weapon_pool = [] if not shop_pool else shop_pool.weapon_pool.duplicate()
	var weapon_draw_count = mini(weapon_offer_count, weapon_pool.size())
	for i in range(weapon_draw_count):
		var picked = weapon_pool[randi_range(0, weapon_pool.size() - 1)]
		_weapon_offers.append(picked)
		weapon_pool.erase(picked)

	_passive_offers.clear()
	var passive_pool = []
	var passive_pool_data = [] if not shop_pool else shop_pool.passive_pool
	for candidate in passive_pool_data:
		if candidate != null and not GameManager.is_passive_item_owned(candidate.id):
			passive_pool.append(candidate)

	var passive_draw_count = mini(passive_offer_count, passive_pool.size())
	for i in range(passive_draw_count):
		var picked = passive_pool[randi_range(0, passive_pool.size() - 1)]
		_passive_offers.append(picked)
		passive_pool.erase(picked)

	_refresh_offer_row(_weapon_buttons, _weapon_names, _weapon_descs, _weapon_offers,
		func(w): return w.name,
		func(w): return "%d dmg | %dg" % [roundi(w.damage), ShopEconomy.get_weapon_price(w)])
	_refresh_offer_row(_passive_buttons, _passive_names, _passive_descs, _passive_offers,
		func(p): return p.display_name,
		func(p): return "%s\n%dg" % [p.description, ShopEconomy.get_passive_price(p)])

	# Show the weapon's own icon, so an offer looks like the thing you'll carry.
	for i in range(_weapon_buttons.size()):
		var offer = _weapon_offers[i] if i < _weapon_offers.size() else null
		_set_card_icon(_weapon_buttons[i], offer.icon if offer != null else null)

# The Icon TextureRect is a sibling of the Buy button inside each card's VBox.
static func _set_card_icon(button: Button, texture: Texture2D) -> void:
	if button == null or texture == null:
		return

	var icon_rect = button.get_parent().get_node_or_null("Icon") as TextureRect
	if icon_rect != null:
		icon_rect.texture = texture

static func _refresh_offer_row(buttons: Array, names: Array, descs: Array, offers: Array, name_fn: Callable, desc_fn: Callable) -> void:
	for i in range(buttons.size()):
		var has_offer = i < offers.size()
		if buttons[i] != null:
			buttons[i].visible = has_offer

		if not has_offer:
			continue

		var offer = offers[i]
		if names[i] != null:
			names[i].text = name_fn.call(offer)
		if descs[i] != null:
			descs[i].text = desc_fn.call(offer)

func _refresh_equipped_row() -> void:
	var equipped = [] if not WeaponInventory.instance else WeaponInventory.instance.equipped_weapons

	for i in range(_equipped_rows.size()):
		var has_weapon = i < equipped.size()
		if _equipped_rows[i] != null:
			_equipped_rows[i].visible = has_weapon

		if not has_weapon:
			continue

		var data = equipped[i].data
		if _equipped_names[i] != null:
			_equipped_names[i].text = "%s (sell %dg)" % [data.name if data else "", ShopEconomy.get_weapon_sell_value(data)]

		if _equipped_sell_buttons[i] != null:
			_equipped_sell_buttons[i].disabled = equipped.size() <= min_weapons_kept

func _refresh_reroll_cost() -> void:
	if _reroll_cost_label != null:
		_reroll_cost_label.text = "%dg" % ShopEconomy.get_reroll_cost(_rerolls_this_visit)

func _on_buy_weapon(offer_index: int) -> void:
	if offer_index >= _weapon_offers.size() or not WeaponInventory.instance:
		return

	var data = _weapon_offers[offer_index]
	var price = ShopEconomy.get_weapon_price(data)

	if not WeaponInventory.instance.has_free_slot or not GameManager.try_spend_currency(price):
		return

	WeaponInventory.instance.try_add_weapon(data)
	AudioManager.play_sfx("ui_purchase")
	_refresh_equipped_row()
	_update_affordability()

func _on_buy_passive(offer_index: int) -> void:
	if offer_index >= _passive_offers.size():
		return

	var data = _passive_offers[offer_index]
	var price = ShopEconomy.get_passive_price(data)

	if not GameManager.try_spend_currency(price):
		return

	AudioManager.play_sfx("ui_purchase")
	_apply_passive_effect(data)
	GameManager.register_passive_item_owned(data.id)

	# Removing the bought offer shifts the remaining ones down; re-running RefreshOfferRow
	# reflows every slot's label/visibility off the shortened list (last slot ends up hidden).
	_passive_offers.remove_at(offer_index)
	_refresh_offer_row(_passive_buttons, _passive_names, _passive_descs, _passive_offers,
		func(p): return p.display_name,
		func(p): return "%s\n%dg" % [p.description, ShopEconomy.get_passive_price(p)])
	_update_affordability()

func _sell_equipped_weapon(slot_index: int) -> void:
	var equipped = WeaponInventory.instance.equipped_weapons if WeaponInventory.instance else null
	if equipped == null or slot_index >= equipped.size() or equipped.size() <= min_weapons_kept:
		return

	var data = equipped[slot_index].data
	var sell_value = ShopEconomy.get_weapon_sell_value(data)

	if WeaponInventory.instance.remove_weapon_at(slot_index):
		AudioManager.play_sfx("ui_click")
		GameManager.add_currency(sell_value)
		_refresh_equipped_row()
		_update_affordability()

static func _apply_passive_effect(item) -> void:
	var stats = PlayerStats.instance
	if stats == null:
		return

	match item.effect_type:
		PassiveItemData.PassiveEffectType.DAMAGE_BOOST:
			stats.apply_damage_upgrade(item.value)
		PassiveItemData.PassiveEffectType.MOVE_SPEED_BOOST:
			stats.apply_move_speed_upgrade(item.value)
		PassiveItemData.PassiveEffectType.MAX_HEALTH_BOOST:
			stats.apply_max_health_upgrade(roundi(item.value))

func _on_currency_changed(current_currency: int) -> void:
	if _currency_label != null:
		_currency_label.text = "%dg" % current_currency

	_update_affordability()

# Greys out any buy/reroll button the player can no longer afford (or, for weapons, if slots are full).
func _update_affordability() -> void:
	if not GameManager:
		return

	var currency = GameManager.currency
	var weapon_slots_full = WeaponInventory.instance and not WeaponInventory.instance.has_free_slot

	for i in range(_weapon_buttons.size()):
		if _weapon_buttons[i] == null or i >= _weapon_offers.size():
			continue

		_weapon_buttons[i].disabled = weapon_slots_full or currency < ShopEconomy.get_weapon_price(_weapon_offers[i])

	for i in range(_passive_buttons.size()):
		if _passive_buttons[i] == null or i >= _passive_offers.size():
			continue

		_passive_buttons[i].disabled = currency < ShopEconomy.get_passive_price(_passive_offers[i])

	if _reroll_button != null:
		_reroll_button.disabled = currency < ShopEconomy.get_reroll_cost(_rerolls_this_visit)

# Helper to get node or null at array index
func _get_or_null_at(arr: Array, index: int):
	if index < arr.size():
		return get_node_or_null(arr[index])
	return null
