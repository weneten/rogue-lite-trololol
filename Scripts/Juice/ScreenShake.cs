using Godot;

namespace Nightbane.Juice;

/// <summary>
/// Camera2D offset shake driven by a decaying trauma value (0..1). Bind a camera once,
/// then call AddTrauma / Shake from combat juice hooks. Offset is restored when trauma hits 0.
/// </summary>
public partial class ScreenShake : Node
{
    /// <summary>Max pixel offset at full trauma (trauma^2 * MaxOffset).</summary>
    [Export] public float MaxOffset { get; set; } = 10f;
    /// <summary>How fast trauma drains per second.</summary>
    [Export] public float TraumaDecayPerSecond { get; set; } = 1.6f;

    private Camera2D _camera;
    private Vector2 _baseOffset;
    private float _trauma;

    public void Bind(Camera2D camera)
    {
        // Drop any residual offset on the previous camera before rebinding.
        if (_camera != null && GodotObject.IsInstanceValid(_camera))
        {
            _camera.Offset = _baseOffset;
        }

        _camera = camera;
        _baseOffset = camera != null ? camera.Offset : Vector2.Zero;
        _trauma = 0f;
    }

    /// <summary>Adds trauma clamped to [0,1]. Small hits ~0.15–0.25; big hits ~0.4–0.7.</summary>
    public void AddTrauma(float amount)
    {
        if (amount <= 0f)
        {
            return;
        }

        _trauma = Mathf.Clamp(_trauma + amount, 0f, 1f);
    }

    /// <summary>Convenience: map a strength/duration pair into trauma (duration only soft-caps decay feel).</summary>
    public void Shake(float strength, float durationSeconds = 0.2f)
    {
        // Duration stretches decay slightly so a longer call doesn't vanish in one frame.
        if (durationSeconds > 0f && TraumaDecayPerSecond > 0f)
        {
            float needed = strength / Mathf.Max(0.01f, durationSeconds * TraumaDecayPerSecond);
            AddTrauma(Mathf.Clamp(Mathf.Max(strength, needed * 0.15f), 0f, 1f));
        }
        else
        {
            AddTrauma(strength);
        }
    }

    public override void _Process(double delta)
    {
        if (_camera == null || !GodotObject.IsInstanceValid(_camera))
        {
            return;
        }

        if (_trauma <= 0f)
        {
            _camera.Offset = _baseOffset;
            return;
        }

        _trauma = Mathf.Max(0f, _trauma - TraumaDecayPerSecond * (float)delta);
        // Quadratic falloff: low trauma barely moves the cam, high trauma punches hard.
        float shake = _trauma * _trauma;
        float ox = (float)GD.RandRange(-1.0, 1.0) * MaxOffset * shake;
        float oy = (float)GD.RandRange(-1.0, 1.0) * MaxOffset * shake;
        _camera.Offset = _baseOffset + new Vector2(ox, oy);
    }
}
