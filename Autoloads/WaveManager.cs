using Godot;
using Nightbane.AI;
using Nightbane.Core;
using Nightbane.Resources;

namespace Nightbane.Autoloads;

/// <summary>
/// Timed enemy-wave loop for Arena gameplay only. Autoload, but idle while no Player exists
/// (MainMenu/CharacterSelect) so the pool is never parented to the wrong scene.
/// Spawns on a ring around the player, clamped into arena bounds.
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
    [Export] public PackedScene EnemyScene { get; set; }
    [Export] public WaveData WaveDefinition { get; set; }
    [Export] public int EnemyPoolPrewarm { get; set; } = 10;
    [Export] public float InitialDelaySeconds { get; set; } = 2.0f;

    [ExportGroup("Spawn Ring")]
    /// <summary>Min distance from player for a spawn (on-screen but not on top of them).</summary>
    [Export] public float SpawnRadiusMin { get; set; } = 260f;
    /// <summary>Max distance from player for a spawn (inside camera / arena, not beyond walls).</summary>
    [Export] public float SpawnRadiusMax { get; set; } = 400f;

    [ExportGroup("Arena Bounds")]
    /// <summary>Half-width of playable area (matches Arena walls ~±800 with margin).</summary>
    [Export] public float ArenaHalfWidth { get; set; } = 760f;
    /// <summary>Half-height of playable area (matches Arena walls ~±500 with margin).</summary>
    [Export] public float ArenaHalfHeight { get; set; } = 460f;

    private ObjectPool<Enemy> _enemyPool;
    private Node _poolParent;

    private double _waveTimeRemaining;
    private double _spawnTimeRemaining;
    private double _interWaveTimeRemaining;
    private int _enemiesToSpawnThisWave;
    private int _enemiesSpawnedThisWave;
    private bool _gameplayActive;

    public double WaveTimeRemaining => _waveTimeRemaining;
    public double TimeUntilNextWave => _interWaveTimeRemaining;

    public override void _EnterTree()
    {
        Instance = this;
    }

    public override void _Ready()
    {
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

        // Only run the wave loop while a Player is in the tree (Arena). Prevents spawning into
        // MainMenu/CharacterSelect and avoids pool instances parented under a freed scene.
        Node2D player = GetTree()?.GetFirstNodeInGroup("Player") as Node2D;
        if (player == null || !GodotObject.IsInstanceValid(player))
        {
            if (_gameplayActive)
            {
                StopGameplay();
            }

            return;
        }

        if (!_gameplayActive)
        {
            BeginGameplay();
        }

        if (!EnsureEnemyPool())
        {
            return;
        }

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

    private void BeginGameplay()
    {
        _gameplayActive = true;
        CurrentWave = 0;
        IsWaveActive = false;
        SpawnsPaused = false;
        _enemiesSpawnedThisWave = 0;
        _enemiesToSpawnThisWave = 0;
        _waveTimeRemaining = 0;
        _interWaveTimeRemaining = InitialDelaySeconds;
        _enemyPool = null;
        _poolParent = null;
        GD.Print("[WaveManager] Gameplay started — wave loop armed.");
    }

    private void StopGameplay()
    {
        _gameplayActive = false;
        IsWaveActive = false;
        SpawnsPaused = false;
        _enemyPool = null;
        _poolParent = null;
        GD.Print("[WaveManager] Left gameplay — wave loop idle.");
    }

    private bool EnsureEnemyPool()
    {
        Node scene = GetTree()?.CurrentScene;
        if (scene == null || !GodotObject.IsInstanceValid(scene))
        {
            return false;
        }

        if (_enemyPool != null && _poolParent == scene && GodotObject.IsInstanceValid(_poolParent))
        {
            return true;
        }

        _poolParent = scene;
        _enemyPool = new ObjectPool<Enemy>(EnemyScene, scene, EnemyPoolPrewarm);
        return true;
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

        _waveTimeRemaining = Mathf.Clamp(
            WaveDefinition.BaseDuration + WaveDefinition.DurationGrowthPerWave * (CurrentWave - 1),
            20f, 90f);
        _enemiesToSpawnThisWave = Mathf.Max(1, Mathf.RoundToInt(
            WaveDefinition.BaseEnemyCount + WaveDefinition.EnemyCountGrowthPerWave * (CurrentWave - 1)));
        _enemiesSpawnedThisWave = 0;
        _spawnTimeRemaining = 0;

        EventBus.Instance?.EmitSignal(EventBus.SignalName.OnWaveStart, CurrentWave);
        GD.Print($"[WaveManager] Wave {CurrentWave} start — spawning {_enemiesToSpawnThisWave} enemies.");
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
            GD.PushWarning($"[WaveManager] No enemy in pool for wave {CurrentWave}.");
            return;
        }

        Node2D player = GetTree().GetFirstNodeInGroup("Player") as Node2D;
        Vector2 origin = player?.GlobalPosition ?? Vector2.Zero;
        Vector2 spawnPos = PickSpawnPosition(origin);

        Enemy enemy = _enemyPool.Get();
        enemy.GlobalPosition = spawnPos;
        enemy.Initialize(data, _enemyPool);
        enemy.ApplySpawnModifiers(CurrentWave, EnemyScaling.RollElite(CurrentWave));
    }

    /// <summary>
    /// Random point on a ring around the player, clamped into the arena so enemies never spawn
    /// outside walls (where they get stuck and never reach the player).
    /// </summary>
    private Vector2 PickSpawnPosition(Vector2 playerPos)
    {
        float minR = Mathf.Min(SpawnRadiusMin, SpawnRadiusMax);
        float maxR = Mathf.Max(SpawnRadiusMin, SpawnRadiusMax);

        for (int attempt = 0; attempt < 16; attempt++)
        {
            float angle = (float)GD.RandRange(0.0, Mathf.Tau);
            float dist = (float)GD.RandRange(minR, maxR);
            Vector2 candidate = playerPos + new Vector2(dist, 0f).Rotated(angle);
            candidate = ClampToArena(candidate);

            // Accept if still a bit away from the player after clamping.
            if (candidate.DistanceSquaredTo(playerPos) >= 120f * 120f)
            {
                return candidate;
            }
        }

        // Fallback: any clamped offset.
        float fallbackAngle = (float)GD.RandRange(0.0, Mathf.Tau);
        return ClampToArena(playerPos + new Vector2(220f, 0f).Rotated(fallbackAngle));
    }

    private Vector2 ClampToArena(Vector2 pos)
    {
        return new Vector2(
            Mathf.Clamp(pos.X, -ArenaHalfWidth, ArenaHalfWidth),
            Mathf.Clamp(pos.Y, -ArenaHalfHeight, ArenaHalfHeight));
    }

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

        // Last eligible entry (pool[^1] may be locked by MinWave).
        for (int i = pool.Length - 1; i >= 0; i--)
        {
            if (pool[i] != null && pool[i].MinWaveToAppear <= waveNumber)
            {
                return pool[i];
            }
        }

        return null;
    }
}
