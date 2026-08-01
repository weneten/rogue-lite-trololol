extends Node
class_name HealthComponent

# Reusable HP tracker attachable to any actor (Player, Enemy, Boss). Owns no game-system
# knowledge (currency rewards, EventBus, etc.) — the owning actor script listens to
# damaged/died and decides what global signals to raise.

@export var max_health: int = 100

# Flat damage reduction applied after incoming_damage_multiplier, before the hit lands
# (minimum 1 damage always gets through). Driven by CharacterData.StartingArmor / passives
# like the Bloodstained Crusader's Taunt Armor. Defaults to 0 so enemies/bosses are unaffected.
@export var armor: int = 0

# Chance [0,1] to negate an incoming hit entirely before any reduction. Driven by
# CharacterData.StartingDodgeChance. Defaults to 0 so enemies/bosses are unaffected.
@export var dodge_chance: float = 0.0

# Multiplies incoming damage before Armor is subtracted; set by PlayerStats for
# passives like the Reaper's HP-for-damage tradeoff (deals more, takes more). Starts at 1
# (no change) so enemies/bosses are unaffected unless explicitly wired.
var incoming_damage_multiplier: float = 1.0

var current_health: int
var is_dead: bool = false

# Fired on every HP change (damage or heal) with the resulting value.
signal health_changed(current_health: int, max_health: int)

# Fired only on damage, before health_changed, carrying the raw damage dealt.
signal damaged(amount: int, source: Node)

signal died(source: Node)

func _ready() -> void:
	current_health = max_health

# Applies damage (after dodge_chance/incoming_damage_multiplier/armor); clamps at 0 and
# triggers die() exactly once. No-op once dead or fully dodged.
func take_damage(amount: int, source: Node = null) -> void:
	if is_dead or amount <= 0:
		return

	if dodge_chance > 0.0 and randf() < dodge_chance:
		return

	# Armor is a flat post-multiplier reduction; a hit always does at least 1 damage so
	# stacking Armor can never make an actor fully unkillable.
	var scaled_amount = maxi(1, roundi(amount * incoming_damage_multiplier) - armor)

	current_health = maxi(0, current_health - scaled_amount)
	damaged.emit(scaled_amount, source)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		die(source)

# Restores HP up to max_health. No-op once dead.
func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return

	current_health = mini(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

# Raises max_health by amount (e.g. a level-up upgrade) and grants the same amount of
# current HP immediately, so the boost is felt right away rather than only on next heal. No-op once dead.
func increase_max_health(amount: int) -> void:
	if is_dead or amount <= 0:
		return

	max_health += amount
	current_health = mini(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

# Forces death regardless of remaining HP (e.g. instant-kill effects). Idempotent.
func die(source: Node = null) -> void:
	if is_dead:
		return

	is_dead = true
	current_health = 0
	died.emit(source)

# Resets is_dead and restores HP. Used by respawning actors (e.g. TargetDummy) — never called on Player/normal enemies which stay dead.
func revive(to_health: Variant = null) -> void:
	is_dead = false
	current_health = clampi(to_health if to_health != null else max_health, 0, max_health)
	health_changed.emit(current_health, max_health)
