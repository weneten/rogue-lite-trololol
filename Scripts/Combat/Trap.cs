using System;
using Godot;
using Nightbane.AI;
using Nightbane.Core;

namespace Nightbane.Combat;

/// <summary>
/// Pooled placed hazard spawned by Weapon.PlaceTrap for WeaponClass.Trap weapons (Iron Bear
/// Trap): sits armed and invisible-to-logic until a live TargetGroup body walks over it, then
/// deals damage and roots it via Enemy.ApplyMovementModifier before returning to the pool — same
/// spawn/despawn contract as Projectile, so it never has to be re-instantiated.
/// </summary>
public partial class Trap : Area2D, IPoolable
{
    private float _damage;
    private float _critChance;
    private float _critMultiplier;
    private string _targetGroup;
    private float _rootDurationSeconds;
    private Node _instigator;
    private ObjectPool<Trap> _pool;
    private Action<int, Node2D> _onDamageDealt;

    private double _lifeRemaining;
    private bool _armed;

    public override void _Ready()
    {
        BodyEntered += OnBodyEntered;
    }

    /// <summary>Arms/positions the trap. Called by Weapon.cs immediately after ObjectPool.Get().</summary>
    public void Arm(Vector2 position, ObjectPool<Trap> pool, Node instigator, float damage,
        float critChance, float critMultiplier, string targetGroup, float rootDurationSeconds,
        float lifetimeSeconds, Action<int, Node2D> onDamageDealt = null)
    {
        GlobalPosition = position;
        _pool = pool;
        _instigator = instigator;
        _damage = damage;
        _critChance = critChance;
        _critMultiplier = critMultiplier;
        _targetGroup = targetGroup;
        _rootDurationSeconds = rootDurationSeconds;
        _onDamageDealt = onDamageDealt;

        _lifeRemaining = lifetimeSeconds;
        _armed = true;
    }

    public override void _PhysicsProcess(double delta)
    {
        if (!_armed)
        {
            return;
        }

        _lifeRemaining -= delta;
        if (_lifeRemaining <= 0)
        {
            Despawn();
        }
    }

    private void OnBodyEntered(Node2D body)
    {
        if (!_armed || !body.IsInGroup(_targetGroup))
        {
            return;
        }

        HealthComponent health = body.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health == null || health.IsDead)
        {
            return;
        }

        bool isCrit = GD.Randf() < _critChance;
        int finalDamage = Mathf.RoundToInt(_damage * (isCrit ? _critMultiplier : 1f));
        health.TakeDamage(finalDamage, _instigator);
        _onDamageDealt?.Invoke(finalDamage, body);

        if (body is Enemy enemy)
        {
            enemy.ApplyMovementModifier(0f, _rootDurationSeconds);
        }

        Despawn();
    }

    private void Despawn()
    {
        _armed = false;
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
        _armed = false;
        Visible = false;
        Monitoring = false;
        Monitorable = false;
        SetPhysicsProcess(false);
    }
}
