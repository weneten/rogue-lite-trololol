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

# The grid the next _add_stat call writes into; swapped out by _begin_section.
var _stat_grid: GridContainer

var _cards: Array[ShopCard] = []
var _rerolls_this_visit: int = 0
var _open: bool = false
var _pending_wave: int = 0
var _waiting_for_peers: bool = false
# When true this instance is a split-screen copy of another hunter's shop.
var is_replica: bool = false

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

	if is_replica:
		if _reroll_button != null:
			_reroll_button.disabled = true
		if _next_wave_button != null:
			_next_wave_button.disabled = true
		return

	EventBus.wave_end.connect(_on_wave_end)
	EventBus.intermission_boons_done.connect(_on_boons_done)
	EventBus.currency_changed.connect(_on_currency_changed)
	if NetSession != null:
		NetSession.all_hunters_ready.connect(_on_all_hunters_ready)
		NetSession.ready_counts.connect(_on_ready_counts)

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
	_pending_wave = wave_number
	_waiting_for_peers = false
	get_tree().paused = true
	# Brotato: moon boons first (every queued level from the wave), then the shop.
	if PlayerStats.instance != null and PlayerStats.instance.pop_next_boon():
		return
	_open_shop(wave_number)

func _on_boons_done() -> void:
	if _pending_wave <= 0:
		return
	_open_shop(_pending_wave)

func _open_shop(wave_number: int) -> void:
	_open = true
	_rerolls_this_visit = 0

	for card in _cards:
		card.set_locked(false)

	if _next_wave_button != null:
		_next_wave_button.disabled = false
		_next_wave_button.text = "NEXT WAVE"

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
	if NetSession != null:
		NetSession.broadcast_intermission("shop", snapshot_state())

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

	AudioManager.play_sfx("ui_click")

	if NetSession != null and NetSession.is_active:
		_waiting_for_peers = true
		if _next_wave_button != null:
			_next_wave_button.disabled = true
			_next_wave_button.text = "WAITING…"
		NetSession.mark_ready()
		return

	_close_and_resume()

func _close_and_resume() -> void:
	_open = false
	_waiting_for_peers = false
	_pending_wave = 0
	if _next_wave_button != null:
		_next_wave_button.disabled = false
		_next_wave_button.text = "NEXT WAVE"
	if _root_panel != null:
		_root_panel.visible = false
	UIAnim.release_focus(get_tree())
	get_tree().paused = false
	var hunter := get_tree().get_first_node_in_group("Player") as Player
	if hunter != null:
		hunter.restore_after_intermission()
	if NetSession == null or not NetSession.is_client():
		WaveManager.start_next_wave()

func _on_all_hunters_ready() -> void:
	if not _waiting_for_peers and not _open:
		return
	_close_and_resume()

func _on_ready_counts(ready_n: int, total_n: int) -> void:
	if not _waiting_for_peers or _next_wave_button == null:
		return
	_next_wave_button.text = "WAITING %d/%d" % [ready_n, total_n]

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
	_push_net()

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
			var weapon = _draw_by_rarity(weapons)
			weapons.erase(weapon)
			card.show_weapon(weapon, ShopEconomy.get_weapon_price(weapon))
		elif not relics.is_empty():
			var relic = _draw_by_rarity(relics)
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

