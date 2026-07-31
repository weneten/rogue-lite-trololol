using Godot;
using Nightbane.Autoloads;
using Nightbane.Core;

namespace Nightbane.Juice;

/// <summary>
/// Central combat-juice hub. Listens to EventBus only — keeps Player/Enemy/Weapon/HealthComponent
/// free of VFX side-effects so parallel stages can own those files. Owns ScreenShake, HitStop,
/// pooled DamageNumber popups, and hit-flash modulation on damaged targets.
/// </summary>
public partial class JuiceController : Node
{
    [ExportGroup("Scenes")]
    [Export] public PackedScene DamageNumberScene { get; set; }
    [Export] public int DamageNumberPoolPrewarm { get; set; } = 24;

    [ExportGroup("Player Hit")]
    [Export] public float PlayerHitTraumaPerDamage { get; set; } = 0.03f;
    [Export] public float PlayerHitTraumaMin { get; set; } = 0.18f;
    [Export] public float PlayerHitTraumaMax { get; set; } = 0.65f;

    [ExportGroup("Outgoing Hits")]
    /// <summary>Damage &gt;= this triggers hitstop + stronger flash/number color.</summary>
    [Export] public int BigHitThreshold { get; set; } = 22;
    [Export] public float BigHitTrauma { get; set; } = 0.22f;
    [Export] public float BigHitStopSeconds { get; set; } = 0.045f;
    [Export] public float HitFlashSeconds { get; set; } = 0.07f;
    [Export] public Color NormalDamageColor { get; set; } = new(1f, 0.92f, 0.85f, 1f);
    [Export] public Color BigDamageColor { get; set; } = new(1f, 0.78f, 0.25f, 1f);
    [Export] public Color FlashModulate { get; set; } = new(2.2f, 2.2f, 2.2f, 1f);

    private ScreenShake _shake;
    private HitStop _hitStop;
    private ObjectPool<DamageNumber> _damageNumberPool;
    private Node2D _player;
    private bool _boundCamera;

    public override void _Ready()
    {
        _shake = new ScreenShake { Name = "ScreenShake" };
        AddChild(_shake);

        _hitStop = new HitStop { Name = "HitStop" };
        AddChild(_hitStop);

        // Draw culling lives as a sibling helper under this hub so Arena only needs one juice node.
        var culler = new OffscreenCuller { Name = "OffscreenCuller" };
        AddChild(culler);

        DamageNumberScene ??= GD.Load<PackedScene>("res://Scenes/Combat/DamageNumber.tscn");

        if (EventBus.Instance != null)
        {
            EventBus.Instance.OnPlayerDamaged += OnPlayerDamaged;
            EventBus.Instance.OnPlayerDamageDealt += OnPlayerDamageDealt;
        }
        else
        {
            GD.PushWarning("[JuiceController] EventBus missing; combat juice disabled.");
        }
    }

    public override void _ExitTree()
    {
        if (EventBus.Instance != null)
        {
            EventBus.Instance.OnPlayerDamaged -= OnPlayerDamaged;
            EventBus.Instance.OnPlayerDamageDealt -= OnPlayerDamageDealt;
        }
    }

    public override void _Process(double delta)
    {
        // Lazy camera bind: Player may spawn after this node in Arena.tscn.
        if (!_boundCamera)
        {
            TryBindCamera();
        }
    }

    private void TryBindCamera()
    {
        _player = GetTree()?.GetFirstNodeInGroup("Player") as Node2D;
        if (_player == null)
        {
            return;
        }

        Camera2D cam = _player.GetNodeOrNull<Camera2D>("Camera2D");
        if (cam == null)
        {
            return;
        }

        _shake.Bind(cam);
        _boundCamera = true;
    }

    private void OnPlayerDamaged(float damageAmount, float currentHealth)
    {
        if (!_boundCamera)
        {
            TryBindCamera();
        }

        float trauma = Mathf.Clamp(
            PlayerHitTraumaMin + damageAmount * PlayerHitTraumaPerDamage,
            PlayerHitTraumaMin,
            PlayerHitTraumaMax);
        _shake?.AddTrauma(trauma);
    }

    private void OnPlayerDamageDealt(Node target, int amount)
    {
        if (amount <= 0 || target == null || !GodotObject.IsInstanceValid(target))
        {
            return;
        }

        bool bigHit = amount >= BigHitThreshold;
        Vector2 pos = ResolveWorldPosition(target);

        SpawnDamageNumber(pos, amount, bigHit ? BigDamageColor : NormalDamageColor);
        FlashTarget(target);

        if (bigHit)
        {
            if (!_boundCamera)
            {
                TryBindCamera();
            }

            _shake?.AddTrauma(BigHitTrauma);
            _hitStop?.Freeze(BigHitStopSeconds);
        }
    }

    private void SpawnDamageNumber(Vector2 worldPos, int amount, Color color)
    {
        if (DamageNumberScene == null)
        {
            return;
        }

        _damageNumberPool ??= new ObjectPool<DamageNumber>(
            DamageNumberScene,
            GetTree().CurrentScene ?? this,
            DamageNumberPoolPrewarm);

        DamageNumber popup = _damageNumberPool.Get();
        popup.ShowAt(worldPos, amount, color, _damageNumberPool);
    }

    private async void FlashTarget(Node target)
    {
        CanvasItem sprite = FindFlashableSprite(target);
        if (sprite == null)
        {
            return;
        }

        Color original = sprite.Modulate;
        sprite.Modulate = FlashModulate;

        SceneTreeTimer timer = GetTree().CreateTimer(HitFlashSeconds, true, true);
        await ToSignal(timer, SceneTreeTimer.SignalName.Timeout);

        if (GodotObject.IsInstanceValid(sprite))
        {
            sprite.Modulate = original;
        }
    }

    private static CanvasItem FindFlashableSprite(Node target)
    {
        // Prefer an explicit "Sprite" child (Enemy/Player/TargetDummy convention), else first Polygon2D.
        CanvasItem sprite = target.GetNodeOrNull<CanvasItem>("Sprite");
        if (sprite != null)
        {
            return sprite;
        }

        foreach (Node child in target.GetChildren())
        {
            if (child is Polygon2D or Sprite2D)
            {
                return (CanvasItem)child;
            }
        }

        return target as CanvasItem;
    }

    private static Vector2 ResolveWorldPosition(Node target)
    {
        if (target is Node2D n2d)
        {
            return n2d.GlobalPosition;
        }

        // HealthComponent etc. live as children — climb to nearest Node2D ancestor.
        Node current = target.GetParent();
        while (current != null)
        {
            if (current is Node2D ancestor)
            {
                return ancestor.GlobalPosition;
            }

            current = current.GetParent();
        }

        return Vector2.Zero;
    }
}
