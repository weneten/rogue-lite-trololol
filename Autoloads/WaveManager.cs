using Godot;
using Nightbane.AI;
using Nightbane.Core;
using Nightbane.Resources;

namespace Nightbane.Autoloads;

/// <summary>
/// Drives the timed enemy-wave loop: after an initial delay it repeatedly starts a wave,
/// trickles enemies out of a single shared ObjectPool&lt;Enemy&gt; (the generic Enemy.tscn,
/// re-initialized per spawn with whatever EnemyData the weighted roll picks) around the
/// player, ends the wave once its duration elapses, waits TimeBetweenWaves, then repeats
/// with WaveData's growth formulas making each wave longer/bigger (clamped to 20-90s).
/// </summary>
public partial class WaveManager : Node
{
    public static WaveManager Instance { get; private set; }

    [Export] public int CurrentWave { get; private set; } = 0;
    [Export] public float TimeBetweenWaves { get; set; } = 5.0f;
    [Export] public bool IsWaveActive { get; private set; } = false;

    /// <summary>
    /// When true, ProcessActiveWave skips enemy spawns (wave timer still runs).
    /// BossManager sets this for the duration of a boss encounter.
    /// </summary>
    public bool SpawnsPaused { get; set; }

    [ExportGroup("Configuration")]
    /// <summary>Generic enemy scene all archetypes share. Falls back to Enemy.tscn if left unassigned (autoloads can't be edited in the Inspector as a scene).</summary>
    [Export] public PackedScene EnemyScene { get; set; }
    /// <summary>Enemy pool + wave-scaling formulas. Falls back to StandardWave.tres if unassigned.</summary>
    [Export] public WaveData WaveDefinition { get; set; }
    [Export] public int EnemyPoolPrewarm { get; set; } = 10;
    [Export] public float InitialDelaySeconds { get; set; } = 3.0f;
    /// <summary>Ring radius around the player that enemies spawn on (just off-screen, Brotato-style).</summary>
    [Export] public float SpawnRadius { get; set; } = 650f;

    private ObjectPool<Enemy> _enemyPool;

    private double _waveTimeRemaining;
    private double _spawnTimeRemaining;
    private double _interWaveTimeRemaining;
    private int _enemiesToSpawnThisWave;
    private int _enemiesSpawnedThisWave;

    /// <summary>Seconds left in the active wave. HUD reads this for its countdown display.</summary>
    public double WaveTimeRemaining => _waveTimeRemaining;
    /// <summary>Seconds until the next wave starts, while between waves.</summary>
    public double TimeUntilNextWave => _interWaveTimeRemaining;

    public override void _EnterTree()
    {
        Instance = this;
    }

    public override void _Ready()
    {
        // Autoloads are instantiated from their script directly (see project.godot), not from a
        // scene, so Inspector-assigned defaults aren't available here — lazily load the stage's
        // authored defaults instead, while still letting a future scene-based autoload override them.
        EnemyScene ??= GD.Load<PackedScene>("res://Scenes/Enemies/Enemy.tscn");
        WaveDefinition ??= GD.Load<WaveData>("res://Resources/WaveData/Data/StandardWave.tres");

        _interWaveTimeRemaining = InitialDelaySeconds;
    }

    public override void _Process(double delta)
    {
        if (WaveDefinition == null || EnemyScene == null)
        {
            return;
        }

        // Built lazily (rather than in _Ready) so GetTree().CurrentScene is guaranteed to be the
        // actual gameplay scene rather than whatever was loading when this autoload first ran.
        _enemyPool ??= new ObjectPool<Enemy>(EnemyScene, GetTree().CurrentScene ?? this, EnemyPoolPrewarm);

        if (IsWaveActive)
        {
            ProcessActiveWave(delta);
        }
        else if (_interWaveTimeRemaining > 0)
        {
            _interWaveTimeRemaining -= delta;
            if (_interWaveTimeRemaining <= 0)
            {
                StartNextWave();
            }
        }
    }

    private void ProcessActiveWave(double delta)
    {
        _waveTimeRemaining -= delta;

        if (!SpawnsPaused && _enemiesSpawnedThisWave < _enemiesToSpawnThisWave)
        {
            _spawnTimeRemaining -= delta;
            if (_spawnTimeRemaining <= 0)
            {
                SpawnRandomEnemy();
                _enemiesSpawnedThisWave++;
                _spawnTimeRemaining = WaveDefinition.SpawnInterval;
            }
        }

        if (_waveTimeRemaining <= 0)
        {
            EndWave();
            _interWaveTimeRemaining = TimeBetweenWaves;
        }
    }

    public void StartNextWave()
    {
        CurrentWave++;
        IsWaveActive = true;

        // Duration/count grow linearly with wave number but are clamped to the designer-specified
        // 20-90s band so late waves stay bounded instead of spawning forever.
        _waveTimeRemaining = Mathf.Clamp(
            WaveDefinition.BaseDuration + WaveDefinition.DurationGrowthPerWave * (CurrentWave - 1),
            20f, 90f);
        _enemiesToSpawnThisWave = Mathf.Max(1, Mathf.RoundToInt(
            WaveDefinition.BaseEnemyCount + WaveDefinition.EnemyCountGrowthPerWave * (CurrentWave - 1)));
        _enemiesSpawnedThisWave = 0;
        _spawnTimeRemaining = 0; // spawn the first enemy of the wave immediately

        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnWaveStart, CurrentWave);
    }

    public void EndWave()
    {
        IsWaveActive = false;
        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnWaveEnd, CurrentWave);
    }

    private void SpawnRandomEnemy()
    {
        EnemyData data = SelectWeightedEnemy(WaveDefinition.EnemyPool, CurrentWave);
        if (data == null)
        {
            return;
        }

        Node2D player = GetTree().GetFirstNodeInGroup("Player") as Node2D;
        Vector2 origin = player?.GlobalPosition ?? Vector2.Zero;
        Vector2 spawnOffset = new Vector2(SpawnRadius, 0).Rotated((float)GD.RandRange(0.0, Mathf.Tau));

        Enemy enemy = _enemyPool.Get();
        enemy.GlobalPosition = origin + spawnOffset;
        enemy.Initialize(data, _enemyPool);
        // Wave curves + elite roll live in EnemyScaling; elite chance ramps from wave 4.
        enemy.ApplySpawnModifiers(CurrentWave, EnemyScaling.RollElite(CurrentWave));
    }

    /// <summary>Weighted-random pick over EnemyData.SpawnWeight, restricted to archetypes unlocked by MinWaveToAppear.</summary>
    private static EnemyData SelectWeightedEnemy(EnemyData[] pool, int waveNumber)
    {
        if (pool == null || pool.Length == 0)
        {
            return null;
        }

        float totalWeight = 0f;
        foreach (EnemyData candidate in pool)
        {
            if (candidate != null && candidate.MinWaveToAppear <= waveNumber)
            {
                totalWeight += Mathf.Max(0f, candidate.SpawnWeight);
            }
        }

        if (totalWeight <= 0f)
        {
            return null;
        }

        float roll = GD.Randf() * totalWeight;
        foreach (EnemyData candidate in pool)
        {
            if (candidate == null || candidate.MinWaveToAppear > waveNumber)
            {
                continue;
            }

            roll -= Mathf.Max(0f, candidate.SpawnWeight);
            if (roll <= 0f)
            {
                return candidate;
            }
        }

        return pool[^1];
    }
}
