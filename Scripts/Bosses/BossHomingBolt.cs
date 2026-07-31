using Godot;
using Nightbane.Combat;

namespace Nightbane.Bosses;

/// <summary>
/// Homing curse bolt used by The Hollow Cardinal. Steers toward the Player each frame,
/// damages on overlap, then frees. Not pooled (boss fights spawn few bolts).
/// </summary>
public partial class BossHomingBolt : Area2D
{
    public float Speed { get; set; } = 220f;
    public float TurnRate { get; set; } = 3.5f;
    public float MaxLifetimeSeconds { get; set; } = 5f;
    public int Damage { get; set; } = 12;
    public Node Instigator { get; set; }

    private Vector2 _direction = Vector2.Right;
    private double _lifeRemaining;
    private bool _active = true;

    public override void _Ready()
    {
        BodyEntered += OnBodyEntered;
        Monitoring = true;
        Monitorable = false;
        CollisionLayer = 0;
        CollisionMask = 2; // Player layer
        _lifeRemaining = MaxLifetimeSeconds;

        var shape = new CollisionShape2D
        {
            Shape = new CircleShape2D { Radius = 7f }
        };
        AddChild(shape);

        var sprite = new Polygon2D
        {
            Color = new Color(0.55f, 0.2f, 0.85f, 1f),
            Polygon = new Vector2[]
            {
                new(-8, -4), new(10, 0), new(-8, 4), new(-4, 0)
            }
        };
        AddChild(sprite);
    }

    public void Launch(Vector2 origin, Vector2 initialDirection)
    {
        GlobalPosition = origin;
        _direction = initialDirection.Normalized();
        if (_direction == Vector2.Zero)
        {
            _direction = Vector2.Right;
        }

        Rotation = _direction.Angle();
        _active = true;
        _lifeRemaining = MaxLifetimeSeconds;
    }

    public override void _PhysicsProcess(double delta)
    {
        if (!_active)
        {
            return;
        }

        Node2D player = GetTree()?.GetFirstNodeInGroup("Player") as Node2D;
        if (player != null)
        {
            Vector2 desired = (player.GlobalPosition - GlobalPosition).Normalized();
            _direction = _direction.Lerp(desired, (float)(TurnRate * delta)).Normalized();
            Rotation = _direction.Angle();
        }

        GlobalPosition += _direction * Speed * (float)delta;

        _lifeRemaining -= delta;
        if (_lifeRemaining <= 0)
        {
            QueueFree();
        }
    }

    private void OnBodyEntered(Node2D body)
    {
        if (!_active || !body.IsInGroup("Player"))
        {
            return;
        }

        HealthComponent health = body.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health == null || health.IsDead)
        {
            return;
        }

        health.TakeDamage(Damage, Instigator);
        _active = false;
        QueueFree();
    }

    public static BossHomingBolt Spawn(Node host, Vector2 origin, Vector2 direction, float speed, int damage,
        Node instigator, float lifetime = 5f, float turnRate = 3.5f)
    {
        var bolt = new BossHomingBolt
        {
            Speed = speed,
            Damage = damage,
            Instigator = instigator,
            MaxLifetimeSeconds = lifetime,
            TurnRate = turnRate
        };

        Node parent = host.GetTree()?.CurrentScene ?? host.GetParent() ?? host;
        parent.AddChild(bolt);
        bolt.Launch(origin, direction);
        return bolt;
    }
}
