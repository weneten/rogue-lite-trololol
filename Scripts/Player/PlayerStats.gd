extends Node

class_name PlayerStats

static var instance: PlayerStats

# Owns the player's XP/level progression, the additive stat bonuses granted by level-up
# upgrades and shop passives (see LevelUpUI/ShopUI), and the Hunter-specific bonuses applied
# from CharacterData at run start (see Player.ApplyCharacterData). Lives as a child node of the
# Player scene rather than an autoload (only one Player exists per run) but is still exposed via
# a scene-lifetime Instance singleton, mirroring the EventBus/GameManager pattern, so
# Weapon/HUD/LevelUpUI/passives can reach it without a direct scene reference.

# Wiring
@export var health_component_path: NodePath

# XP Curve
# XP required for level 1 -> 2 (before growth). Ghoul ≈ 3 XP, so ~4 kills early.
@export var base_xp_to_level: int = 12
# Power-curve exponent in CalculateXpRequirement (base * level^growth).
# 1.0 = linear; ~1.25–1.3 = gentle mid/late climb; avoid >1.5 (runaway). Sample with
# defaults (12, 1.28): L1=12, L5≈91, L10≈228, L20≈546 XP to next.
@export var xp_growth_per_level: float = 1.28

# Multiplies all Weapon damage; read by Weapon.cs. Starts at 1 (no bonus).
var damage_multiplier: float = 1.0
# Multiplies Player.MoveSpeed; read by Player.cs. Starts at 1 (no bonus).
var move_speed_multiplier: float = 1.0
# Multiplies Weapon.AttackSpeed (attacks/sec) before the cooldown is derived from it;
# read by Weapon.cs. Driven by the Moonlit Duelist's dual-wield passive. Starts at 1.
var attack_speed_multiplier: float = 1.0
# Added flat on top of WeaponData.CritChance when a Weapon rolls a crit. Starts at 0.
var extra_crit_chance: float = 0.0
# Added flat on top of WeaponData.CritMultiplier for crit hits. Starts at 0.
var extra_crit_multiplier: float = 0.0
# Fraction of damage dealt returned as healing; applied in NotifyDamageDealt. Starts at 0.
var lifesteal_fraction: float = 0.0
# Multiplies damage dealt to EnemyData.IsUndead targets. Starts at 1 (no bonus).
var undead_damage_multiplier: float = 1.0
# Multiplies damage dealt by WeaponClass.Magic weapons only. Starts at 1 (no bonus).
var magic_damage_multiplier: float = 1.0
# Multiplies incoming damage before Armor is applied; mirrored onto HealthComponent so
# the reduction actually takes effect regardless of who calls TakeDamage. Starts at 1 (no change).
var damage_taken_multiplier: float = 1.0
# HP restored per second out of combat and in it alike; ticked in _process and
# only ever applied in whole points so HealthComponent never sees a fraction.
var health_regen_per_second: float = 0.0
# Added to every pickup's attract radius, so relics that "vacuum" shards do it
# through one number instead of each XpGem carrying its own copy.
var pickup_radius_bonus: float = 0.0
# Multiplies XP and Grave Coin taken from pickups. Deliberately NOT applied in
# GameManager.add_currency: that path also carries shop refunds, which must not
# grow just because the player owns a gold relic.
var xp_gain_multiplier: float = 1.0
var currency_gain_multiplier: float = 1.0

# The selected Hunter's unique passive, if any (set by Player.ApplyCharacterData right
# after spawning it). Hooked here rather than in Player so Weapon can reach OnDamageDealt via
# the same reference it already holds for damage-multiplier lookups.
var active_passive: PassiveAbility

var level: int = 1
var current_xp: int = 0

var _health: HealthComponent
# Tracks how much of DamageMultiplier currently comes from CurseLiftScalingPassive's
# ramp so each frame's SetCurseDamageBonus call can apply just the delta instead of stacking.
var _curse_damage_bonus_applied: float = 0.0
# Fractional HP banked between regen ticks.
var _regen_carry: float = 0.0

var xp_to_next_level: int:
	get:
		return calculate_xp_requirement(level, base_xp_to_level, xp_growth_per_level)

func _ready() -> void:
	instance = self
	_health = get_node_or_null(health_component_path)

	if _health != null:
		_health.damaged.connect(func(amount: int, source: Node): if active_passive: active_passive.on_damage_taken(amount, source))

	if EventBus != null:
		# Single-player game: every enemy death is a player kill, so this is safe to forward
		# unconditionally rather than checking the kill's source.
		EventBus.enemy_killed.connect(func(enemy: Node, currency_reward: int, experience_reward: int): if active_passive: active_passive.on_enemy_killed(enemy))

func _exit_tree() -> void:
	if instance == self:
		instance = null

# Pure XP-curve formula (no instance state): requirement = baseXp * level^growthRate.
# Soft power curve — not pure exponential (would be growth^level). Tune BaseXpToLevel /
# XpGrowthPerLevel only; leave this method alone.
# TODO: re-check mid/late pace once EnemyScaling + wave density settle (Enemy roster owns those).
static func calculate_xp_requirement(level: int, base_xp: int, growth_rate: float) -> int:
	return maxi(1, roundi(base_xp * pow(maxf(1, level), growth_rate)))

