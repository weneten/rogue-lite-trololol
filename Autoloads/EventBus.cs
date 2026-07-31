using Godot;

namespace Nightbane.Autoloads;

/// <summary>
/// Global signal hub. Every gameplay system communicates through here instead of
/// holding direct references to each other, keeping Player/Enemies/UI/Waves decoupled.
/// Registered as an autoload singleton (see project.godot [autoload]).
/// </summary>
public partial class EventBus : Node
{
    public static EventBus Instance { get; private set; }

    [Signal]
    public delegate void OnEnemyKilledEventHandler(Node enemy, int currencyReward, int experienceReward);

    [Signal]
    public delegate void OnWaveStartEventHandler(int waveNumber);

    [Signal]
    public delegate void OnWaveEndEventHandler(int waveNumber);

    [Signal]
    public delegate void OnPlayerLevelUpEventHandler(int newLevel);

    [Signal]
    public delegate void OnItemPickedUpEventHandler(string itemId);

    [Signal]
    public delegate void OnPlayerDamagedEventHandler(float damageAmount, float currentHealth);

    /// <summary>Raised on every player HP change (damage/heal/max-HP upgrade), forwarded by Player.cs
    /// from its HealthComponent so HUD never needs a direct scene reference.</summary>
    [Signal]
    public delegate void OnPlayerHealthChangedEventHandler(int currentHealth, int maxHealth);

    /// <summary>Raised whenever the player's banked XP or level changes (gem pickup or level-up). HUD's XP bar listens here.</summary>
    [Signal]
    public delegate void OnXpChangedEventHandler(int currentXp, int xpToNextLevel, int level);

    /// <summary>Raised whenever GameManager's currency total changes. HUD's currency display listens here.</summary>
    [Signal]
    public delegate void OnCurrencyChangedEventHandler(int currentCurrency);

    [Signal]
    public delegate void OnPlayerDiedEventHandler();

    /// <summary>Raised whenever a player weapon lands a hit, carrying the final damage dealt and the
    /// target hit. Feeds character passives (lifesteal, on-hit DoT, etc.) via PlayerStats.NotifyDamageDealt;
    /// broadcast on EventBus too so future systems (damage numbers, combat log) can listen without
    /// touching PlayerStats directly.</summary>
    [Signal]
    public delegate void OnPlayerDamageDealtEventHandler(Node target, int amount);

    /// <summary>Raised by BossManager when a boss is spawned. Carries display name and trigger wave.</summary>
    [Signal]
    public delegate void OnBossEncounterStartEventHandler(string bossName, int waveNumber);

    /// <summary>Raised when a boss fight ends (boss death or run fail). defeated=true if boss was killed.</summary>
    [Signal]
    public delegate void OnBossEncounterEndEventHandler(string bossName, bool defeated);

    public override void _EnterTree()
    {
        // Assigned in _EnterTree (before other autoloads' _Ready runs) so any autoload
        // or scene listening to EventBus.Instance during _Ready can rely on it existing.
        Instance = this;
    }

    public override void _ExitTree()
    {
        if (Instance == this)
        {
            Instance = null;
        }
    }
}
