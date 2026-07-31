using System.Collections.Generic;
using Godot;
using Nightbane.Resources;
using Nightbane.Shop;

namespace Nightbane.Autoloads;

/// <summary>
/// Owns per-run state: Grave Coin (the run's currency), current wave, owned passive shop items,
/// and the RNG seed for the run. Reacts to EventBus signals rather than being polled by other systems.
/// </summary>
public partial class GameManager : Node
{
    public static GameManager Instance { get; private set; }

    /// <summary>Grave Coin balance. Earned from enemy kills (OnEnemyKilled) and an end-of-wave
    /// bonus (OnWaveEnd); spent in the shop on weapons/passives via TrySpendCurrency.</summary>
    [Export] public int Currency { get; private set; } = 0;
    [Export] public int WaveNumber { get; private set; } = 1;

    public ulong RunSeed { get; private set; }

    /// <summary>Hunter chosen at CharacterSelect; Player.ApplyCharacterData reads this at run start.
    /// Persists across StartNewRun (re-picking a character is an explicit CharacterSelect visit,
    /// not something a fresh run should silently clear).</summary>
    public CharacterData SelectedCharacter { get; set; }

    /// <summary>Ids of PassiveItemData already purchased this run, so ShopUI doesn't re-offer them.</summary>
    private readonly List<string> _ownedPassiveItemIds = new();

    public override void _EnterTree()
    {
        Instance = this;
    }

    public override void _Ready()
    {
        RunSeed = GD.Randi();

        EventBus.Instance.OnEnemyKilled += OnEnemyKilled;
        EventBus.Instance.OnWaveStart += OnWaveStart;
        EventBus.Instance.OnWaveEnd += OnWaveEnd;
        EventBus.Instance.OnPlayerDied += OnPlayerDied;
    }

    private void OnEnemyKilled(Node enemy, int currencyReward, int experienceReward)
    {
        // XP is no longer auto-granted here: it's now owned by PlayerStats and only banked once
        // the player actually collects the XpGem the kill drops (see XpGemSpawner/XpGem).
        AddCurrency(currencyReward);
    }

    private void OnWaveStart(int waveNumber)
    {
        WaveNumber = waveNumber;
    }

    private void OnWaveEnd(int waveNumber)
    {
        // Rewards clearing the wave itself, on top of whatever was earned killing enemies during it.
        AddCurrency(ShopEconomy.GetWaveEndBonus(waveNumber));
    }

    public bool IsPassiveItemOwned(string passiveId) => _ownedPassiveItemIds.Contains(passiveId);

    public void RegisterPassiveItemOwned(string passiveId)
    {
        if (!string.IsNullOrEmpty(passiveId) && !_ownedPassiveItemIds.Contains(passiveId))
        {
            _ownedPassiveItemIds.Add(passiveId);
        }
    }

    private void OnPlayerDied()
    {
        // Stage stub: full run-end / game-over flow (stats screen, meta-currency payout)
        // will be implemented once the UI/Shop stage exists.
        GD.Print($"[GameManager] Run ended on wave {WaveNumber} with {Currency} currency.");
    }

    public void AddCurrency(int amount)
    {
        Currency = Mathf.Max(0, Currency + amount);
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnCurrencyChanged, Currency);
    }

    public bool TrySpendCurrency(int amount)
    {
        if (amount < 0 || Currency < amount)
        {
            return false;
        }

        Currency -= amount;
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnCurrencyChanged, Currency);
        return true;
    }

    /// <summary>Resets state for a fresh run. Pass 0 to roll a new random seed.</summary>
    public void StartNewRun(ulong seed = 0)
    {
        Currency = 0;
        WaveNumber = 1;
        RunSeed = seed == 0 ? GD.Randi() : seed;
        _ownedPassiveItemIds.Clear();
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnCurrencyChanged, Currency);
    }
}