# Weighted draw from a pool of offers (weapons or relics alike — both carry a
# rarity_tier). Commons are the baseline; every point of Luck makes each step up
# the rarity ladder that much less punishing, which is the entire point of the
# stat. A run with no Luck still sees Legendaries, just rarely.
func _draw_by_rarity(pool: Array):
	if pool.size() <= 1:
		return pool[0] if not pool.is_empty() else null

	var luck: float = PlayerStats.instance.luck if PlayerStats.instance != null else 0.0
	# Each tier is ~2.2x rarer than the one below it at zero Luck; Luck shrinks
	# that falloff, and is capped so a hoarder never gets a shelf of guaranteed
	# Legendaries.
	var falloff := 2.2 - clampf(luck * 0.08, 0.0, 1.1)

	var weights: Array[float] = []
	var total := 0.0
	for entry in pool:
		var tier: int = clampi(entry.rarity_tier, 0, 4)
		var weight: float = pow(falloff, -float(tier))
		weights.append(weight)
		total += weight

	var roll := randf() * total
	for i in range(pool.size()):
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]

	return pool[pool.size() - 1]

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
	_push_net()

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
	_push_net()

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
		_push_net()

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
		icon.custom_minimum_size = Vector2(40, 40)
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
		blank.custom_minimum_size = Vector2(40, 50)
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
		icon.custom_minimum_size = Vector2(30, 30)
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
	_stat_grid = null

	var stats := PlayerStats.instance
	if stats == null:
		return

	var health := stats.get_node_or_null("../HealthComponent") as HealthComponent

	# The core block is unconditional, even at its starting value. A stat that
	# only appears once you own a relic for it is a stat you cannot plan a
	# purchase around — you have to already own the thing to learn it exists.
	# Conditional rows are only for the genuinely exotic, which would otherwise
	# be a column of "0%" crowding out what matters.
	_begin_section("OFFENCE")
	_add_stat("Damage", "%d%%" % roundi(stats.damage_multiplier * 100.0))
	_add_stat("Atk Speed", "%d%%" % roundi(stats.attack_speed_multiplier * 100.0))
	_add_stat("Crit", "+%d%%" % roundi(stats.extra_crit_chance * 100.0))
	if stats.extra_crit_multiplier > 0.0:
		_add_stat("Crit Dmg", "+%.1fx" % stats.extra_crit_multiplier)
	if stats.magic_damage_multiplier != 1.0:
		_add_stat("Magic", "%d%%" % roundi(stats.magic_damage_multiplier * 100.0))
	if stats.undead_damage_multiplier != 1.0:
		_add_stat("vs Undead", "%d%%" % roundi(stats.undead_damage_multiplier * 100.0))

	_begin_section("SURVIVAL")
	if health != null:
		_add_stat("Health", "%d/%d" % [health.current_health, health.max_health])
		_add_stat("Armour", str(health.armor))
		_add_stat("Dodge", "%d%%" % roundi(health.dodge_chance * 100.0))
	_add_stat("Regen", "%.1f/s" % stats.health_regen_per_second)
	_add_stat("Lifesteal", "%d%%" % roundi(stats.lifesteal_fraction * 100.0))
	if stats.damage_taken_multiplier != 1.0:
		_add_stat("Dmg Taken", "%d%%" % roundi(stats.damage_taken_multiplier * 100.0))

	_begin_section("UTILITY")
	_add_stat("Speed", "%d%%" % roundi(stats.move_speed_multiplier * 100.0))
	_add_stat("Luck", "%d" % roundi(stats.luck))
	_add_stat("Gold", "%d%%" % roundi(stats.currency_gain_multiplier * 100.0))
	_add_stat("XP", "%d%%" % roundi(stats.xp_gain_multiplier * 100.0))
	if stats.pickup_radius_bonus > 0.0:
		_add_stat("Pickup", "+%d" % roundi(stats.pickup_radius_bonus))
	if stats.enemy_density_multiplier != 1.0:
		_add_stat("Horde", "%d%%" % roundi(stats.enemy_density_multiplier * 100.0))

	var inventory := WeaponInventory.instance
	if inventory != null:
		_add_stat("Slots", "%d/%d" % [inventory.equipped_weapons.size(), inventory.max_weapon_slots])

# Stats are laid out two to a row. One column of twenty rows does not fit the
# panel, and a panel you have to scroll to see your own build in is a panel that
# does not answer the question it exists to answer.
func _begin_section(title: String) -> void:
	if _stats_list.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 4)
		_stats_list.add_child(spacer)

	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"StatLabel"
	heading.modulate = Color(1.0, 0.82, 0.45, 0.75)
	_stats_list.add_child(heading)

	_stat_grid = GridContainer.new()
	_stat_grid.columns = 2
	_stat_grid.add_theme_constant_override("h_separation", 12)
	_stat_grid.add_theme_constant_override("v_separation", 0)
	_stats_list.add_child(_stat_grid)

