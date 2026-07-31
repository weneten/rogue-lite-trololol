using System.Collections.Generic;
using Godot;
using Nightbane.Combat;

namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Pyromancer — every hit sets the target alight: on each weapon hit, applies (or refreshes,
/// non-stacking) a burn on the target dealing PassiveValueA * hitDamage per tick, once per second,
/// for PassiveValueB seconds. Ticked in _Process rather than relying on any single Weapon instance
/// so the burn keeps running between attacks and across whichever weapon last tagged the target.
/// </summary>
public partial class FireDotPassive : PassiveAbility
{
    private class Burn
    {
        public HealthComponent Target;
        public double TimeRemaining;
        public double TickTimer;
        public int TickDamage;
    }

    private const double TickInterval = 1.0;
    private readonly List<Burn> _activeBurns = new();

    public override void OnDamageDealt(int amount, Node target)
    {
        HealthComponent health = ResolveHealth(target);
        if (health == null || health.IsDead)
        {
            return;
        }

        int tickDamage = Mathf.Max(1, Mathf.RoundToInt(amount * Data.PassiveValueA));
        double duration = Data.PassiveValueB > 0 ? Data.PassiveValueB : 3.0;

        Burn existing = _activeBurns.Find(b => b.Target == health);
        if (existing != null)
        {
            // Refresh rather than stack: repeatedly hitting the same target extends the burn
            // instead of piling up multiple simultaneous DoT instances on it.
            existing.TimeRemaining = duration;
            existing.TickDamage = tickDamage;
        }
        else
        {
            _activeBurns.Add(new Burn { Target = health, TimeRemaining = duration, TickTimer = TickInterval, TickDamage = tickDamage });
        }
    }

    public override void _Process(double delta)
    {
        for (int i = _activeBurns.Count - 1; i >= 0; i--)
        {
            Burn burn = _activeBurns[i];
            if (burn.Target == null || !GodotObject.IsInstanceValid(burn.Target) || burn.Target.IsDead)
            {
                _activeBurns.RemoveAt(i);
                continue;
            }

            burn.TimeRemaining -= delta;
            burn.TickTimer -= delta;
            if (burn.TickTimer <= 0)
            {
                burn.Target.TakeDamage(burn.TickDamage, Owner);
                burn.TickTimer += TickInterval;
            }

            if (burn.TimeRemaining <= 0)
            {
                _activeBurns.RemoveAt(i);
            }
        }
    }

    private static HealthComponent ResolveHealth(Node target)
    {
        return target as HealthComponent ?? target?.GetNodeOrNull<HealthComponent>("HealthComponent");
    }
}
