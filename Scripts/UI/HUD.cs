using System.Collections.Generic;
using Godot;
using Nightbane.Autoloads;
using Nightbane.Combat;
using Nightbane.PlayerCharacter;

namespace Nightbane.UI;

/// <summary>
/// Always-on in-run HUD: HP/XP bars, wave number + timer, currency, and off-screen enemy
/// direction arrows. Syncs initial state from autoloads then listens to EventBus.
/// </summary>
public partial class HUD : CanvasLayer
{
    [ExportGroup("Wiring")]
    [Export] public NodePath HealthBarPath { get; set; }
    [Export] public NodePath XpBarPath { get; set; }
    [Export] public NodePath WaveLabelPath { get; set; }
    [Export] public NodePath TimerLabelPath { get; set; }
    [Export] public NodePath CurrencyLabelPath { get; set; }
    [Export] public NodePath ArrowLayerPath { get; set; }

    [ExportGroup("Offscreen Arrows")]
    [Export] public int MaxOffscreenArrows { get; set; } = 12;
    [Export] public float ArrowEdgePadding { get; set; } = 28f;
    [Export] public float ArrowMinDistance { get; set; } = 40f;

    private ProgressBar _healthBar;
    private ProgressBar _xpBar;
    private Label _waveLabel;
    private Label _timerLabel;
    private Label _currencyLabel;
    private Control _arrowLayer;
    private readonly List<Label> _arrowPool = new();

    public override void _Ready()
    {
        _healthBar = GetNodeOrNull<ProgressBar>(HealthBarPath);
        _xpBar = GetNodeOrNull<ProgressBar>(XpBarPath);
        _waveLabel = GetNodeOrNull<Label>(WaveLabelPath);
        _timerLabel = GetNodeOrNull<Label>(TimerLabelPath);
        _currencyLabel = GetNodeOrNull<Label>(CurrencyLabelPath);
        _arrowLayer = GetNodeOrNull<Control>(ArrowLayerPath);

        EnsureArrowLayer();
        BuildArrowPool();

        EventBus.Instance.OnPlayerHealthChanged += OnPlayerHealthChanged;
        EventBus.Instance.OnXpChanged += OnXpChanged;
        EventBus.Instance.OnCurrencyChanged += OnCurrencyChanged;
        EventBus.Instance.OnWaveStart += OnWaveStart;

        SyncInitialState();
    }

    public override void _Process(double delta)
    {
        UpdateWaveTimer();
        UpdateOffscreenArrows();
    }

    private void EnsureArrowLayer()
    {
        if (_arrowLayer != null)
        {
            return;
        }

        _arrowLayer = new Control
        {
            Name = "OffscreenArrows",
            MouseFilter = Control.MouseFilterEnum.Ignore
        };
        _arrowLayer.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        _arrowLayer.GrowHorizontal = Control.GrowDirection.Both;
        _arrowLayer.GrowVertical = Control.GrowDirection.Both;
        AddChild(_arrowLayer);
    }

    private void BuildArrowPool()
    {
        for (int i = 0; i < MaxOffscreenArrows; i++)
        {
            var arrow = new Label
            {
                Text = "◆",
                Visible = false,
                MouseFilter = Control.MouseFilterEnum.Ignore,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            arrow.AddThemeColorOverride("font_color", new Color(0.85f, 0.15f, 0.18f, 0.9f));
            arrow.AddThemeFontSizeOverride("font_size", 18);
            arrow.PivotOffset = new Vector2(10, 10);
            arrow.Size = new Vector2(20, 20);
            _arrowLayer.AddChild(arrow);
            _arrowPool.Add(arrow);
        }
    }

    private void SyncInitialState()
    {
        if (GameManager.Instance != null)
        {
            OnCurrencyChanged(GameManager.Instance.Currency);
            OnWaveStart(GameManager.Instance.WaveNumber);
        }

        if (PlayerStats.Instance != null)
        {
            OnXpChanged(PlayerStats.Instance.CurrentXp, PlayerStats.Instance.XpToNextLevel, PlayerStats.Instance.Level);
        }

        Node2D player = GetTree().GetFirstNodeInGroup("Player") as Node2D;
        HealthComponent health = player?.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health != null)
        {
            OnPlayerHealthChanged(health.CurrentHealth, health.MaxHealth);
        }
    }

    private void UpdateWaveTimer()
    {
        if (_timerLabel == null || WaveManager.Instance == null)
        {
            return;
        }

        if (WaveManager.Instance.IsWaveActive)
        {
            _timerLabel.Text = $"{Mathf.Max(0.0, WaveManager.Instance.WaveTimeRemaining):F0}s";
        }
        else
        {
            _timerLabel.Text = $"Next wave in {Mathf.Max(0.0, WaveManager.Instance.TimeUntilNextWave):F0}s";
        }
    }