func _add_stat(label: String, value: String) -> void:
	if _stat_grid == null:
		_begin_section("HUNTER")

	var cell := HBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_grid.add_child(cell)

	var name_label := Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.theme_type_variation = &"StatLabel"
	cell.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.theme_type_variation = &"GoldLabel"
	cell.add_child(value_label)

# ----------------------------------------------------------------- affordability

func _refresh_reroll_cost() -> void:
	if _reroll_cost_label != null:
		_reroll_cost_label.text = "%dg" % ShopEconomy.get_reroll_cost(_rerolls_this_visit)

func apply_net_state(st: Dictionary) -> void:
	var phase := str(st.get("phase", "shop"))
	if _root_panel != null:
		_root_panel.visible = phase != "boon"
	if _currency_label != null:
		_currency_label.text = str(int(st.get("gold", 0)))
	if _wave_label != null:
		_wave_label.text = str(st.get("char", ""))
	var offers: Variant = st.get("offers", [])
	if typeof(offers) == TYPE_ARRAY:
		for i in range(_cards.size()):
			if i < offers.size() and typeof(offers[i]) == TYPE_DICTIONARY:
				_cards[i].apply_net(offers[i])
			else:
				_cards[i].clear()
	if _next_wave_button != null:
		_next_wave_button.disabled = true
		_next_wave_button.text = "READY" if phase == "ready" else "NEXT WAVE"
	_apply_net_trays(st)

func _apply_net_trays(st: Dictionary) -> void:
	if _weapon_tray != null:
		for child in _weapon_tray.get_children():
			child.queue_free()
		var names: Variant = st.get("weapons", [])
		if typeof(names) == TYPE_ARRAY:
			for raw in names:
				var lab := Label.new()
				lab.text = str(raw)
				lab.theme_type_variation = &"StatLabel"
				_weapon_tray.add_child(lab)
	if _relic_tray != null:
		for child in _relic_tray.get_children():
			child.queue_free()
		var relics: Variant = st.get("relics", [])
		if typeof(relics) == TYPE_ARRAY:
			for row in relics:
				if typeof(row) != TYPE_DICTIONARY:
					continue
				var icon := TextureRect.new()
				icon.custom_minimum_size = Vector2(30, 30)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				var ipath := str(row.get("i", ""))
				if not ipath.is_empty() and ResourceLoader.exists(ipath):
					icon.texture = load(ipath)
				icon.tooltip_text = str(row.get("n", ""))
				_relic_tray.add_child(icon)
	if _empty_relics_label != null:
		var relics2: Variant = st.get("relics", [])
		_empty_relics_label.visible = typeof(relics2) != TYPE_ARRAY or relics2.is_empty()

func snapshot_state() -> Dictionary:
	var offers: Array = []
	for card in _cards:
		offers.append(card.to_net() if card != null else {"sold": true})
	var relics: Array = []
	if GameManager != null:
		for item in GameManager.owned_passive_items:
			if item != null:
				var path := item.icon.resource_path if item.icon != null else ""
				relics.append({"n": item.display_name, "i": path})
	return {"offers": offers, "relics": relics}

func _push_net() -> void:
	if _open and NetSession != null and NetSession.is_active:
		NetSession.broadcast_intermission("shop", snapshot_state())

