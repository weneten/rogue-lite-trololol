using Godot;

namespace Nightbane.Resources;

/// <summary>
/// Data-driven definition of the enemy spawn pool WaveManager draws from and the formulas it
/// scales per-wave. One WaveData can serve indefinitely — WaveManager keeps advancing
/// CurrentWave and re-evaluating the growth formulas rather than requiring one resource per wave.
/// </summary>
[GlobalClass]
public partial class WaveData : Resource
{
    /// <summary>Enemy archetypes this wave can spawn. Selection is weighted by EnemyData.SpawnWeight
    /// and filtered by EnemyData.MinWaveToAppear.</summary>
    [Export] public EnemyData[] EnemyPool { get; set; } = System.Array.Empty<EnemyData>();

    [ExportGroup("Timing")]
    [Export(PropertyHint.Range, "20,90,1")] public float BaseDuration { get; set; } = 30f;
    /// <summary>Seconds added to BaseDuration per wave past the first, before the 20-90s clamp.</summary>
    [Export] public float DurationGrowthPerWave { get; set; } = 2f;
    [Export] public float SpawnInterval { get; set; } = 1.2f;

    [ExportGroup("Count Scaling")]
    [Export] public int BaseEnemyCount { get; set; } = 5;
    [Export] public float EnemyCountGrowthPerWave { get; set; } = 1.5f;
}
