using Godot;

namespace Nightbane.AI;

/// <summary>
/// Pure wave-number → multiplier helpers for regular enemy spawns. Isolated so WaveManager /
/// balancing passes can retune curves without touching AI or resource definitions.
/// Elite roll + elite multipliers live here too so spawn-site code stays a thin call site.
/// </summary>
public static class EnemyScaling
{
    /// <summary>HP grows ~12% per wave past wave 1 (wave 1 = 1.0x).</summary>
    public static float HealthMultiplier(int waveNumber)
    {
        int wavesPastFirst = Mathf.Max(0, waveNumber - 1);
        return 1f + wavesPastFirst * 0.12f;
    }

    /// <summary>Damage grows ~8% per wave past wave 1.</summary>
    public static float DamageMultiplier(int waveNumber)
    {
        int wavesPastFirst = Mathf.Max(0, waveNumber - 1);
        return 1f + wavesPastFirst * 0.08f;
    }

    /// <summary>Speed grows slowly (~3%/wave) so late packs stay readable.</summary>
    public static float SpeedMultiplier(int waveNumber)
    {
        int wavesPastFirst = Mathf.Max(0, waveNumber - 1);
        return 1f + wavesPastFirst * 0.03f;
    }

    /// <summary>Elites start appearing at wave 4; chance caps at 25%.</summary>
    public static float EliteChance(int waveNumber)
    {
        if (waveNumber < 4)
        {
            return 0f;
        }

        return Mathf.Min(0.25f, 0.04f + (waveNumber - 4) * 0.02f);
    }

    public static bool RollElite(int waveNumber)
    {
        float chance = EliteChance(waveNumber);
        return chance > 0f && GD.Randf() < chance;
    }

    public const float EliteHealthMultiplier = 1.8f;
    public const float EliteDamageMultiplier = 1.45f;
    public const float EliteSpeedMultiplier = 1.12f;
}
