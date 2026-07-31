using Godot;
using Nightbane.Autoloads;
using Nightbane.Combat;
using Nightbane.PlayerCharacter.Passives;

namespace Nightbane.PlayerCharacter;

/// <summary>
/// Owns the player's XP/level progression, the additive stat bonuses granted by level-up
/// upgrades and shop passives (see LevelUpUI/ShopUI), and the Hunter-specific bonuses applied
/// from CharacterData at run start (see Player.ApplyCharacterData). Lives as a child node of the
/// Player scene rather than an autoload (only one Player exists per run) but is still exposed via
/// a scene-lifetime Instance singleton, mirroring the EventBus/GameManager pattern, so
/// Weapon/HUD/LevelUpUI/passives can reach it without a direct scene reference.
/// </summary>
public partial class PlayerStats : Node
{
    public static PlayerStats Instance { get; private set; }

    [ExportGroup("Wiring")]
    [Export] public NodePath HealthComponentPath { get; set; }

    [ExportGroup("XP Curve")]
    /// <summary>XP required for level 1 -> 2 (before growth). Ghoul ≈ 3 XP, so ~4 kills early.</summary>
    [Export] public int BaseXpToLevel { get; set; } = 12;
    /// <summary>Power-curve exponent in CalculateXpRequirement (base * level^growth).
    /// 1.0 = linear; ~1.25–1.3 = gentle mid/late climb; avoid &gt;1.5 (runaway). Sample with
    /// defaults (12, 1.28): L1=12, L5≈91, L10≈228, L20≈546 XP to next.</summary>
    [Export] public float XpGrowthPerLevel { get; set; } = 1.28f;

    /// <summary>Multiplies all Weapon damage; read by Weapon.cs. Starts at 1 (no bonus).</summary>
    public float DamageMultiplier { get; private set; } = 1f;
    /// <summary>Multiplies Player.MoveSpeed; read by Player.cs. Starts at 1 (no bonus).</summary>
    public float MoveSpeedMultiplier { get; private set; } = 1f;
    /// <summary>Multiplies Weapon.AttackSpeed (attacks/sec) before the cooldown is derived from it;
    /// read by Weapon.cs. Driven by the Moonlit Duelist's dual-wield passive. Starts at 1.</summary>
    public float AttackSpeedMultiplier { get; private set; } = 1f;
    /// <summary>Added flat on top of WeaponData.CritChance when a Weapon rolls a crit. Starts at 0.</summary>
    public float ExtraCritChance { get; private set; } = 0f;
    /// <summary>Added flat on top of WeaponData.CritMultiplier for crit hits. Starts at 0.</summary>
    public float ExtraCritMultiplier { get; private set; } = 0f;
    /// <summary>Fraction of damage dealt returned as healing; applied in NotifyDamageDealt. Starts at 0.</summary>
    public float LifestealFraction { get; private set; } = 0f;
    /// <summary>Multiplies damage dealt to EnemyData.IsUndead targets. Starts at 1 (no bonus).</summary>
    public float UndeadDamageMultiplier { get; private set; } = 1f;
    /// <summary>Multiplies damage dealt by WeaponClass.Magic weapons only. Starts at 1 (no bonus).</summary>
    public float MagicDamageMultiplier { get; private set; } = 1f;
    /// <summary>Multiplies incoming damage before Armor is applied; mirrored onto HealthComponent so
    /// the reduction actually takes effect regardless of who calls TakeDamage. Starts at 1 (no change).</summary>
    public float DamageTakenMultiplier { get; private set; } = 1f;

    /// <summary>The selected Hunter's unique passive, if any (set by Player.ApplyCharacterData right
    /// after spawning it). Hooked here rather than in Player so Weapon can reach OnDamageDealt via
    /// the same reference it already holds for damage-multiplier lookups.</summary>
    public PassiveAbility ActivePassive { get; set; }

    public int Level { get; private set; } = 1;
    public int CurrentXp { get; private set; } = 0;
    public int XpToNextLevel => CalculateXpRequirement(Level, BaseXpToLevel, XpGrowthPerLevel);

    private HealthComponent _health;
    /// <summary>Tracks how much of DamageMultiplier currently comes from CurseLiftScalingPassive's
    /// ramp so each frame's SetCurseDamageBonus call can apply just the delta instead of stacking.</summary>
    private float _curseDamageBonusApplied = 0f;

    public override void _Ready()
    {
        Instance = this;
        _health = GetNodeOrNull<HealthComponent>(HealthComponentPath);

        if (_health != null)
        {
            _health.Damaged += (amount, source) => ActivePassive?.OnDamageTaken(amount, source);
        }

        if (EventBus.Instance != null)
        {
            // Single-player game: every enemy death is a player kill, so this is safe to forward
            // unconditionally rather than checking the kill's source.
            EventBus.Instance.OnEnemyKilled += (enemy, currencyReward, experienceReward) => ActivePassive?.OnEnemyKilled(enemy);
        }
    }

