using Godot;
using Nightbane.Combat;

namespace Nightbane.Bosses;

/// <summary>
/// Persistent purple ritual zone that ticks damage only while the player is nearly stationary
/// inside it — punishes camping. Frees after DurationSeconds.
/// </summary>
public partial class BossRitualCircle : Node2D
{
    public float Radius { get; set; } = 90f;
    public float DurationSeconds { get; set; } = 5f;
    public float TickInterval { get; set; } = 0.4f;
    public int DamagePerTick { get; set; } = 8;
    /// <summary>Player speed below this counts as "standing still".</summary>
    public float StillSpeedThreshold { get; set; } = 30f;
    public Node Instigator { get; set; }

    private double _lifeRemaining;
    private double _tickRemaining;
    private Vector2 _lastPlayerPos;
    private bool _hasLastPos;

    public override void _Ready()
    {
        _lifeRemaining = DurationSeconds;
        _tickRemaining = TickInterval;
        ZIndex = -1;

        var fill = new Polygon2D
        {
            Color = new Color(0.45f, 0.1f, 0.7f, 0.35f),
            Polygon = BuildCircle(Radius, 24)
        };
        AddChild(fill);

        var ring = new Polygon2D
        {
            Color = new Color(0.7f, 0.25f, 0.95f, 0.8f),
            Polygon = BuildRing(Radius * 0.9f, Radius, 24)
        };
        AddChild(ring);
    }

    public override void _Process(double delta)
    {
        _lifeRemaining -= delta;
        if (_lifeRemaining <= 0)
        {
            QueueFree();
            return;
        }

        // Slow pulse.
        Modulate = new Color(1f, 1f, 1f, 0.75f + 0.25f * Mathf.Sin((float)Time.GetTicksMsec() * 0.006f));

        _tickRemaining -= delta;
        if (_tickRemaining > 0)
        {
            return;
        }

        _tickRemaining = TickInterval;
        TryPunishStationaryPlayer();
    }

    private void TryPunishStationaryPlayer()
    {
        Node2D player = GetTree()?.GetFirstNodeInGroup("Player") as Node2D;
        if (player == null)
        {
            return;
        }

        if (GlobalPosition.DistanceTo(player.GlobalPosition) > Radius)
        {
            _hasLastPos = false;
            return;
        }

        float speed;
        if (player is CharacterBody2D body)
        {
            speed = body.Velocity.Length();
        }
        else if (_hasLastPos)
        {
            speed = _lastPlayerPos.DistanceTo(player.GlobalPosition) / Mathf.Max(0.001f, (float)TickInterval);
        }
        else
        {
            speed = 0f;
        }

        _lastPlayerPos = player.GlobalPosition;
        _hasLastPos = true;

        if (speed > StillSpeedThreshold)
        {
            return;
        }

        HealthComponent health = player.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health == null || health.IsDead)
        {
            return;
        }

        health.TakeDamage(DamagePerTick, Instigator);
    }

    private static Vector2[] BuildCircle(float radius, int segments)
    {
        var points = new Vector2[segments];
        for (int i = 0; i < segments; i++)
        {
            float a = Mathf.Tau * i / segments;
            points[i] = new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * radius;
        }

        return points;
    }

    private static Vector2[] BuildRing(float inner, float outer, int segments)
    {
        var points = new Vector2[segments * 2];
        for (int i = 0; i < segments; i++)
        {
            float a = Mathf.Tau * i / segments;
            Vector2 dir = new Vector2(Mathf.Cos(a), Mathf.Sin(a));
            points[i] = dir * outer;
            points[segments * 2 - 1 - i] = dir * inner;
        }

        return points;
    }

    public static BossRitualCircle Spawn(Node host, Vector2 globalPosition, float radius, float duration,
        int damagePerTick, Node instigator)
    {
        var circle = new BossRitualCircle
        {
            Radius = radius,
            DurationSeconds = duration,
            DamagePerTick = damagePerTick,
            Instigator = instigator
        };

        Node parent = host.GetTree()?.CurrentScene ?? host.GetParent() ?? host;
        parent.AddChild(circle);
        circle.GlobalPosition = globalPosition;
        return circle;
    }
}
