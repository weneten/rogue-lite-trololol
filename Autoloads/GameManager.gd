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

# Ids of PassiveItemData already purchased this run, so ShopUI doesn't re-offer them.
var _owned_passive_item_ids: Array[String] = []

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
	return _owned_passive_item_ids.has(passive_id)

func register_passive_item_owned(passive_id: String) -> void:
	if !passive_id.is_empty() and !_owned_passive_item_ids.has(passive_id):
		_owned_passive_item_ids.append(passive_id)

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
	_owned_passive_item_ids.clear()
	EventBus.currency_changed.emit(currency)
