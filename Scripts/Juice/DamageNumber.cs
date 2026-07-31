using Godot;
using Nightbane.Core;

namespace Nightbane.Juice;

/// <summary>
/// Pooled floating damage popup. JuiceController pulls one from ObjectPool, calls Show(),
/// and this node floats up / fades then Returns itself. Root must be Node2D with a Label child.
/// </summary>
public partial class DamageNumber : Node2D, IPoolable
{
    [Export] public float RiseSpeed { get; set; } = 48f;
    [Export] public float LifetimeSeconds { get; set; } = 0.55f;
    [Export] public float FadeStartFraction { get; set; } = 0.45f;
    [Export] public NodePath LabelPath { get; set; } = "Label";

    private Label _label;
    private ObjectPool<DamageNumber> _pool;
    private float _remaining;
    private float _lifetime;
    private bool _active;
    private Vector2 _drift;

    public override void _Ready()
    {
        _label = GetNodeOrNull<Label>(LabelPath);
        if (_label == null)
        {
            GD.PushWarning("[DamageNumber] LabelPath not wired; popup will be blank.");
        }
    }

    /// <summary>Arms the popup at world position with the given amount/color. Call right after pool.Get().</summary>
    public void ShowAt(Vector2 worldPosition, int amount, Color color, ObjectPool<DamageNumber> pool)
    {
        _pool = pool;
        GlobalPosition = worldPosition + new Vector2((float)GD.RandRange(-6.0, 6.0), (float)GD.RandRange(-10.0, -2.0));
        _lifetime = LifetimeSeconds;
        _remaining = LifetimeSeconds;
        _active = true;
        // Slight horizontal drift so stacked hits on the same target don't fully overlap.
        _drift = new Vector2((float)GD.RandRange(-12.0, 12.0), 0f);

        if (_label != null)
        {
            _label.Text = amount.ToString();
            _label.Modulate = color;
        }

        Modulate = Colors.White;
    }

    public override void _Process(double delta)
    {
        if (!_active)
        {
            return;
        }

        float dt = (float)delta;
        _remaining -= dt;
        GlobalPosition += (Vector2.Up * RiseSpeed + _drift) * dt;

        // Fade after FadeStartFraction of life is spent.
        float lived = 1f - Mathf.Clamp(_remaining / Mathf.Max(0.001f, _lifetime), 0f, 1f);
        if (lived >= FadeStartFraction)
        {
            float fadeT = (lived - FadeStartFraction) / Mathf.Max(0.001f, 1f - FadeStartFraction);
            Modulate = new Color(1f, 1f, 1f, 1f - fadeT);
        }

        if (_remaining <= 0f)
        {
            _active = false;
            _pool?.Return(this);
        }
    }

    public void OnSpawn()
    {
        Visible = true;
        SetProcess(true);
        Modulate = Colors.White;
    }

    public void OnDespawn()
    {
        _active = false;
        Visible = false;
        SetProcess(false);
        if (_label != null)
        {
            _label.Text = string.Empty;
        }
    }
}
