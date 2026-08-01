extends Resource
class_name CharacterData

# Data-driven definition for a selectable Hunter (Brotato-style character sheet). CharacterSelect
# lists every CharacterData it's given; picking one has Player.cs apply MaxHealth/MoveSpeed/Armor/
# Dodge/Crit/Magic, equip StartingWeapons, and spawn the PassiveAbility named by PassiveId (see
# Scripts/Player/Passives/PassiveAbilityFactory.cs) as a child node driving that Hunter's unique effect.

@export var character_name: String = "Unnamed Hunter"
@export var lore_blurb: String = ""
@export var portrait: Texture2D

# Unused by the current single Player.tscn flow (stage stub for a future per-Hunter
# scene/art swap) — reserved so this Resource shape doesn't need to change when that lands.
@export var character_scene: PackedScene

# Nightbane sprite sheet (PNG under Assets/sprites) driving both the in-game Player
# visual and the CharacterSelect preview. Prefer assigning the Texture2D as well as the path —
# path-only GD.Load can fail when import state is flaky (see SpriteSheetCache).
# Hunters without a sheet keep Player.tscn's fallback polygon.
@export var sprite_sheet: Texture2D
@export var sprite_sheet_path: String = ""

# Atlas JSON next to the sheet (frame size, per-animation frame indices, fps, origin).
# Empty falls back to the sheet path with a .json extension.
@export var sprite_json_path: String = ""
@export var sprite_scale: float = 1.0

# Animation played on attacks; falls back through SpriteSheetCache's known attack
# names when this sheet doesn't have it.
@export var attack_anim_name: String = ""

@export var max_health: int = 100
@export var move_speed: float = 300.0
@export var starting_armor: int = 0
@export var starting_dodge_chance: float = 0.0
@export var starting_crit_chance: float = 0.05

# Baseline multiplier applied only to WeaponClass.Magic weapons (see PlayerStats.MagicDamageMultiplier).
@export var starting_magic_power: float = 1.0

# Legacy stat carried over from the stage-6 stub; not yet consumed by any system
# (reserved for future loot-luck/drop-rarity tuning).
@export var starting_luck: float = 0.0

@export var starting_weapons: Array[WeaponData] = []

# Key consumed by PassiveAbilityFactory to build the matching PassiveAbility subclass.
# Empty/unknown ids simply leave the Hunter without a passive (warned in Player.cs).
@export var passive_id: String = ""
@export var passive_name: String = ""
@export var passive_description: String = ""

# Generic numeric dials consumed by the specific PassiveAbility named by PassiveId —
# meaning differs per passive (e.g. a fraction, a flat amount, a duration); see each
# PassiveAbility subclass's doc comment for what A/B mean for that Hunter.
@export var passive_value_a: float = 0.0
@export var passive_value_b: float = 0.0

@export var difficulty_rating: int = 1
