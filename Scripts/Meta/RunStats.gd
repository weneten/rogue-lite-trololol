extends Node
class_name RunStats

static var instance: RunStats

# Per-run counters for the death/summary screen. Listens only to EventBus (additive, no
# GameManager mutation). Reset at run start; finalize once on death or wave-20 clear.

# Highest wave reached this run (from OnWaveStart).
var waves_survived: int

var kills: int
var damage_dealt: int

# Cumulative Grave Coin granted this run (from OnCurrencyChanged deltas).
var gold_earned: int

var run_complete: bool
var is_finalized: bool
var meta_currency_granted: int

var _last_currency: int
var _subscribed: bool = false


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	_subscribe()
	reset()


func _exit_tree() -> void:
	_unsubscribe()
	if instance == self:
		instance = null


func reset() -> void:
	waves_survived = 0
	kills = 0
	damage_dealt = 0
	gold_earned = 0
	run_complete = false
	is_finalized = false
	meta_currency_granted = 0
	_last_currency = GameManager.currency if GameManager != null else 0


# Compute + grant meta currency once. Safe to call multiple times (idempotent).
func finalize_and_grant_meta(run_complete_: bool) -> int:
	if is_finalized:
		return meta_currency_granted

	run_complete = run_complete_
	is_finalized = true

	# Base: 10 per wave + kill chip + gold drip; clear wave 20 for bonus.
	var payout = waves_survived * 10 + kills / 5 + gold_earned / 50
	if run_complete:
		payout += 100

	meta_currency_granted = maxi(0, payout)
	if meta_currency_granted > 0:
		MetaSave.add_meta_currency(meta_currency_granted)

	print("[RunStats] Finalized. Waves=%d Kills=%d Dmg=%d Gold=%d Complete=%s Meta+=%d" % [
		waves_survived, kills, damage_dealt, gold_earned, run_complete, meta_currency_granted
	])
	return meta_currency_granted


static func preview_payout(waves: int, kills: int, gold: int, run_complete_: bool) -> int:
	var payout = waves * 10 + kills / 5 + gold / 50
	if run_complete_:
		payout += 100
	return maxi(0, payout)


func _subscribe() -> void:
	if _subscribed or EventBus == null:
		return

	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_damage_dealt.connect(_on_player_damage_dealt)
	EventBus.wave_start.connect(_on_wave_start)
	EventBus.wave_end.connect(_on_wave_end)
	EventBus.currency_changed.connect(_on_currency_changed)
	_subscribed = true


func _unsubscribe() -> void:
	if not _subscribed or EventBus == null:
		_subscribed = false
		return

	EventBus.enemy_killed.disconnect(_on_enemy_killed)
	EventBus.player_damage_dealt.disconnect(_on_player_damage_dealt)
	EventBus.wave_start.disconnect(_on_wave_start)
	EventBus.wave_end.disconnect(_on_wave_end)
	EventBus.currency_changed.disconnect(_on_currency_changed)
	_subscribed = false


func _on_enemy_killed(enemy: Node, currency_reward: int, experience_reward: int) -> void:
	if is_finalized:
		return

	kills += 1


func _on_player_damage_dealt(target: Node, amount: int) -> void:
	if is_finalized or amount <= 0:
		return

	damage_dealt += amount


func _on_wave_start(wave_number: int) -> void:
	if is_finalized:
		return

	waves_survived = maxi(waves_survived, wave_number)


func _on_wave_end(wave_number: int) -> void:
	if is_finalized:
		return

	waves_survived = maxi(waves_survived, wave_number)

	# Wave 20 clear = run victory. DeathScreen listens too; we only mark stats here.
	if wave_number >= 20:
		run_complete = true


func _on_currency_changed(current_currency: int) -> void:
	if is_finalized:
		return

	var delta = current_currency - _last_currency
	if delta > 0:
		gold_earned += delta

	_last_currency = current_currency