    public override void _ExitTree()
    {
        if (Instance == this)
        {
            Instance = null;
        }
    }

    /// <summary>
    /// Pure XP-curve formula (no instance state): requirement = baseXp * level^growthRate.
    /// Soft power curve — not pure exponential (would be growth^level). Tune BaseXpToLevel /
    /// XpGrowthPerLevel only; leave this method alone.
    /// TODO: re-check mid/late pace once EnemyScaling + wave density settle (Enemy roster owns those).
    /// </summary>
    public static int CalculateXpRequirement(int level, int baseXp, float growthRate)
    {
        return Mathf.Max(1, Mathf.RoundToInt(baseXp * Mathf.Pow(Mathf.Max(1, level), growthRate)));
    }

    /// <summary>Called by XpGem on pickup. Banks XP and triggers a level-up (pausing the run) once enough has been earned.</summary>
    public void AddXp(int amount)
    {
        if (amount <= 0)
        {
            return;
        }

        CurrentXp += amount;
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnXpChanged, CurrentXp, XpToNextLevel, Level);
        TryLevelUp();
    }

    private void TryLevelUp()
    {
        if (CurrentXp < XpToNextLevel)
        {
            return;
        }

        CurrentXp -= XpToNextLevel;
        Level++;

        // Brief pause while the level-up choice screen is up; the tree resumes via
        // ConfirmUpgradeSelected() once LevelUpUI reports a choice was made.
        GetTree().Paused = true;

        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnXpChanged, CurrentXp, XpToNextLevel, Level);
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnPlayerLevelUp, Level);
    }

    /// <summary>
    /// Called by LevelUpUI once the player has picked an upgrade. Resumes gameplay — unless the
    /// XP already banked covers the next level too (a big multi-gem pickup), in which case another
    /// level-up screen is triggered immediately instead of actually unpausing.
    /// </summary>
    public void ConfirmUpgradeSelected()
    {
        if (CurrentXp >= XpToNextLevel)
        {
            TryLevelUp();
        }
        else
        {
            GetTree().Paused = false;
        }
    }

    public void ApplyDamageUpgrade(float multiplierIncrease) => DamageMultiplier += multiplierIncrease;

    public void ApplyMoveSpeedUpgrade(float multiplierIncrease) => MoveSpeedMultiplier += multiplierIncrease;

    public void ApplyMaxHealthUpgrade(int amount) => _health?.IncreaseMaxHealth(amount);

    public void ApplyAttackSpeedBonus(float multiplierIncrease) => AttackSpeedMultiplier += multiplierIncrease;

    public void ApplyExtraCrit(float chanceIncrease, float multiplierIncrease)
    {
        ExtraCritChance += chanceIncrease;
        ExtraCritMultiplier += multiplierIncrease;
    }

    public void ApplyLifesteal(float fractionIncrease) => LifestealFraction += fractionIncrease;

    public void ApplyUndeadDamageBonus(float multiplierIncrease) => UndeadDamageMultiplier += multiplierIncrease;

    public void SetMagicDamageMultiplier(float value) => MagicDamageMultiplier = value;

    /// <summary>Increases DamageTakenMultiplier and mirrors it onto HealthComponent immediately —
    /// used by the Reaper's HP-for-damage tradeoff (more damage dealt, more damage taken).</summary>
    public void ApplyIncomingDamageMultiplier(float increase)
    {
        DamageTakenMultiplier += increase;
        if (_health != null)
        {
            _health.IncomingDamageMultiplier = DamageTakenMultiplier;
        }
    }

    /// <summary>Sets the Cursed Noble's ramping damage bonus to an absolute total each frame,
    /// applying only the delta to DamageMultiplier so repeated calls never over-stack.</summary>
    public void SetCurseDamageBonus(float totalBonus)
    {
        DamageMultiplier += totalBonus - _curseDamageBonusApplied;
        _curseDamageBonusApplied = totalBonus;
    }

    /// <summary>Called by Weapon.cs after every landed hit. Applies lifesteal, broadcasts
    /// EventBus.OnPlayerDamageDealt, and forwards to the active passive's OnDamageDealt hook.</summary>
    public void NotifyDamageDealt(int amount, Node target)
    {
        if (LifestealFraction > 0f)
        {
            _health?.Heal(Mathf.RoundToInt(amount * LifestealFraction));
        }

        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnPlayerDamageDealt, target, amount);
        ActivePassive?.OnDamageDealt(amount, target);
    }
}