# Called by XpGem on pickup. Banks XP and triggers a level-up (pausing the run) once enough has been earned.
func _process(delta: float) -> void:
	if health_regen_per_second <= 0.0 or _health == null or _health.is_dead:
		return

	_regen_carry += health_regen_per_second * delta
	var whole: int = int(_regen_carry)
	if whole > 0:
		_regen_carry -= whole
		_health.heal(whole)

func add_xp(amount: int) -> void:
	if amount <= 0:
		return

	amount = maxi(1, roundi(amount * xp_gain_multiplier))
	current_xp += amount
	EventBus.xp_changed.emit(current_xp, xp_to_next_level, level)
	try_level_up()

func try_level_up() -> void:
	if current_xp < xp_to_next_level:
		return

	current_xp -= xp_to_next_level
	level += 1

	# Brief pause while the level-up choice screen is up; the tree resumes via
	# ConfirmUpgradeSelected() once LevelUpUI reports a choice was made.
	get_tree().paused = true

	EventBus.xp_changed.emit(current_xp, xp_to_next_level, level)
	EventBus.player_level_up.emit(level)

# Called by LevelUpUI once the player has picked an upgrade. Resumes gameplay — unless the
# XP already banked covers the next level too (a big multi-gem pickup), in which case another
# level-up screen is triggered immediately instead of actually unpausing.
func confirm_upgrade_selected() -> void:
	if current_xp >= xp_to_next_level:
		try_level_up()
	else:
		get_tree().paused = false

func apply_damage_upgrade(multiplier_increase: float) -> void:
	damage_multiplier += multiplier_increase

func apply_move_speed_upgrade(multiplier_increase: float) -> void:
	move_speed_multiplier += multiplier_increase

func apply_max_health_upgrade(amount: int) -> void:
	if _health != null:
		_health.increase_max_health(amount)

func apply_attack_speed_bonus(multiplier_increase: float) -> void:
	attack_speed_multiplier += multiplier_increase

func apply_extra_crit(chance_increase: float, multiplier_increase: float) -> void:
	extra_crit_chance += chance_increase
	extra_crit_multiplier += multiplier_increase

func apply_lifesteal(fraction_increase: float) -> void:
	lifesteal_fraction += fraction_increase

func apply_undead_damage_bonus(multiplier_increase: float) -> void:
	undead_damage_multiplier += multiplier_increase

func apply_magic_damage_bonus(multiplier_increase: float) -> void:
	magic_damage_multiplier += multiplier_increase

# Flat post-multiplier damage reduction on HealthComponent. A hit always lands
# for at least 1, so armour relics can never make the player unkillable.
func apply_armor(points: int) -> void:
	if _health != null:
		_health.armor = maxi(0, _health.armor + points)

func apply_dodge(chance_increase: float) -> void:
	if _health != null:
		# Capped well short of 1.0: a build that literally cannot be hit stops
		# being a game.
		_health.dodge_chance = clampf(_health.dodge_chance + chance_increase, 0.0, 0.6)

func apply_health_regen(per_second_increase: float) -> void:
	health_regen_per_second += per_second_increase

func apply_pickup_radius(radius_increase: float) -> void:
	pickup_radius_bonus += radius_increase

func apply_xp_gain_bonus(multiplier_increase: float) -> void:
	xp_gain_multiplier += multiplier_increase

func apply_currency_gain_bonus(multiplier_increase: float) -> void:
	currency_gain_multiplier += multiplier_increase

func set_magic_damage_multiplier(value: float) -> void:
	magic_damage_multiplier = value

# Increases DamageTakenMultiplier and mirrors it onto HealthComponent immediately —
# used by the Reaper's HP-for-damage tradeoff (more damage dealt, more damage taken).
func apply_incoming_damage_multiplier(increase: float) -> void:
	damage_taken_multiplier += increase
	if _health != null:
		_health.incoming_damage_multiplier = damage_taken_multiplier

# Sets the Cursed Noble's ramping damage bonus to an absolute total each frame,
# applying only the delta to DamageMultiplier so repeated calls never over-stack.
func set_curse_damage_bonus(total_bonus: float) -> void:
	damage_multiplier += total_bonus - _curse_damage_bonus_applied
	_curse_damage_bonus_applied = total_bonus

# Called by Weapon.cs after every landed hit. Applies lifesteal, broadcasts
# EventBus.OnPlayerDamageDealt, and forwards to the active passive's OnDamageDealt hook.
func notify_damage_dealt(amount: int, target: Node) -> void:
	if lifesteal_fraction > 0.0:
		if _health != null:
			_health.heal(roundi(amount * lifesteal_fraction))

	EventBus.player_damage_dealt.emit(target, amount)
	if active_passive != null:
		active_passive.on_damage_dealt(amount, target)