    private void UpdateOffscreenArrows()
    {
        if (_arrowLayer == null || _arrowPool.Count == 0)
        {
            return;
        }

        // Hide all first.
        for (int i = 0; i < _arrowPool.Count; i++)
        {
            _arrowPool[i].Visible = false;
        }

        Node2D player = GetTree().GetFirstNodeInGroup("Player") as Node2D;
        if (player == null)
        {
            return;
        }

        Viewport viewport = GetViewport();
        if (viewport == null)
        {
            return;
        }

        Rect2 visible = viewport.GetVisibleRect();
        Vector2 screenCenter = visible.Position + visible.Size * 0.5f;
        float pad = ArrowEdgePadding;
        Rect2 inner = new Rect2(
            visible.Position + new Vector2(pad, pad),
            visible.Size - new Vector2(pad * 2f, pad * 2f));

        int arrowIndex = 0;
        foreach (Node node in GetTree().GetNodesInGroup("Enemy"))
        {
            if (arrowIndex >= _arrowPool.Count)
            {
                break;
            }

            if (node is not Node2D enemy || !GodotObject.IsInstanceValid(enemy) || !enemy.IsInsideTree())
            {
                continue;
            }

            // Skip inactive/pooled (common pattern: hidden or process disabled).
            if (!enemy.Visible || enemy.GetParent() == null)
            {
                continue;
            }

            Vector2 screenPos = enemy.GetGlobalTransformWithCanvas().Origin;
            if (inner.HasPoint(screenPos))
            {
                continue;
            }

            Vector2 dir = screenPos - screenCenter;
            if (dir.LengthSquared() < ArrowMinDistance * ArrowMinDistance)
            {
                continue;
            }

            dir = dir.Normalized();
            Vector2 edge = ClampToRectEdge(screenCenter, dir, inner);
            Label arrow = _arrowPool[arrowIndex++];
            arrow.Position = edge - arrow.Size * 0.5f;
            arrow.Rotation = dir.Angle() + Mathf.Pi * 0.5f; // diamond tip toward threat
            arrow.Visible = true;
        }
    }

    /// <summary>Ray from center along dir hits the padded rect edge.</summary>
    private static Vector2 ClampToRectEdge(Vector2 center, Vector2 dir, Rect2 rect)
    {
        float tMin = float.MaxValue;

        // Intersect with each of the 4 edges of the rect, keep nearest positive hit.
        if (Mathf.Abs(dir.X) > 0.0001f)
        {
            float tLeft = (rect.Position.X - center.X) / dir.X;
            if (tLeft > 0)
            {
                Vector2 p = center + dir * tLeft;
                if (p.Y >= rect.Position.Y && p.Y <= rect.End.Y)
                {
                    tMin = Mathf.Min(tMin, tLeft);
                }
            }

            float tRight = (rect.End.X - center.X) / dir.X;
            if (tRight > 0)
            {
                Vector2 p = center + dir * tRight;
                if (p.Y >= rect.Position.Y && p.Y <= rect.End.Y)
                {
                    tMin = Mathf.Min(tMin, tRight);
                }
            }
        }

        if (Mathf.Abs(dir.Y) > 0.0001f)
        {
            float tTop = (rect.Position.Y - center.Y) / dir.Y;
            if (tTop > 0)
            {
                Vector2 p = center + dir * tTop;
                if (p.X >= rect.Position.X && p.X <= rect.End.X)
                {
                    tMin = Mathf.Min(tMin, tTop);
                }
            }

            float tBottom = (rect.End.Y - center.Y) / dir.Y;
            if (tBottom > 0)
            {
                Vector2 p = center + dir * tBottom;
                if (p.X >= rect.Position.X && p.X <= rect.End.X)
                {
                    tMin = Mathf.Min(tMin, tBottom);
                }
            }
        }

        if (tMin == float.MaxValue)
        {
            return center + dir * 100f;
        }

        return center + dir * tMin;
    }

    private void OnPlayerHealthChanged(int currentHealth, int maxHealth)
    {
        if (_healthBar == null)
        {
            return;
        }

        _healthBar.MaxValue = maxHealth;
        _healthBar.Value = currentHealth;
    }

    private void OnXpChanged(int currentXp, int xpToNextLevel, int level)
    {
        if (_xpBar == null)
        {
            return;
        }

        _xpBar.MaxValue = xpToNextLevel;
        _xpBar.Value = currentXp;
    }

    private void OnCurrencyChanged(int currentCurrency)
    {
        if (_currencyLabel != null)
        {
            _currencyLabel.Text = $"{currentCurrency}";
        }
    }

    private void OnWaveStart(int waveNumber)
    {
        if (_waveLabel != null)
        {
            _waveLabel.Text = $"Wave {waveNumber}";
        }
    }
}
