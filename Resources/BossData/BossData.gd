extends Resource
class_name BossData

# Data-driven definition for a boss encounter, triggered at a specific wave by BossManager.
# Phases + per-phase attack patterns drive the boss AI state machine; BossScene points at the
# concrete boss scene (script + placeholder art).

@export var boss_name: String = "The Crimson Countess"
@export var boss_scene: PackedScene
@export var portrait: Texture2D

# Placeholder Polygon2D tint so bosses read as visually distinct.
@export var sprite_color: Color = Color(0.7, 0.15, 0.2, 1.0)

@export var max_health: int = 500
@export var move_speed: float = 60.0

# Passive contact damage when the player overlaps the boss body hitbox.
@export var contact_damage: float = 15.0
@export var contact_damage_cooldown: float = 1.0

# Ordered high→low EnterHpFraction. Index 0 is the opening phase; later entries unlock
# as HP falls (e.g. blood frenzy at 0.5). Empty array → single synthetic full-HP phase
# using AbilityIds only (legacy fallback).
@export var phases: Array[BossPhaseData] = []

# Wave number that triggers this boss (BossManager matches OnWaveStart).
@export var wave_trigger: int = 10
@export var currency_reward: int = 100
@export var experience_reward: int = 50

# Legacy ability id list; preferred path is Phases[].Attacks[].AttackId.
@export var ability_ids: Array[String] = []
