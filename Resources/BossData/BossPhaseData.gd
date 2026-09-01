extends Resource
class_name BossPhaseData

# One boss phase: becomes active when HP fraction drops to EnterHpFraction (phase 0 is always
# active from fight start). Carries move/attack multipliers and the attack pattern pool.

@export var phase_name: String = "Phase 1"

# HP fraction (0–1) at or below which this phase activates. Phase 0 should use 1.0 (start).
# Later phases use lower values (e.g. 0.5 blood frenzy). Order phases high → low.
@export var enter_hp_fraction: float = 1.0

@export var move_speed_multiplier: float = 1.0

# Multiplies each attack's CooldownSeconds while this phase is active (<1 = faster).
@export var attack_cooldown_multiplier: float = 1.0

# Multiplies every point of damage the boss deals while this phase is active —
# telegraphed attacks, contact damage, hazards it leaves behind. 1.0 is the
# authored number; 2.0 is a boss that got twice as dangerous, not one whose
# every attack pattern had to be duplicated with bigger figures in it.
@export var damage_multiplier: float = 1.0

@export_group("Phase appearance")
# Optional sheet swap on entering this phase. Leave empty to keep the sheet
# from BossData, which is what a boss that only gets angrier wants; a boss that
# visibly transforms points these at its second set of art.
@export var sprite_sheet: Texture2D
@export var sprite_sheet_path: String = ""
@export var sprite_json_path: String = ""
# 0 keeps BossData.sprite_scale.
@export var sprite_scale: float = 0.0

@export var attacks: Array[BossAttackPatternData] = []
