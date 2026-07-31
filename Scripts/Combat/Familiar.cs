using Godot;
using Nightbane.AI;
using Nightbane.Core;
using Nightbane.PlayerCharacter;
using Nightbane.Resources;

namespace Nightbane.Combat;

/// <summary>
/// Independent auto-attacking pet spawned by WeaponClass.Summon weapons (Grimoire of Bones'
/// skeleton, Spectral Hound Whistle's hound). Unlike Weapon — a slot rigidly mounted on the
/// owner — a Familiar is a free-roaming Node2D that hovers near its owner and fires its own
/// pooled projectiles at the nearest enemy on its own cooldown; the Weapon node that spawned it
/// does nothing further once Setup() is called (see Weapon._Process's Summon early-out).
/// </summary>
public partial class Familiar : Node2D
{
    [Export] public string TargetGroup { get; set; } = "Enemy";
    [Export] public float FollowSpeed { get; set; } = 220f;
    /// <summary>Offset from the owner this familiar tries to hover at, so multiple familiars/weapon
    /// copies don't all stack exactly on top of the owner.</summary>
    [Export] public Vector2 FollowOffset { get; set; } = new Vector2(-40, -20);
    [Export] public NodePath ProjectileSpawnPointPath { get; set; }
    [Export] public int ProjectilePoolPrewarm { get; set; } = 4;

    private WeaponData _data;
    private Node2D _owner;
    private PlayerStats _ownerStats;
    private Node2D _spawnPoint;
    private ObjectPool<Projectile> _projectilePool;

    private double _cooldownRemaining;

    public override void _Ready()
    {
        _spawnPoint = GetNodeOrNull<Node2D>(ProjectileSpawnPointPath) ?? this;
    }

    /// <summary>Wires this familiar to fight on behalf of owner using data's stats. Called once by
    /// Weapon.SpawnFamiliar right after instantiation.</summary>
    public void Setup(Node2D owner, WeaponData data, PlayerStats ownerStats)
    {
        _owner = owner;
        _data = data;
        _ownerStats = ownerStats;

        if (data.ProjectileScene != null)
        {
            _projectilePool = new ObjectPool<Projectile>(data.ProjectileScene, GetTree().CurrentScene ?? GetParent(), ProjectilePoolPrewarm);
        }
    }

    public override void _Process(double delta)
    {
        if (_owner == null || _data == null)
        {
            return;
        }

        Vector2 desiredPosition = _owner.GlobalPosition + FollowOffset;
        GlobalPosition = GlobalPosition.MoveToward(desiredPosition, FollowSpeed * (float)delta);

        _cooldownRemaining -= delta;

        Node2D target = FindNearestTarget();
        if (target == null)
        {
            return;
        }

        GlobalRotation = (target.GlobalPosition - GlobalPosition).Angle();

        if (_cooldownRemaining > 0)
        {
            return;
        }

        FireAt(target);
        _cooldownRemaining = 1.0 / Mathf.Max(0.01f, _data.AttackSpeed * (_ownerStats?.AttackSpeedMultiplier ?? 1f));
    }

    /// <summary>Nearest live TargetGroup member within Data.Range of the familiar itself (not the owner).</summary>
    private Node2D FindNearestTarget()
    {
        Node2D nearest = null;
        float nearestDistSq = _data.Range * _data.Range;

        foreach (Node node in GetTree().GetNodesInGroup(TargetGroup))
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

            float distSq = GlobalPosition.DistanceSquaredTo(candidate.GlobalPosition);
            if (distSq <= nearestDistSq)
            {
                nearestDistSq = distSq;
                nearest = candidate;
            }
        }

        return nearest;
    }

    private void FireAt(Node2D target)
    {
        if (_projectilePool == null)
        {
            return;
        }

        Vector2 direction = (target.GlobalPosition - _spawnPoint.GlobalPosition).Normalized();
        float critChance = _data.CritChance + (_ownerStats?.ExtraCritChance ?? 0f);
        float critMultiplier = _data.CritMultiplier + (_ownerStats?.ExtraCritMultiplier ?? 0f);

        float damageMultiplier = _ownerStats?.DamageMultiplier ?? 1f;
        if (target is Enemy enemy && enemy.Data != null && enemy.Data.IsUndead)
        {
            damageMultiplier *= _ownerStats?.UndeadDamageMultiplier ?? 1f;
        }

        Projectile projectile = _projectilePool.Get();
        projectile.Launch(
            _spawnPoint.GlobalPosition,
            direction,
            _projectilePool,
            _owner,
            _data.Damage * damageMultiplier,
            critChance,
            critMultiplier,
            _data.Knockback,
            TargetGroup,
            (dealt, hitBody) => _ownerStats?.NotifyDamageDealt(dealt, hitBody));
    }
}
