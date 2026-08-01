extends Resource
class_name WeaponData

# Rarity tier shown on the weapon's UI frame; also feeds shop pricing/drop tables later.
enum RarityTier {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
}

# Bitmask categorisation of a weapon. Flags (not a plain enum) because a weapon can be
# more than one thing at once, e.g. a Holy Firearm or a Cursed Melee weapon — Weapon.gd
# branches its attack behaviour (melee hitbox vs. projectile spawn) off the Melee bit.
enum WeaponClass {
	NONE = 0,
	MELEE = 1 << 0,
	RANGED = 1 << 1,
	FIREARM = 1 << 2,
	MAGIC = 1 << 3,
	HOLY = 1 << 4,
	CURSED = 1 << 5,
	AOE = 1 << 6,
	SUMMON = 1 << 7,
	# Placed hazard (Iron Bear Trap): Weapon.gd drops a Trap.tscn instead of attacking
	# directly; the trap itself deals the damage/root once a target walks over it.
	TRAP = 1 << 8,
}

@export var name: String = "Unnamed Weapon"
@export var icon: Texture2D

# For Ranged/Firearm/Magic weapons: the pooled projectile scene Weapon.gd spawns.
# Unused for pure Melee weapons (they hit via an Area2D hitbox instead).
@export var projectile_scene: PackedScene

@export_group("Combat Stats")
@export var damage: float = 10.0
# Attacks per second. Weapon.gd cooldown = 1 / attack_speed.
@export var attack_speed: float = 1.0
@export var range: float = 100.0
@export_range(0, 1, 0.01) var crit_chance: float = 0.05
@export_range(1, 5, 0.1) var crit_multiplier: float = 2.0
# How many projectiles fired per shot (Ranged/Firearm/Magic only). Melee ignores this.
@export_range(1, 12, 1) var projectile_count: int = 1
# Total spread angle in degrees across which projectile_count projectiles fan out.
@export var spread: float = 0.0
@export var knockback: float = 0.0

@export_group("Classification")
@export var rarity_tier: RarityTier = RarityTier.COMMON
@export_flags("Melee", "Ranged", "Firearm", "Magic", "Holy", "Cursed", "AoE", "Summon", "Trap") var weapon_class: int = WeaponClass.MELEE

# Optional tiered-up version of this weapon (e.g. Flintlock Pistol -> Hexed Revolver
# -> Cathedral Rifle). Not auto-applied by anything yet in this stage — it's the data hook a
# future fusion/evolution shop feature reads to know what a weapon becomes.
@export var upgrades_to: WeaponData

@export_group("Magic Scaling")
# Only relevant for WeaponClass.MAGIC. Extra multiplier applied on top of
# PlayerStats.magic_damage_multiplier: final = 1 + magic_scaling_per_point * (magic_stat - 1).
# A pure melee/firearm weapon leaves this at 0 and is untouched by the Magic stat.
@export var magic_scaling_per_point: float = 0.0

@export_group("Cursed Scaling")
# Only relevant for WeaponClass.CURSED. Extra damage multiplier scaling with the
# wielder's missing HP fraction: final = 1 + cursed_missing_hp_scaling * missing_hp_fraction.
# A full-HP wielder gets no bonus; a near-death wielder hits much harder.
@export var cursed_missing_hp_scaling: float = 0.0

@export_group("Area Effect")
# Only relevant for WeaponClass.AOE (and not Melee, which cleaves via its hitbox
# instead). Radius of the burst; falls back to range when left at 0.
@export var aoe_radius: float = 0.0
# True = burst centered on the wielder (Bell of Judgement's screen-wide pulse);
# false = centered on the current target (a thrown Firebomb/Holy Water Flask's impact point).
@export var aoe_centered_on_self: bool = false
# Movement-speed multiplier applied to anything the AoE hits, e.g. 0.4 = slowed to
# 40% speed (Frost Lantern). 0 (default) = no slow effect at all.
@export_range(0, 1, 0.01) var slow_multiplier: float = 0.0
@export var slow_duration_seconds: float = 0.0

@export_group("Summon")
# Only relevant for WeaponClass.SUMMON. Independent Familiar.tscn (or compatible)
# scene spawned once when this Weapon node is created; it fights on its own from then on and
# this Weapon node stops doing anything else (see Weapon._process's Summon early-out).
@export var summon_scene: PackedScene

@export_group("Trap")
# Only relevant for WeaponClass.TRAP. Pooled Trap.tscn (or compatible) scene dropped
# at the wielder's feet on cooldown expiry.
@export var trap_scene: PackedScene
@export var trap_root_duration_seconds: float = 1.5
# How long an armed-but-untriggered trap waits before despawning back to the pool.
@export var trap_lifetime_seconds: float = 12.0

@export_group("On-Hit")
# Fraction of damage dealt by THIS weapon healed back to the wielder immediately
# (Vampiric Claws). Independent of PlayerStats.lifesteal_fraction, which is the character-wide
# passive version — the two stack additively.
@export_range(0, 1, 0.01) var on_hit_lifesteal_fraction: float = 0.0

@export_group("Meta")
@export_range(1, 5, 1) var shop_cost: int = 10
