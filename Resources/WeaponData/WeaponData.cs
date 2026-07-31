using Godot;

namespace Nightbane.Resources;

/// <summary>Rarity tier shown on the weapon's UI frame; also feeds shop pricing/drop tables later.</summary>
public enum RarityTier
{
    Common,
    Uncommon,
    Rare,
    Epic,
    Legendary
}

/// <summary>
/// Bitmask categorisation of a weapon. Flags (not a plain enum) because a weapon can be
/// more than one thing at once, e.g. a Holy Firearm or a Cursed Melee weapon — Weapon.cs
/// branches its attack behaviour (melee hitbox vs. projectile spawn) off the Melee bit.
/// </summary>
[System.Flags]
public enum WeaponClass
{
    None = 0,
    Melee = 1 << 0,
    Ranged = 1 << 1,
    Firearm = 1 << 2,
    Magic = 1 << 3,
    Holy = 1 << 4,
    Cursed = 1 << 5,
    AoE = 1 << 6,
    Summon = 1 << 7,
    /// <summary>Placed hazard (Iron Bear Trap): Weapon.cs drops a Trap.tscn instead of attacking
    /// directly; the trap itself deals the damage/root once a target walks over it.</summary>
    Trap = 1 << 8
}

/// <summary>Data-driven definition for a weapon: stats + the scene(s) it spawns/attaches.</summary>
[GlobalClass]
public partial class WeaponData : Resource
{
    [Export] public string Name { get; set; } = "Unnamed Weapon";
    [Export] public Texture2D Icon { get; set; }

    /// <summary>
    /// For Ranged/Firearm/Magic weapons: the pooled projectile scene Weapon.cs spawns.
    /// Unused for pure Melee weapons (they hit via an Area2D hitbox instead).
    /// </summary>
    [Export] public PackedScene ProjectileScene { get; set; }

    [ExportGroup("Combat Stats")]
    [Export] public float Damage { get; set; } = 10f;
    /// <summary>Attacks per second. Weapon.cs cooldown = 1 / AttackSpeed.</summary>
    [Export] public float AttackSpeed { get; set; } = 1.0f;
    [Export] public float Range { get; set; } = 100f;
    [Export(PropertyHint.Range, "0,1,0.01")] public float CritChance { get; set; } = 0.05f;
    [Export(PropertyHint.Range, "1,5,0.1")] public float CritMultiplier { get; set; } = 2.0f;
    /// <summary>How many projectiles fired per shot (Ranged/Firearm/Magic only). Melee ignores this.</summary>
    [Export(PropertyHint.Range, "1,12,1")] public int ProjectileCount { get; set; } = 1;
    /// <summary>Total spread angle in degrees across which ProjectileCount projectiles fan out.</summary>
    [Export] public float Spread { get; set; } = 0f;
    [Export] public float Knockback { get; set; } = 0f;

    [ExportGroup("Classification")]
    [Export] public RarityTier RarityTier { get; set; } = RarityTier.Common;
    [Export(PropertyHint.Flags, "Melee,Ranged,Firearm,Magic,Holy,Cursed,AoE,Summon,Trap")]
    public WeaponClass WeaponClass { get; set; } = WeaponClass.Melee;

    /// <summary>Optional tiered-up version of this weapon (e.g. Flintlock Pistol -> Hexed Revolver
    /// -> Cathedral Rifle). Not auto-applied by anything yet in this stage — it's the data hook a
    /// future fusion/evolution shop feature reads to know what a weapon becomes.</summary>
    [Export] public WeaponData UpgradesTo { get; set; }

    [ExportGroup("Magic Scaling")]
    /// <summary>Only relevant for WeaponClass.Magic. Extra multiplier applied on top of
    /// PlayerStats.MagicDamageMultiplier: final = 1 + MagicScalingPerPoint * (magicStat - 1).
    /// A pure melee/firearm weapon leaves this at 0 and is untouched by the Magic stat.</summary>
    [Export] public float MagicScalingPerPoint { get; set; } = 0f;

    [ExportGroup("Cursed Scaling")]
    /// <summary>Only relevant for WeaponClass.Cursed. Extra damage multiplier scaling with the
    /// wielder's missing HP fraction: final = 1 + CursedMissingHpScaling * missingHpFraction.
    /// A full-HP wielder gets no bonus; a near-death wielder hits much harder.</summary>
    [Export] public float CursedMissingHpScaling { get; set; } = 0f;

    [ExportGroup("Area Effect")]
    /// <summary>Only relevant for WeaponClass.AoE (and not Melee, which cleaves via its hitbox
    /// instead). Radius of the burst; falls back to Range when left at 0.</summary>
    [Export] public float AoERadius { get; set; } = 0f;
    /// <summary>True = burst centered on the wielder (Bell of Judgement's screen-wide pulse);
    /// false = centered on the current target (a thrown Firebomb/Holy Water Flask's impact point).</summary>
    [Export] public bool AoECenteredOnSelf { get; set; } = false;
    /// <summary>Movement-speed multiplier applied to anything the AoE hits, e.g. 0.4 = slowed to
    /// 40% speed (Frost Lantern). 0 (default) = no slow effect at all.</summary>
    [Export(PropertyHint.Range, "0,1,0.01")] public float SlowMultiplier { get; set; } = 0f;
    [Export] public float SlowDurationSeconds { get; set; } = 0f;

    [ExportGroup("Summon")]
    /// <summary>Only relevant for WeaponClass.Summon. Independent Familiar.tscn (or compatible)
    /// scene spawned once when this Weapon node is created; it fights on its own from then on and
    /// this Weapon node stops doing anything else (see Weapon._Process's Summon early-out).</summary>
    [Export] public PackedScene SummonScene { get; set; }

    [ExportGroup("Trap")]
    /// <summary>Only relevant for WeaponClass.Trap. Pooled Trap.tscn (or compatible) scene dropped
    /// at the wielder's feet on cooldown expiry.</summary>
    [Export] public PackedScene TrapScene { get; set; }
    [Export] public float TrapRootDurationSeconds { get; set; } = 1.5f;
    /// <summary>How long an armed-but-untriggered trap waits before despawning back to the pool.</summary>
    [Export] public float TrapLifetimeSeconds { get; set; } = 12f;

    [ExportGroup("On-Hit")]
    /// <summary>Fraction of damage dealt by THIS weapon healed back to the wielder immediately
    /// (Vampiric Claws). Independent of PlayerStats.LifestealFraction, which is the character-wide
    /// passive version — the two stack additively.</summary>
    [Export(PropertyHint.Range, "0,1,0.01")] public float OnHitLifestealFraction { get; set; } = 0f;

    [ExportGroup("Meta")]
    [Export(PropertyHint.Range, "1,5,1")] public int ShopCost { get; set; } = 10;
}
