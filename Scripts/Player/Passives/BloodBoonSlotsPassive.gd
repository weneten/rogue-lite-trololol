extends PassiveAbility
class_name BloodBoonSlotsPassive

# The Jester — "The Bleeding Wheel".
#
# Instead of a passive that ticks on its own, the Jester carries a one-armed bandit in the
# corner of the screen. Spins cost Blood Boons (the Jester's private currency, starting at
# BloodBoonEconomy.STARTING_COINS), the wheel always lands three of a kind, and what it
# lands ranges from executing the map's biggest enemy to turning 666 on the Jester himself.
#
# This node owns the currency and resolves the outcomes; SlotMachineUI draws the in-run
# machine and BloodBoonExchange sells more Blood Boons between waves. Both reach it through
# the scene-lifetime `instance`, the same pattern PlayerStats/WeaponInventory use, because
# a CanvasLayer in the UI tree has no path to a node parented under Player.

static var instance: BloodBoonSlotsPassive

signal coins_changed(coins: int)
# Emitted the moment a spin is paid for, carrying the face it will land on. The UI spins
# its reels for `reel_seconds` and then calls resolve_spin — the wheel is already decided,
# the animation is just theatre.
signal spin_started(face: int)
# Emitted once the outcome has actually been applied, with a line describing what happened.
signal spin_resolved(face: int, result_text: String)

# How long SlotMachineUI rattles the reels before resolve_spin lands the effect.
const REEL_SECONDS = 0.9

var coins: int = 0

var _slot_ui: CanvasLayer
var _spin_in_progress: bool = false

func on_initialize() -> void:
	instance = self
	coins = BloodBoonEconomy.STARTING_COINS
	_spawn_slot_ui.call_deferred()

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _spawn_slot_ui() -> void:
	if _slot_ui != null and is_instance_valid(_slot_ui):
		return

	_slot_ui = SlotMachineUI.new()
	_slot_ui.name = "SlotMachineUI"
	add_child(_slot_ui)

# ------------------------------------------------------------------------- currency

func add_coins(amount: int) -> void:
	if amount == 0:
		return
	coins = maxi(0, coins + amount)
	coins_changed.emit(coins)

func try_spend_coins(amount: int) -> bool:
	if amount < 0 or coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins)
	return true

func current_wave() -> int:
	return GameManager.wave_number if GameManager != null else 1

func spin_cost() -> int:
	return BloodBoonEconomy.get_spin_cost(current_wave())

func luck() -> float:
	return stats.luck if stats != null else 0.0

# The wheel is only live during a wave. Spinning it from the shop would let the Jester
# clear the next wave before it spawns.
func can_spin() -> bool:
	if _spin_in_progress or coins < spin_cost():
		return false
	var tree := get_tree()
	return tree != null and not tree.paused

# Pays for a spin and decides the face. Returns -1 when the spin was refused; the caller
# animates and must call resolve_spin with the returned face.
func request_spin() -> int:
	if not can_spin():
		return -1

	if not try_spend_coins(spin_cost()):
		return -1

	_spin_in_progress = true
	var face := BloodBoonEconomy.roll_face(luck())
	spin_started.emit(face)
	return face

# ------------------------------------------------------------------------- outcomes

func resolve_spin(face: int) -> void:
	_spin_in_progress = false

	var wave := current_wave()
	var l := luck()
	var damage := BloodBoonEconomy.face_damage(face, l, wave)
	var text := ""

	match face:
		BloodBoonEconomy.Face.SEVEN:
			text = _execute_strongest_enemy()
		BloodBoonEconomy.Face.SKULL:
			var hit := _damage_enemies(_live_enemies(), damage)
			text = "%d damage to %d enemies" % [damage, hit]
		BloodBoonEconomy.Face.BELL:
			var targets := _nearest_enemies(BloodBoonEconomy.BELL_TARGETS)
			var bell_hit := _damage_enemies(targets, damage)
			text = "%d damage to %d nearby" % [damage, bell_hit]
		BloodBoonEconomy.Face.BAT:
			var bat_targets := _nearest_enemies(BloodBoonEconomy.BAT_TARGETS)
			var bat_hit := _damage_enemies(bat_targets, damage)
			var healed := 0
			if bat_hit > 0 and health != null:
				healed = maxi(1, roundi(damage * BloodBoonEconomy.BAT_HEAL_FRACTION))
				health.heal(healed)
			text = "%d damage, %d health drained" % [damage, healed] if bat_hit > 0 else "Nothing within reach"
		BloodBoonEconomy.Face.VIAL:
			var enemies := _live_enemies()
			var vial_hit := _damage_enemies(enemies, damage)
			for enemy in enemies:
				if enemy.has_method("apply_movement_modifier"):
					enemy.apply_movement_modifier(BloodBoonEconomy.VIAL_SLOW_MULTIPLIER, BloodBoonEconomy.VIAL_SLOW_SECONDS)
			text = "%d damage and a slow on %d enemies" % [damage, vial_hit]
		BloodBoonEconomy.Face.COIN:
			var gold := BloodBoonEconomy.coin_face_gold(wave)
			if GameManager != null:
				GameManager.add_currency(gold)
			add_coins(spin_cost())
			text = "+%dg, spin refunded" % gold
		BloodBoonEconomy.Face.SIX:
			var dealt := _damage_self(damage)
			text = "The wheel bites back for %d" % dealt

	spin_resolved.emit(face, text)

