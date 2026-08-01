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

@export var attacks: Array[BossAttackPatternData] = []
