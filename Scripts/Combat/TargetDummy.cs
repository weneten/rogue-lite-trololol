using Godot;

namespace Nightbane.Combat;

/// <summary>
/// Stationary punching bag used to verify weapons actually land hits: logs every hit via
/// HealthComponent.Damaged and auto-resets its HP (instead of staying dead) so it can be
/// hit repeatedly during manual testing. Belongs to the "Enemy" group so Weapon.cs's
/// nearest-target search and Projectile.cs's overlap check both pick it up like a real enemy.
/// </summary>
public partial class TargetDummy : CharacterBody2D
{
    [Export] public NodePath HealthComponentPath { get; set; }
    [Export] public bool AutoResetOnDeath { get; set; } = true;
    [Export] public float ResetDelaySeconds { get; set; } = 1.5f;

    /// <summary>Knockback velocity applied by weapon hits, decayed each physics frame.</summary>
    [Export] public float KnockbackFriction { get; set; } = 900f;

    private HealthComponent _health;
    private Vector2 _knockbackVelocity = Vector2.Zero;

    public override void _Ready()
    {
        AddToGroup("Enemy");

        _health = GetNodeOrNull<HealthComponent>(HealthComponentPath);
        if (_health == null)
        {
            GD.PushWarning("[TargetDummy] HealthComponentPath not wired; dummy cannot take damage.");
            return;
        }

        _health.Damaged += OnDamaged;
        _health.Died += OnDied;
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_knockbackVelocity.LengthSquared() < 1f)
        {
            _knockbackVelocity = Vector2.Zero;
            return;
        }

        Velocity = _knockbackVelocity;
        MoveAndSlide();
        _knockbackVelocity = _knockbackVelocity.MoveToward(Vector2.Zero, KnockbackFriction * (float)delta);
    }

    /// <summary>Called by Weapon.cs (melee) and Projectile.cs (ranged) on a successful hit.</summary>
    public void ApplyKnockback(Vector2 impulse)
    {
        _knockbackVelocity += impulse;
    }

    private void OnDamaged(int amount, Node source)
    {
        GD.Print($"[TargetDummy] Hit for {amount} dmg by {source?.Name} -> {_health.CurrentHealth}/{_health.MaxHealth} HP");
    }

    private void OnDied(Node source)
    {
        GD.Print("[TargetDummy] Destroyed. Resetting for further testing." );
        if (AutoResetOnDeath)
        {
            GetTree().CreateTimer(ResetDelaySeconds).Timeout += ResetHealth;
        }
    }

    private void ResetHealth()
    {
        _health.Revive();
    }
}
