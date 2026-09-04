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

# Difficulty picked at CharacterSelect. Like selected_character it survives
# start_new_run: choosing it is a deliberate act, and dying should not quietly
# put the player back on Normal.
var difficulty: int = Difficulty.Level.NORMAL

# The Hunter's move speed at run start, published by Player once it has applied
# its CharacterData. "Dark is the Night" sets enemy speed relative to this, and
# enemies spawn before they could ask a Player that may not exist yet.
var player_base_speed: float = 300.0

# Auto-Wave: the intermission is skipped whole — no moon boons, no Ossuary. The
# next wave comes up on WaveManager's own inter-wave timer, exactly as it does
# after the shop is dismissed.
#
# Levels earned under it are deferred, not thrown away: PlayerStats.pending_boons
# keeps counting, and the first intermission that actually runs hands over
# everything that piled up. Switching it off is how you collect.
#
# Per-run and never saved: it is a way to play a run, not a setting.
var auto_wave: bool = false

# PassiveItemData already purchased this run. Kept as the resources rather than
# bare ids because the shop tray and the Hunter's cosmetic layer both need the
# icon and effect, not just "do I own this".
var _owned_passive_items: Array[PassiveItemData] = []

var owned_passive_items: Array[PassiveItemData]:
	get:
		return _owned_passive_items

func _ready() -> void:
	run_seed = randi()
	_apply_runtime_quality()

	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.wave_start.connect(_on_wave_start)
	EventBus.wave_end.connect(_on_wave_end)
	EventBus.player_died.connect(_on_player_died)

# Browser WASM is single-thread and fill-rate bound. Cap the sim so a hitch
# cannot snowball, and keep the canvas at project resolution.
func _apply_runtime_quality() -> void:
	Engine.max_fps = 60
	if not OS.has_feature("web"):
		return

	Engine.physics_ticks_per_second = 30
	Engine.max_physics_steps_per_frame = 2
	# Firefox's WASM/WebGL path hitches harder than Chromium if the sim
	# tries to catch up more than one extra physics tick.
	if is_firefox():
		Engine.max_physics_steps_per_frame = 1

static func is_web() -> bool:
	return OS.has_feature("web")

static func is_firefox() -> bool:
	if not OS.has_feature("web"):
		return false
	if not ClassDB.class_exists("JavaScriptBridge"):
		return false
	var ua := str(JavaScriptBridge.eval("navigator.userAgent || ''"))
	return ua.contains("Firefox")

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

# Kept as the plain yes/no question now that get_passive_item_count answers the
# interesting one. Nothing in the shop asks this any more — relics stack, so
# "owns one" stopped being a reason to do anything differently.
func is_passive_item_owned(passive_id: String) -> bool:
	return get_passive_item_count(passive_id) > 0

# How many copies of a relic the Hunter is carrying. Relics stack, so "do you
# own it" and "how many" are different questions and the shop asks both.
func get_passive_item_count(passive_id: String) -> int:
	var count := 0
	for item in _owned_passive_items:
		if item != null and item.id == passive_id:
			count += 1

	return count

# Appends unconditionally: a second copy of a relic is a second copy of its
# effect. The guard that used to sit here silently swallowed the purchase, so a
# player who bought a duplicate paid for nothing.
func register_passive_item(item: PassiveItemData) -> void:
	if item == null:
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
func set_difficulty(level: int) -> void:
	difficulty = level
	print("[GameManager] Difficulty set to %s." % Difficulty.display_name(level))

# Returns the new state so the caller can speak it aloud without reading it back.
func toggle_auto_wave() -> bool:
	set_auto_wave(not auto_wave)
	return auto_wave

func set_auto_wave(enabled: bool) -> void:
	if auto_wave == enabled:
		return

	auto_wave = enabled
	EventBus.auto_wave_changed.emit(enabled)
	print("[GameManager] Auto-Wave %s." % ("on — intermissions skipped" if enabled else "off"))

func start_new_run(seed: int = 0) -> void:
	currency = 0
	wave_number = 1
	set_auto_wave(false)
	run_seed = seed if seed != 0 else randi()
	_owned_passive_items.clear()
	EventBus.currency_changed.emit(currency)