func _on_currency_changed(current_currency: int) -> void:
	if _currency_label != null:
		_currency_label.text = "%d" % current_currency

	_update_affordability()
	if _open and NetSession != null and NetSession.is_active:
		NetSession.broadcast_intermission("shop", snapshot_state())

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
			var price := ShopEconomy.get_weapon_price(card.offer)
			if slots_full:
				card.set_slots_full()
			else:
				card.set_affordable(currency >= price, price)
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
		PassiveItemData.PassiveEffectType.LUCK_BOOST:
			stats.apply_luck(item.value)
		PassiveItemData.PassiveEffectType.ENEMY_DENSITY_BOOST:
			stats.apply_enemy_density(item.value)
		PassiveItemData.PassiveEffectType.DAMAGE_TAKEN_REDUCTION:
			stats.apply_damage_taken_reduction(item.value)
		_:
			push_warning("[ShopUI] Relic '%s' has no effect wired for type %d." % [item.id, item.effect_type])


# Split-screen: keep native font size and reflow the chrome so the shop
# fills the pane instead of shrinking the whole 1280×720 layout.
func apply_pane_layout(pane: Vector2) -> void:
	if _root_panel == null:
		return
	var content := _root_panel.get_node_or_null("Content") as MarginContainer
	var rows := _root_panel.get_node_or_null("Content/Rows") as VBoxContainer
	var body := _root_panel.get_node_or_null("Content/Rows/Body") as HBoxContainer
	var left := _root_panel.get_node_or_null("Content/Rows/Body/LeftColumn") as Control
	var stats := _root_panel.get_node_or_null("Content/Rows/Body/LeftColumn/StatsPanel") as Control
	var right := _root_panel.get_node_or_null("Content/Rows/Body/RightColumn") as VBoxContainer
	var solo := pane.x >= 1180.0 and pane.y >= 680.0
	if solo or pane.x < 8.0 or pane.y < 8.0:
		if content != null:
			content.add_theme_constant_override("margin_left", 40)
			content.add_theme_constant_override("margin_top", 26)
			content.add_theme_constant_override("margin_right", 40)
			content.add_theme_constant_override("margin_bottom", 26)
		if rows != null:
			rows.add_theme_constant_override("separation", 12)
		if body != null:
			body.add_theme_constant_override("separation", 20)
		if left != null:
			left.visible = true
			left.custom_minimum_size = Vector2(330, 0)
		if stats != null:
			stats.visible = true
		if right != null:
			right.add_theme_constant_override("separation", 14)
		if _shelf != null:
			_shelf.add_theme_constant_override("separation", 14)
		for card in _cards:
			if card != null:
				card.apply_pane_size(Vector2.ZERO)
		return

	var tight: bool = pane.y < 560.0
	var narrow: bool = pane.x < 920.0
	var m: int = 8 if (tight or narrow) else 18
	if content != null:
		content.add_theme_constant_override("margin_left", m)
		content.add_theme_constant_override("margin_top", m)
		content.add_theme_constant_override("margin_right", m)
		content.add_theme_constant_override("margin_bottom", m)
	if rows != null:
		rows.add_theme_constant_override("separation", 6 if tight else 10)
	if body != null:
		body.add_theme_constant_override("separation", 8 if narrow else 12)
	if stats != null:
		stats.visible = not tight and not narrow
	var left_w := 330.0
	if narrow:
		left_w = 132.0
	elif tight:
		left_w = 210.0
	if left != null:
		left.visible = true
		left.custom_minimum_size = Vector2(left_w, 0)
	if right != null:
		right.add_theme_constant_override("separation", 6 if tight else 10)
	if _shelf != null:
		_shelf.add_theme_constant_override("separation", 8 if narrow else 10)

	var center := _shelf.get_parent() as Control if _shelf != null else null
	var area := Vector2.ZERO
	if center != null:
		area = center.size
	if area.x < 16.0 or area.y < 16.0:
		area = Vector2(
			maxf(120.0, pane.x - float(m) * 2.0 - left_w - 12.0),
			maxf(140.0, pane.y - float(m) * 2.0 - 120.0)
		)
	var n: int = maxi(1, _cards.size())
	var sep: float = 8.0 if narrow else 10.0
	var card := Vector2(
		clampf((area.x - sep * float(n - 1)) / float(n), 110.0, 220.0),
		clampf(area.y, 148.0, 268.0)
	)
	for c in _cards:
		if c != null:
			c.apply_pane_size(card)
