using Godot;

namespace Nightbane.Juice;

/// <summary>
/// Brief Engine.TimeScale dip for impactful hits. Uses a SceneTreeTimer with ignoreTimeScale
/// so the freeze always ends in real time even while scaled. Stacking calls extend/refresh
/// rather than nesting multiple scale restores.
/// </summary>
public partial class HitStop : Node
{
    /// <summary>Softer default — 0.08 felt like full freeze and stacked into permanent slowmo.</summary>
    [Export] public float DefaultTimeScale { get; set; } = 0.35f;
    [Export] public float DefaultDurationSeconds { get; set; } = 0.03f;

    private bool _active;
    private float _restoreScale = 1f;
    private ulong _token;

    public override void _Ready()
    {
        // Survive tree pauses (level-up/shop) so a hitstop started on the same frame still restores.
        ProcessMode = ProcessModeEnum.Always;
    }

    /// <summary>Dips TimeScale for durationSeconds, then restores the pre-dip scale.</summary>
    public async void Freeze(float durationSeconds = -1f, float timeScale = -1f)
    {
        if (durationSeconds < 0f)
        {
            durationSeconds = DefaultDurationSeconds;
        }

        if (timeScale < 0f)
        {
            timeScale = DefaultTimeScale;
        }

        if (durationSeconds <= 0f)
        {
            return;
        }

        // First freeze captures the real scale; stacked freezes just refresh the timer.
        if (!_active)
        {
            _restoreScale = (float)Engine.TimeScale;
            if (_restoreScale <= 0.001f)
            {
                _restoreScale = 1f;
            }
        }

        _active = true;
        ulong myToken = ++_token;
        Engine.TimeScale = timeScale;

        // processAlways + ignoreTimeScale: timer runs in wall-clock seconds, not game time.
        SceneTreeTimer timer = GetTree().CreateTimer(durationSeconds, true, true);
        await ToSignal(timer, SceneTreeTimer.SignalName.Timeout);

        // Only the latest Freeze owns the restore (older awaits no-op).
        if (myToken != _token)
        {
            return;
        }

        Engine.TimeScale = _restoreScale;
        _active = false;
    }
}