# Kills the enemy with the most current HP anywhere on the map, boss included. Routed
# through take_damage rather than die() so the kill still pays out its shard and reward.
func _execute_strongest_enemy() -> String:
	var best: Node = null
	var best_health: HealthComponent = null

	for enemy in _live_enemies():
		var enemy_health := _health_of(enemy)
		if enemy_health == null:
			continue
		if best_health == null or enemy_health.current_health > best_health.current_health:
			best = enemy
			best_health = enemy_health

	if best == null or best_health == null:
		return "JACKPOT — but the arena is empty"

	var overkill: int = best_health.current_health + best_health.armor + 9999
	best_health.take_damage(overkill, owner_player)
	if stats != null:
		stats.notify_damage_dealt(overkill, best)

	var display_name := str(best.name)
	if best is Boss and (best as Boss).data != null:
		display_name = (best as Boss).data.boss_name
	elif best is Enemy and (best as Enemy).data != null:
		display_name = (best as Enemy).data.enemy_name

	return "JACKPOT — %s executed" % display_name

# Applies one damage number to every target, returning how many actually took it.
func _damage_enemies(targets: Array, damage: int) -> int:
	if damage <= 0:
		return 0

	var hit := 0
	for enemy in targets:
		var enemy_health := _health_of(enemy)
		if enemy_health == null or enemy_health.is_dead:
			continue
		enemy_health.take_damage(damage, owner_player)
		if stats != null:
			stats.notify_damage_dealt(damage, enemy)
		hit += 1

	return hit

# 666. Goes through the Jester's own HealthComponent, so armour and dodge apply exactly
# as they would to an enemy hit — which is why the shop tooltip's lethality warning uses
# the same maths rather than the raw number.
func _damage_self(damage: int) -> int:
	if health == null or damage <= 0:
		return 0

	var before := health.current_health
	health.take_damage(damage, owner_player)
	return before - health.current_health

# Same reduction HealthComponent would apply, used by the shop tooltip to decide whether
# 666 is currently lethal.
func projected_self_damage() -> int:
	var raw := BloodBoonEconomy.face_damage(BloodBoonEconomy.Face.SIX, luck(), current_wave())
	if health == null:
		return raw
	return maxi(1, roundi(raw * health.incoming_damage_multiplier) - health.armor)

func is_self_damage_lethal() -> bool:
	return health != null and projected_self_damage() >= health.current_health

# ------------------------------------------------------------------------- targeting

func _live_enemies() -> Array:
	var live: Array = []
	var tree := get_tree()
	if tree == null:
		return live

	for node in tree.get_nodes_in_group("Enemy"):
		var enemy_health := _health_of(node)
		if enemy_health != null and not enemy_health.is_dead:
			live.append(node)

	return live

func _nearest_enemies(count: int) -> Array:
	if owner_player == null or count <= 0:
		return []

	var origin: Vector2 = owner_player.global_position
	var candidates: Array = _live_enemies().filter(func(node): return node is Node2D)
	candidates.sort_custom(func(a, b):
		return origin.distance_squared_to((a as Node2D).global_position) < origin.distance_squared_to((b as Node2D).global_position))

	return candidates.slice(0, mini(count, candidates.size()))

static func _health_of(node: Node) -> HealthComponent:
	if node == null:
		return null
	return node.get_node_or_null("HealthComponent") as HealthComponent

# ------------------------------------------------------------------------- exchange

# Grave Coin -> Blood Boons, at the between-waves exchange.
func try_buy_with_gold(coin_count: int) -> bool:
	if coin_count <= 0 or GameManager == null:
		return false

	var price := BloodBoonEconomy.get_gold_price(coin_count, current_wave())
	if not GameManager.try_spend_currency(price):
		return false

	add_coins(coin_count)
	return true

# XP -> Blood Boons. The XP comes out of the Jester's banked total, which can drop his
# level; PlayerStats.spend_xp handles the re-levelling and the pending-boon bookkeeping.
func try_buy_with_xp(coin_count: int) -> bool:
	if coin_count <= 0 or stats == null:
		return false

	var price := BloodBoonEconomy.get_xp_price(coin_count, current_wave())
	if not stats.spend_xp(price):
		return false

	add_coins(coin_count)
	return true
