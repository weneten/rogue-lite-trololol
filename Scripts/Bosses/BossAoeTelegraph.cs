using Godot;
using Nightbane.Combat;

namespace Nightbane.Bosses;

/// <summary>
/// Red circular warning decal. After WindupSeconds it damages any live Player in radius, then frees.
/// Spawned by Boss during attack wind-up so the player can dodge telegraphed AoEs.
/// </summary>
public partial class BossAoeTelegraph : Node2D
{
    public float Radius { get; set; } = 80f;
    public float WindupSeconds { get; set; } = 0.8f;
    public int Damage { get; set; } = 20;
    public Node Instigator { get; set; }
    /// <summary>When true, resolve damage on timer end. When false, only visual (caller resolves).</summary>
    public bool DealDamageOnComplete { get; set; } = true;
    /// <summary>Optional callback after wind-up (before free), e.g. for custom hit logic.</summary>
    public System.Action OnWindupComplete { get; set; }

    private double _remaining;
    private Polygon2D _fill;
    private Polygon2D _ring;
    private bool _resolved;

    public override void _Ready()
    {
        _remaining = WindupSeconds;
        BuildVisuals();
        ZIndex = -1;
    }

    public override void _Process(double delta)
    {
        if (_resolved)
        {
            return;
        }

        _remaining -= delta;

        // Pulse alpha so the telegraph reads as urgent.
        float t = WindupSeconds > 0f ? 1f - (float)(_remaining / WindupSeconds) : 1f;
        float pulse = 0.35f + 0.45f * (0.5f + 0.5f * Mathf.Sin(t * Mathf.Tau * 4f));
        if (_fill != null)
        {
            _fill.Color = new Color(0.95f, 0.1f, 0.12f, pulse * 0.45f);
        }

        if (_remaining > 0)
        {
            return;
        }

        Resolve();
    }

    private void Resolve()
    {
        if (_resolved)
        {
            return;
        }

        _resolved = true;
        OnWindupComplete?.Invoke();

        if (DealDamageOnComplete)
        {
            DamagePlayersInRadius();
        }

        QueueFree();
    }

    public void DamagePlayersInRadius()
    {
        Node2D player = GetTree()?.GetFirstNodeInGroup("Player") as Node2D;
        if (player == null)
        {
            return;
        }

        if (GlobalPosition.DistanceTo(player.GlobalPosition) > Radius)
        {
            return;
        }

        HealthComponent health = player.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health == null || health.IsDead)
        {
            return;
        }

        health.TakeDamage(Damage, Instigator);
    }

    private void BuildVisuals()
    {
        _fill = new Polygon2D
        {
            Color = new Color(0.95f, 0.1f, 0.12f, 0.35f),
            Polygon = BuildCirclePolygon(Radius, 28)
        };
        AddChild(_fill);

        _ring = new Polygon2D
        {
            Color = new Color(1f, 0.25f, 0.2f, 0.85f),
            Polygon = BuildRingPolygon(Radius * 0.92f, Radius, 28)
        };
        AddChild(_ring);
    }

    private static Vector2[] BuildCirclePolygon(float radius, int segments)
    {
        var points = new Vector2[segments];
        for (int i = 0; i < segments; i++)
        {
            float a = Mathf.Tau * i / segments;
            points[i] = new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * radius;
        }

        return points;
    }

    private static Vector2[] BuildRingPolygon(float inner, float outer, int segments)
    {
        // Triangle strip as a single polygon: outer ring then reversed inner ring.
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

    /// <summary>Factory: parents a telegraph under the current scene at world position.</summary>
    public static BossAoeTelegraph Spawn(Node host, Vector2 globalPosition, float radius, float windupSeconds,
        int damage, Node instigator, bool dealDamageOnComplete = true, System.Action onComplete = null)
    {
        var telegraph = new BossAoeTelegraph
        {
            Radius = radius,
            WindupSeconds = windupSeconds,
            Damage = damage,
            Instigator = instigator,
            DealDamageOnComplete = dealDamageOnComplete,
            OnWindupComplete = onComplete
        };

        Node parent = host.GetTree()?.CurrentScene ?? host.GetParent() ?? host;
        parent.AddChild(telegraph);
        telegraph.GlobalPosition = globalPosition;
        return telegraph;
    }
}
