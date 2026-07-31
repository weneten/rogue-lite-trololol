using Godot;

namespace Nightbane.Resources;

/// <summary>
/// Data-driven definition for a selectable Hunter (Brotato-style character sheet). CharacterSelect
/// lists every CharacterData it's given; picking one has Player.cs apply MaxHealth/MoveSpeed/Armor/
/// Dodge/Crit/Magic, equip StartingWeapons, and spawn the PassiveAbility named by PassiveId (see
/// Scripts/Player/Passives/PassiveAbilityFactory.cs) as a child node driving that Hunter's unique effect.
/// </summary>
[GlobalClass]
public partial class CharacterData : Resource
{
    [Export] public string CharacterName { get; set; } = "Unnamed Hunter";
    [Export(PropertyHint.MultilineText)] public string LoreBlurb { get; set; } = "";
    [Export] public Texture2D Portrait { get; set; }
    /// <summary>Unused by the current single Player.tscn flow (stage stub for a future per-Hunter
    /// scene/art swap) — reserved so this Resource shape doesn't need to change when that lands.</summary>
    [Export] public PackedScene CharacterScene { get; set; }

    [ExportGroup("Sprite")]
    /// <summary>Nightbane sprite sheet (PNG under Assets/sprites) driving both the in-game Player
    /// visual and the CharacterSelect preview. Prefer assigning the Texture2D as well as the path —
    /// path-only GD.Load can fail when import state is flaky (see SpriteSheetCache).
    /// Hunters without a sheet keep Player.tscn's fallback polygon.</summary>
    [Export] public Texture2D SpriteSheet { get; set; }
    [Export] public string SpriteSheetPath { get; set; } = "";
    /// <summary>Atlas JSON next to the sheet (frame size, per-animation frame indices, fps, origin).
    /// Empty falls back to the sheet path with a .json extension.</summary>
    [Export] public string SpriteJsonPath { get; set; } = "";
    [Export] public float SpriteScale { get; set; } = 1f;
    /// <summary>Animation played on attacks; falls back through SpriteSheetCache's known attack
    /// names when this sheet doesn't have it.</summary>
    [Export] public string AttackAnimName { get; set; } = "";

    [ExportGroup("Base Stats")]
    [Export] public int MaxHealth { get; set; } = 100;
    [Export] public float MoveSpeed { get; set; } = 300f;
    [Export] public int StartingArmor { get; set; } = 0;
    [Export(PropertyHint.Range, "0,1,0.01")] public float StartingDodgeChance { get; set; } = 0f;
    [Export(PropertyHint.Range, "0,1,0.01")] public float StartingCritChance { get; set; } = 0.05f;
    /// <summary>Baseline multiplier applied only to WeaponClass.Magic weapons (see PlayerStats.MagicDamageMultiplier).</summary>
    [Export] public float StartingMagicPower { get; set; } = 1f;
    /// <summary>Legacy stat carried over from the stage-6 stub; not yet consumed by any system
    /// (reserved for future loot-luck/drop-rarity tuning).</summary>
    [Export] public float StartingLuck { get; set; } = 0f;

    [ExportGroup("Loadout")]
    [Export] public WeaponData[] StartingWeapons { get; set; } = System.Array.Empty<WeaponData>();

    [ExportGroup("Passive Ability")]
    /// <summary>Key consumed by PassiveAbilityFactory to build the matching PassiveAbility subclass.
    /// Empty/unknown ids simply leave the Hunter without a passive (warned in Player.cs).</summary>
    [Export] public string PassiveId { get; set; } = "";
    [Export] public string PassiveName { get; set; } = "";
    [Export(PropertyHint.MultilineText)] public string PassiveDescription { get; set; } = "";
    /// <summary>Generic numeric dials consumed by the specific PassiveAbility named by PassiveId —
    /// meaning differs per passive (e.g. a fraction, a flat amount, a duration); see each
    /// PassiveAbility subclass's doc comment for what A/B mean for that Hunter.</summary>
    [Export] public float PassiveValueA { get; set; } = 0f;
    [Export] public float PassiveValueB { get; set; } = 0f;

    [ExportGroup("Meta")]
    [Export(PropertyHint.Range, "1,5,1")] public int DifficultyRating { get; set; } = 1;
}
