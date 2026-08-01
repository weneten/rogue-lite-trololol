extends Resource
class_name BossAttackPatternData

# One telegraphed (or instant) boss attack definition. AttackId is resolved by the boss
# subclass; numeric fields are shared param slots so designers can tune without code.

# Key looked up by boss AI (e.g. "ground_smash", "curse_bolt", "bat_swarm").
@export var attack_id: String = "melee"

# Red AoE / cast warning duration before the hit resolves.
@export var windup_seconds: float = 0.8

# Brief lock after the hit before the boss can pick another attack.
@export var recovery_seconds: float = 0.25

# Base delay until this attack (or any attack) may fire again after recovery.
@export var cooldown_seconds: float = 2.5

@export var damage: float = 20.0

# AoE / shockwave / ritual radius in pixels.
@export var radius: float = 80.0

# Preferred cast range / blink distance / bolt travel context.
@export var range: float = 220.0

# Projectile / dash speed where applicable.
@export var speed: float = 280.0

# How many summons, bolts, or rings this attack produces.
@export var count: int = 1

# DoT / zone lifetime / frenzy duration depending on AttackId.
@export var duration: float = 3.0

# Fraction of damage healed by the boss (blood frenzy life drain). 0 = none.
@export var heal_fraction: float = 0.0
