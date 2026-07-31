using Godot;
using Nightbane.Core;
using Nightbane.PlayerCharacter;

namespace Nightbane.Items;

/// <summary>
/// Pooled soul-gem pickup dropped on enemy death (see XpGemSpawner). Idles in place until the
/// player gets within AttractRadius, then drifts toward them (Brotato-style magnetism) and
/// grants XP to PlayerStats on overlap.
/// </summary>
public partial class XpGem : Area2D, IPoolable
{
    [Export] public float AttractRadius { get; set; } = 90f;
    [Export] public float AttractSpeed { get; set; } = 500f;

    private int _xpValue;
    private ObjectPool<XpGem> _pool;
    private bool _active;

    public override void _Ready()
    {
        BodyEntered += OnBodyEntered;
    }

    /// <summary>Arms this pooled instance at the given position with the given XP payout. Called by XpGemSpawner right after ObjectPool.Get().</summary>
    public void Launch(Vector2 position, int xpValue, ObjectPool<XpGem> pool)
    {
        GlobalPosition = position;
        _xpValue = xpValue;
        _pool = pool;
        _active = true;
    }

    public override void _PhysicsProcess(double delta)
    {
        if (!_active)
        {
            return;
        }

        Node2D player = GetTree().GetFirstNodeInGroup("Player") as Node2D;
        if (player == null)
        {
            return;
        }

        if (GlobalPosition.DistanceTo(player.GlobalPosition) <= AttractRadius)
        {
            GlobalPosition = GlobalPosition.MoveToward(player.GlobalPosition, AttractSpeed * (float)delta);
        }
    }

    private void OnBodyEntered(Node2D body)
    {
        if (!_active || !body.IsInGroup("Player"))
        {
            return;
        }

        PlayerStats.Instance?.AddXp(_xpValue);
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
