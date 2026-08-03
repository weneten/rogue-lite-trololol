extends Node

# Owns per-run state: Grave Coin (the run's currency), current wave, owned passive shop items,
# and the RNG seed for the run. Reacts to EventBus signals rather than being polled by other systems.

# Grave Coin balance. Earned from enemy kills (enemy_killed) and an end-of-wave
# bonus (wave_end); spent in the shop on weapons/passives via try_spend_currency.
@export var currency: int = 0
@export var wave_number: int = 1

var run_seed: int

# Hunter chosen at CharacterSelect; Player.apply_character_data reads this at run start.
# Persists across start_new_run (re-picking a character is an explicit CharacterSelect visit,
# not something a fresh run should silently clear).
var selected_character: CharacterData

# PassiveItemData already purchased this run. Kept as the resources rather than
# bare ids because the shop tray and the Hunter's cosmetic layer both need the
# icon and effect, not just "do I own this".
var _owned_passive_items: Array[PassiveItemData] = []

var owned_passive_items: Array[PassiveItemData]:
	get:
		return _owned_passive_items

func _ready() -> void:
	run_seed = randi()

	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.wave_start.connect(_on_wave_start)
	EventBus.wave_end.connect(_on_wave_end)
	EventBus.player_died.connect(_on_player_died)

func _on_enemy_killed(enemy: Node, currency_reward: int, experience_reward: int) -> void:
	# Neither half of a kill's reward is banked here. Both the experience and
	# the coin ride on the shard the kill drops, and are only credited once the
	# player walks over it (see XpGemSpawner/XpGem). Paying out instantly made
	# the drops decorative and removed any reason to move toward a fight.
	pass

func _on_wave_start(wave_number: int) -> void:
	self.wave_number = wave_number

func _on_wave_end(wave_number: int) -> void:
	# Rewards clearing the wave itself, on top of whatever was earned killing enemies during it.
	add_currency(ShopEconomy.get_wave_end_bonus(wave_number))

func is_passive_item_owned(passive_id: String) -> bool:
	for item in _owned_passive_items:
		if item != null and item.id == passive_id:
			return true
	return false

func register_passive_item(item: PassiveItemData) -> void:
	if item == null or is_passive_item_owned(item.id):
		return

	_owned_passive_items.append(item)
	# Everything that reacts to the loadout — the Hunter's cosmetic layer, the
	# shop's owned tray — listens for this rather than polling the array.
	EventBus.item_picked_up.emit(item.id)

func _on_player_died() -> void:
	# Stage stub: full run-end / game-over flow (stats screen, meta-currency payout)
	# will be implemented once the UI/Shop stage exists.
	print("[GameManager] Run ended on wave %d with %d currency." % [wave_number, currency])

func add_currency(amount: int) -> void:
	currency = maxi(0, currency + amount)
	EventBus.currency_changed.emit(currency)

func try_spend_currency(amount: int) -> bool:
	if amount < 0 or currency < amount:
		return false

	currency -= amount
	EventBus.currency_changed.emit(currency)
	return true

# Resets state for a fresh run. Pass 0 to roll a new random seed.
func start_new_run(seed: int = 0) -> void:
	currency = 0
	wave_number = 1
	run_seed = seed if seed != 0 else randi()
	_owned_passive_items.clear()
	EventBus.currency_changed.emit(currency)
