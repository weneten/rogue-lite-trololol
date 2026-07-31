using Godot;
using Nightbane.Autoloads;

namespace Nightbane.Meta;

/// <summary>
/// Per-run counters for the death/summary screen. Listens only to EventBus (additive, no
/// GameManager mutation). Reset at run start; finalize once on death or wave-20 clear.
/// </summary>
public partial class RunStats : Node
{
    public static RunStats Instance { get; private set; }

    /// <summary>Highest wave reached this run (from OnWaveStart).</summary>
    public int WavesSurvived { get; private set; }

    public int Kills { get; private set; }
    public int DamageDealt { get; private set; }

    /// <summary>Cumulative Grave Coin granted this run (from OnCurrencyChanged deltas).</summary>
    public int GoldEarned { get; private set; }

    public bool RunComplete { get; private set; }
    public bool IsFinalized { get; private set; }
    public int MetaCurrencyGranted { get; private set; }

    private int _lastCurrency;
    private bool _subscribed;

    public override void _EnterTree()
    {
        Instance = this;
    }

    public override void _Ready()
    {
        Subscribe();
        Reset();
    }

    public override void _ExitTree()
    {
        Unsubscribe();
        if (Instance == this)
        {
            Instance = null;
        }
    }

    public void Reset()
    {
        WavesSurvived = 0;
        Kills = 0;
        DamageDealt = 0;
        GoldEarned = 0;
        RunComplete = false;
        IsFinalized = false;
        MetaCurrencyGranted = 0;
        _lastCurrency = GameManager.Instance?.Currency ?? 0;
    }

    /// <summary>
    /// Compute + grant meta currency once. Safe to call multiple times (idempotent).
    /// </summary>
    public int FinalizeAndGrantMeta(bool runComplete)
    {
        if (IsFinalized)
        {
            return MetaCurrencyGranted;
        }

        RunComplete = runComplete;
        IsFinalized = true;

        // Base: 10 per wave + kill chip + gold drip; clear wave 20 for bonus.
        int payout = WavesSurvived * 10
            + Kills / 5
            + GoldEarned / 50
            + (runComplete ? 100 : 0);

        MetaCurrencyGranted = Mathf.Max(0, payout);
        if (MetaCurrencyGranted > 0)
        {
            MetaSave.AddMetaCurrency(MetaCurrencyGranted);
        }

        GD.Print($"[RunStats] Finalized. Waves={WavesSurvived} Kills={Kills} Dmg={DamageDealt} " +
                 $"Gold={GoldEarned} Complete={runComplete} Meta+={MetaCurrencyGranted}");
        return MetaCurrencyGranted;
    }

    public static int PreviewPayout(int waves, int kills, int gold, bool runComplete)
    {
        return Mathf.Max(0, waves * 10 + kills / 5 + gold / 50 + (runComplete ? 100 : 0));
    }

    private void Subscribe()
    {
        if (_subscribed || EventBus.Instance == null)
        {
            return;
        }

        EventBus.Instance.OnEnemyKilled += OnEnemyKilled;
        EventBus.Instance.OnPlayerDamageDealt += OnPlayerDamageDealt;
        EventBus.Instance.OnWaveStart += OnWaveStart;
        EventBus.Instance.OnWaveEnd += OnWaveEnd;
        EventBus.Instance.OnCurrencyChanged += OnCurrencyChanged;
        _subscribed = true;
    }

    private void Unsubscribe()
    {
        if (!_subscribed || EventBus.Instance == null)
        {
            _subscribed = false;
            return;
        }

        EventBus.Instance.OnEnemyKilled -= OnEnemyKilled;
        EventBus.Instance.OnPlayerDamageDealt -= OnPlayerDamageDealt;
        EventBus.Instance.OnWaveStart -= OnWaveStart;
        EventBus.Instance.OnWaveEnd -= OnWaveEnd;
        EventBus.Instance.OnCurrencyChanged -= OnCurrencyChanged;
        _subscribed = false;
    }

    private void OnEnemyKilled(Node enemy, int currencyReward, int experienceReward)
    {
        if (IsFinalized)
        {
            return;
        }

        Kills++;
    }

    private void OnPlayerDamageDealt(Node target, int amount)
    {
        if (IsFinalized || amount <= 0)
        {
            return;
        }

        DamageDealt += amount;
    }

    private void OnWaveStart(int waveNumber)
    {
        if (IsFinalized)
        {
            return;
        }

        WavesSurvived = Mathf.Max(WavesSurvived, waveNumber);
    }

    private void OnWaveEnd(int waveNumber)
    {
        if (IsFinalized)
        {
            return;
        }

        WavesSurvived = Mathf.Max(WavesSurvived, waveNumber);

        // Wave 20 clear = run victory. DeathScreen listens too; we only mark stats here.
        if (waveNumber >= 20)
        {
            RunComplete = true;
        }
    }

    private void OnCurrencyChanged(int currentCurrency)
    {
        if (IsFinalized)
        {
            return;
        }

        int delta = currentCurrency - _lastCurrency;
        if (delta > 0)
        {
            GoldEarned += delta;
        }

        _lastCurrency = currentCurrency;
    }
}
