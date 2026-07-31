using Godot;
using Nightbane.Combat;

namespace Nightbane.PlayerCharacter.Passives;

/// <summary>
/// Alchemist — lobs a corrosive vial at the nearest foe on a timer: every PassiveValueB seconds
/// (default 2.5s), deals PassiveValueA instant poison damage to the nearest live Enemy-group
/// target in the arena, independent of and in addition to her equipped weapons' own attacks.
/// </summary>
public partial class PotionThrowDebuffPassive : PassiveAbility
{
    private double _cooldownRemaining;

    protected override void OnInitialize()
    {
        _cooldownRemaining = ThrowInterval();
    }

    public override void _Process(double delta)
    {
        _cooldownRemaining -= delta;
        if (_cooldownRemaining > 0)
        {
            return;
        }

        _cooldownRemaining = ThrowInterval();

        Node2D target = FindNearestEnemy();
        HealthComponent health = target?.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health != null && !health.IsDead)
        {
            health.TakeDamage(Mathf.RoundToInt(Data.PassiveValueA), Owner);
        }
    }

    private double ThrowInterval() => Data.PassiveValueB > 0 ? Data.PassiveValueB : 2.5;

    /// <summary>Nearest live member of the "Enemy" group to the Player, or null if the arena is empty.</summary>
    private Node2D FindNearestEnemy()
    {
        if (Owner == null)
        {
            return null;
        }

        Node2D nearest = null;
        float nearestDistSq = float.MaxValue;
        Vector2 origin = Owner.GlobalPosition;

        foreach (Node node in Owner.GetTree().GetNodesInGroup("Enemy"))
        {
            if (node is not Node2D candidate)
            {
                continue;
            }

            HealthComponent health = candidate.GetNodeOrNull<HealthComponent>("HealthComponent");
            if (health != null && health.IsDead)
            {
                continue;
            }

            float distSq = origin.DistanceSquaredTo(candidate.GlobalPosition);
            if (distSq < nearestDistSq)
            {
                nearestDistSq = distSq;
                nearest = candidate;
            }
        }

        return nearest;
    }
}
