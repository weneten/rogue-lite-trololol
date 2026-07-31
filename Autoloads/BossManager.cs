using Godot;
using Nightbane.Bosses;
using Nightbane.Resources;

namespace Nightbane.Autoloads;

/// <summary>
/// Spawns bosses when the matching wave starts. Self-subscribes to EventBus.OnWaveStart —
/// does NOT edit WaveManager trigger logic. Pauses normal wave spawns via WaveManager.SpawnsPaused
/// for the duration of the encounter.
/// </summary>
public partial class BossManager : Node
{
    public static BossManager Instance { get; private set; }

    /// <summary>True while a boss fight is live. Parallel systems may read this.</summary>
    public static bool IsBossActive { get; private set; }

    /// <summary>Roster of bosses. If empty at _Ready, loads the three default .tres definitions.</summary>
    [Export] public BossData[] BossRoster { get; set; }

    [Export] public float SpawnOffsetFromPlayer { get; set; } = 280f;

    private Boss _activeBoss;
    private BossData _activeData;
    private readonly System.Collections.Generic.HashSet<int> _triggeredWaves = new();

    public override void _EnterTree()
    {
        Instance = this;
    }

    public override void _Ready()
    {
        if (BossRoster == null || BossRoster.Length == 0)
        {
            BossRoster = new[]
            {
                GD.Load<BossData>("res://Resources/BossData/Data/BatWingedCount.tres"),
                GD.Load<BossData>("res://Resources/BossData/Data/GravekeeperColossus.tres"),
                GD.Load<BossData>("res://Resources/BossData/Data/HollowCardinal.tres")
            };
        }

        if (EventBus.Instance != null)
        {
            EventBus.Instance.OnWaveStart += OnWaveStart;
            EventBus.Instance.OnBossEncounterEnd += OnBossEncounterEnd;
            EventBus.Instance.OnPlayerDied += OnPlayerDied;
        }
    }

    public override void _ExitTree()
    {
        if (EventBus.Instance != null)
        {
            EventBus.Instance.OnWaveStart -= OnWaveStart;
            EventBus.Instance.OnBossEncounterEnd -= OnBossEncounterEnd;
            EventBus.Instance.OnPlayerDied -= OnPlayerDied;
        }

        if (Instance == this)
        {
            Instance = null;
        }
    }

    private void OnWaveStart(int waveNumber)
    {
        if (IsBossActive)
        {
            return;
        }

        // One trigger per wave number per run.
        if (_triggeredWaves.Contains(waveNumber))
        {
            return;
        }

        BossData match = FindBossForWave(waveNumber);
        if (match == null)
        {
            return;
        }

        _triggeredWaves.Add(waveNumber);
        SpawnBoss(match);
    }

    private BossData FindBossForWave(int waveNumber)
    {
        if (BossRoster == null)
        {
            return null;
        }

        foreach (BossData data in BossRoster)
        {
            if (data != null && data.WaveTrigger == waveNumber)
            {
                return data;
            }
        }

        return null;
    }

    public void SpawnBoss(BossData data)
    {
        if (data == null)
        {
            return;
        }

        if (data.BossScene == null)
        {
            GD.PushError($"[BossManager] BossData '{data.BossName}' has no BossScene.");
            return;
        }

        Node2D player = GetTree().GetFirstNodeInGroup("Player") as Node2D;
        Vector2 origin = player?.GlobalPosition ?? Vector2.Zero;
        Vector2 spawnPos = origin + new Vector2(SpawnOffsetFromPlayer, 0).Rotated((float)GD.RandRange(0.0, Mathf.Tau));

        Node instance = data.BossScene.Instantiate();
        Node parent = GetTree().CurrentScene ?? this;
        parent.AddChild(instance);

        if (instance is not Boss boss)
        {
            GD.PushError($"[BossManager] BossScene root is not a Boss: {data.BossScene.ResourcePath}");
            instance.QueueFree();
            return;
        }

        boss.GlobalPosition = spawnPos;
        boss.Initialize(data);

        _activeBoss = boss;
        _activeData = data;
        IsBossActive = true;

        if (WaveManager.Instance != null)
        {
            WaveManager.Instance.SpawnsPaused = true;
        }

        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnBossEncounterStart, data.BossName, data.WaveTrigger);
        GD.Print($"[BossManager] Spawned {data.BossName} on wave {data.WaveTrigger}.");
    }

    private void OnBossEncounterEnd(string bossName, bool defeated)
    {
        EndEncounter(defeated);
    }

    private void OnPlayerDied()
    {
        if (!IsBossActive)
        {
            return;
        }

        string name = _activeData?.BossName ?? "Boss";
        if (_activeBoss != null && GodotObject.IsInstanceValid(_activeBoss))
        {
            _activeBoss.QueueFree();
        }

        // Emit so listeners (audio/UI) can react; EndEncounter also runs via the handler.
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnBossEncounterEnd, name, false);
    }

    private void EndEncounter(bool defeated)
    {
        if (!IsBossActive && _activeBoss == null)
        {
            return;
        }

        IsBossActive = false;
        _activeBoss = null;
        _activeData = null;

        if (WaveManager.Instance != null)
        {
            WaveManager.Instance.SpawnsPaused = false;
        }

        GD.Print(defeated
            ? "[BossManager] Boss defeated — wave spawns resumed."
            : "[BossManager] Boss encounter ended (not defeated) — wave spawns resumed.");
    }

    /// <summary>Debug / tests: force a roster entry by wave trigger.</summary>
    public void DebugSpawnBossForWave(int waveNumber)
    {
        BossData data = FindBossForWave(waveNumber);
        if (data != null)
        {
            SpawnBoss(data);
        }
    }
}
