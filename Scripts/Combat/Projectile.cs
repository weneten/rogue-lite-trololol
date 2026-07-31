using System;
using Godot;
using Nightbane.Core;

namespace Nightbane.Combat;

/// <summary>
/// Pooled ranged-attack projectile. Weapon.cs pulls one from its ObjectPool&lt;Projectile&gt;,
/// calls Launch() to arm/aim it, and the projectile returns itself to the pool on hit or
/// timeout — it never Free()s itself, so the pool never has to re-instantiate.
/// </summary>
public partial class Projectile : Area2D, IPoolable
{
    [Export] public float Speed { get; set; } = 600f;
    [Export] public float MaxLifetimeSeconds { get; set; } = 3f;

    private float _damage;
    private float _critChance;
    private float _critMultiplier;
    private float _knockback;
    private string _targetGroup;
    private Node _instigator;
    /// <summary>Optional hook fired with (finalDamage, hitBody) after a successful hit — used by
    /// Weapon.cs to forward ranged hits into PlayerStats.NotifyDamageDealt (lifesteal, on-hit
    /// passives) the same way melee hits do. Null for non-player-fired projectiles (e.g. enemies).</summary>
    private Action<int, Node2D> _onDamageDealt;

    private Vector2 _direction = Vector2.Right;
    private double _lifeRemaining;
    private ObjectPool<Projectile> _pool;
    private bool _active;

    public override void _Ready()
    {
        BodyEntered += OnBodyEntered;
    }

    /// <summary>Arms and aims the projectile. Called by Weapon.cs immediately after ObjectPool.Get().</summary>
    public void Launch(Vector2 originPosition, Vector2 direction, ObjectPool<Projectile> pool, Node instigator,
        float damage, float critChance, float critMultiplier, float knockback, string targetGroup,
        Action<int, Node2D> onDamageDealt = null)
    {
        GlobalPosition = originPosition;
        _direction = direction.Normalized();
        Rotation = _direction.Angle();

        _pool = pool;
        _instigator = instigator;
        _damage = damage;
        _critChance = critChance;
        _critMultiplier = critMultiplier;
        _knockback = knockback;
        _targetGroup = targetGroup;
        _onDamageDealt = onDamageDealt;

        _lifeRemaining = MaxLifetimeSeconds;
        _active = true;
    }

    public override void _PhysicsProcess(double delta)
    {
        if (!_active)
        {
            return;
        }

        GlobalPosition += _direction * Speed * (float)delta;

        _lifeRemaining -= delta;
        if (_lifeRemaining <= 0)
        {
            Despawn();
        }
    }

    private void OnBodyEntered(Node2D body)
    {
        if (!_active || !body.IsInGroup(_targetGroup))
        {
            return;
        }

        var health = body.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health == null || health.IsDead)
        {
            return;
        }

        bool isCrit = GD.Randf() < _critChance;
        int finalDamage = Mathf.RoundToInt(_damage * (isCrit ? _critMultiplier : 1f));
        health.TakeDamage(finalDamage, _instigator);
        _onDamageDealt?.Invoke(finalDamage, body);

        if (body is TargetDummy dummy && _knockback > 0f)
        {
            dummy.ApplyKnockback(_direction * _knockback);
        }

        Despawn();
    }

    private void Despawn()
    {
        _active = false;
        _pool?.Return(this);
    }

    public void OnSpawn()
    {
        Visible = true;
        Monitoring = true;
        Monitorable = true;
        SetPhysicsProcess(true);
    }

    public void OnDespawn()
    {
        _active = false;
        Visible = false;
        Monitoring = false;
        Monitorable = false;
        SetPhysicsProcess(false);
    }
}
