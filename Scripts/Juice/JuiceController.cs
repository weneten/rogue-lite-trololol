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
    /// <summary>Damage &gt;= this uses stronger flash/number color (NOT hitstop by default).</summary>
    [Export] public int BigHitThreshold { get; set; } = 35;
    [Export] public float BigHitTrauma { get; set; } = 0.12f;
    /// <summary>Hitstop only when damage reaches this AND cooldown elapsed. Keep high — per-hit freeze feels awful.</summary>
    [Export] public int HitStopDamageThreshold { get; set; } = 80;
    [Export] public float HitStopSeconds { get; set; } = 0.03f;
    [Export] public float HitStopCooldownSeconds { get; set; } = 0.45f;
    [Export] public bool EnableHitStop { get; set; } = false;
    [Export] public float HitFlashSeconds { get; set; } = 0.06f;
    [Export] public Color NormalDamageColor { get; set; } = new(1f, 0.92f, 0.85f, 1f);
    [Export] public Color BigDamageColor { get; set; } = new(1f, 0.78f, 0.25f, 1f);
    [Export] public Color FlashModulate { get; set; } = new(1.8f, 1.8f, 1.8f, 1f);

    private ScreenShake _shake;
    private HitStop _hitStop;
    private ObjectPool<DamageNumber> _damageNumberPool;
    private Node2D _player;
    private bool _boundCamera;
    private double _hitStopCooldownRemaining;

    public override void _Ready()
    {
        // Recover if a previous session left TimeScale stuck low after hitstop spam.
        if (Engine.TimeScale < 0.99)
        {
            Engine.TimeScale = 1.0;
        }

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
        if (_hitStopCooldownRemaining > 0)
        {
            _hitStopCooldownRemaining -= delta;
        }

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

            // Light shake only — no TimeScale freeze on normal combat hits.
            _shake?.AddTrauma(BigHitTrauma * 0.55f);
        }

        // Hitstop OFF by default. When enabled, rare + cooldown so multi-cleave doesn't stutter.
        if (EnableHitStop
            && amount >= HitStopDamageThreshold
            && _hitStopCooldownRemaining <= 0
            && HitStopSeconds > 0f)
        {
            _hitStop?.Freeze(HitStopSeconds, 0.35f);
            _hitStopCooldownRemaining = HitStopCooldownSeconds;
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
        // Prefer an explicit "Sprite" child (AnimatedSprite2D / Polygon2D / Sprite2D).
        CanvasItem sprite = target.GetNodeOrNull<CanvasItem>("Sprite");
        if (sprite != null)
        {
            return sprite;
        }

        foreach (Node child in target.GetChildren())
        {
            if (child is AnimatedSprite2D or Polygon2D or Sprite2D)
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
