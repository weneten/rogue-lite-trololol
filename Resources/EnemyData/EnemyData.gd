extends Resource
class_name EnemyData

# How an enemy delivers its damage. Drives the branch in Enemy.cs's attack execution.
enum EnemyAttackPattern {
	MELEE,
	RANGED
}

# High-level combat approach tag consumed by Enemy.cs's state machine to decide how it
# closes/holds distance. Chase/Attack are melee-style (walk in, stop in range, swing).
# Wander is the idle/no-target roam state. Flee marks kiting ranged units that back off
# once the player gets closer than PreferredDistance while still attacking in range.
enum EnemyBehaviorType {
	CHASE,
	WANDER,
	ATTACK,
	FLEE
}

# Data-driven definition for a regular (non-boss) enemy archetype.

@export var enemy_name: String = "Ghoul"

# Always the generic Enemy.tscn — one scene driven entirely by this Resource.
@export var enemy_scene: PackedScene

# Modulate tint on the sprite (also used for elite recolor lerp).
@export var sprite_color: Color = Color(1.0, 1.0, 1.0, 1.0)

# Imported sheet texture (preferred). Wiring this as ExtResource in .tres makes Godot
# keep a hard resource reference so GD.Load never hits "No loader found".
@export var sprite_sheet: Texture2D

# Path to sheet PNG under Assets/sprites (fallback if SpriteSheet is null).
@export var sprite_sheet_path: String = ""

# Optional JSON path; if empty, uses same path with .json extension.
@export var sprite_json_path: String = ""

# Visual scale of the 64×64 sheet (rats smaller, tanks larger).
@export var sprite_scale: float = 1.0

# One-shot attack anim name on the sheet (aliases resolved if missing).
@export var attack_anim_name: String = "attack_slash"

@export var max_health: int = 20

# Feeds character passives that key off enemy type (e.g. Silver Priest's bonus vs undead).
# Defaults true since most current archetypes (ghouls, skeletons) already are.
@export var is_undead: bool = true
@export var move_speed: float = 80.0
@export var attack_damage: float = 5.0
@export var attack_pattern: EnemyAttackPattern = EnemyAttackPattern.MELEE
@export var behavior_type: EnemyBehaviorType = EnemyBehaviorType.CHASE

# For Ranged enemies: pooled projectile scene fired via the shared Projectile.cs. Unused for Melee.
@export var projectile_scene: PackedScene

# Distance at which an idle (Wander) enemy notices the player and starts chasing.
@export var aggro_range: float = 500.0

# Distance at which the enemy stops closing and enters its Attack state.
@export var attack_range: float = 40.0

# Flee-only: if the player gets closer than this, the enemy backs away while still attacking. 0 disables fleeing.
@export var preferred_distance: float = 0.0
@export var attack_cooldown: float = 1.0

# When true, OnDied detonates an AoE that hits Player + other Enemies via HealthComponent.
@export var explode_on_death: bool = false
@export var explosion_radius: float = 90.0
@export var explosion_damage: float = 18.0

# When true, collision_mask ignores World layer so the unit phases through walls/obstacles.
@export var phases_through_obstacles: bool = false

# When true, chase path jitter-strafes instead of walking a straight line.
@export var erratic_movement: bool = false

@export var currency_reward: int = 1
@export var experience_reward: int = 1

# Relative weight used by WaveManager's weighted random spawn table.
@export var spawn_weight: float = 1.0
@export var min_wave_to_appear: int = 1
