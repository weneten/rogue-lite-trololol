extends Node
class_name PassiveAbility

# Base hook for a Hunter's unique passive ability. One concrete subclass per CharacterData
# (selected via PassiveAbilityFactory off CharacterData.PassiveId) attached as a child Node of
# Player at run start (see Player.ApplyCharacterData). Subclasses override whichever hooks their
# effect needs; the rest default to no-ops. Continuous effects (DoTs, ramping bonuses, familiar
# upkeep) use Godot's own _Process on the subclass itself rather than a bespoke tick list, so
# pausing the tree (level-up/shop) automatically pauses them too, same as everything else.

# Owning hunter actor (renamed from Owner to avoid hiding Node.Owner).
var owner_player: Player
var stats: PlayerStats
var health: HealthComponent
var data: CharacterData

# Wires the shared references and runs one-time setup. Called by Player right after AddChild.
func setup(owner: Player, stats_param: PlayerStats, health_param: HealthComponent, data_param: CharacterData) -> void:
	owner_player = owner
	stats = stats_param
	health = health_param
	data = data_param
	on_initialize()

# One-shot setup: apply flat stat bonuses, spawn familiars, etc. Runs once, right after Setup.
func on_initialize() -> void:
	pass

# Called by PlayerStats.NotifyDamageDealt after every weapon hit the player lands.
func on_damage_dealt(amount: int, target: Node) -> void:
	pass

# Called whenever the player's HealthComponent takes damage (post-armor/dodge).
func on_damage_taken(amount: int, source: Node) -> void:
	pass

# Called whenever any enemy dies (single-player game, so always a player kill).
func on_enemy_killed(enemy: Node) -> void:
	pass
