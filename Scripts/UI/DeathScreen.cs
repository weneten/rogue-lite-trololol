using Godot;
using Nightbane.Autoloads;
using Nightbane.Meta;

namespace Nightbane.UI;

/// <summary>
/// Run-end summary: player death OR wave-20 clear. Grants meta-currency via RunStats,
/// shows waves/kills/damage/gold, Continue -> MainMenu.
/// </summary>
public partial class DeathScreen : CanvasLayer
{
    /// <summary>True while the overlay is up (PauseMenu ignores ESC while set).</summary>
    public static bool IsShowing { get; private set; }

    [Export] public NodePath RootPanelPath { get; set; }
    [Export] public NodePath TitleLabelPath { get; set; }
    [Export] public NodePath StatsLabelPath { get; set; }
    [Export] public NodePath MetaLabelPath { get; set; }
    [Export] public NodePath ContinueButtonPath { get; set; }
    [Export] public string MainMenuScenePath { get; set; } = "res://Scenes/MainMenu/MainMenu.tscn";
    [Export] public int VictoryWave { get; set; } = 20;

    private Control _rootPanel;
    private Label _titleLabel;
    private Label _statsLabel;
    private Label _metaLabel;
    private Button _continueButton;
    private bool _shown;

    public override void _Ready()
    {
        ProcessMode = ProcessModeEnum.Always;
        Layer = 100;

        _rootPanel = GetNodeOrNull<Control>(RootPanelPath);
        _titleLabel = GetNodeOrNull<Label>(TitleLabelPath);
        _statsLabel = GetNodeOrNull<Label>(StatsLabelPath);
        _metaLabel = GetNodeOrNull<Label>(MetaLabelPath);
        _continueButton = GetNodeOrNull<Button>(ContinueButtonPath);

        if (_continueButton != null)
        {
            _continueButton.Pressed += OnContinuePressed;
        }

        if (_rootPanel != null)
        {
            _rootPanel.Visible = false;
        }

        IsShowing = false;
        _shown = false;

        if (EventBus.Instance != null)
        {
            EventBus.Instance.OnPlayerDied += OnPlayerDied;
            EventBus.Instance.OnWaveEnd += OnWaveEnd;
        }
    }

    public override void _ExitTree()
    {
        if (EventBus.Instance != null)
        {
            EventBus.Instance.OnPlayerDied -= OnPlayerDied;
            EventBus.Instance.OnWaveEnd -= OnWaveEnd;
        }

        IsShowing = false;
    }

    private void OnPlayerDied()
    {
        ShowSummary(runComplete: false);
    }

    private void OnWaveEnd(int waveNumber)
    {
        if (waveNumber >= VictoryWave)
        {
            ShowSummary(runComplete: true);
        }
    }

    private void ShowSummary(bool runComplete)
    {
        if (_shown)
        {
            return;
        }

        _shown = true;
        IsShowing = true;
        GetTree().Paused = true;

        RunStats stats = RunStats.Instance;
        int waves = stats?.WavesSurvived ?? GameManager.Instance?.WaveNumber ?? 0;
        int kills = stats?.Kills ?? 0;
        int damage = stats?.DamageDealt ?? 0;
        int gold = stats?.GoldEarned ?? GameManager.Instance?.Currency ?? 0;

        int metaGranted = stats != null
            ? stats.FinalizeAndGrantMeta(runComplete)
            : RunStats.PreviewPayout(waves, kills, gold, runComplete);

        if (stats == null && metaGranted > 0)
        {
            MetaSave.AddMetaCurrency(metaGranted);
        }

        if (_titleLabel != null)
        {
            _titleLabel.Text = runComplete ? "The Blood Moon Wanes" : "You Have Fallen";
        }

        if (_statsLabel != null)
        {
            _statsLabel.Text =
                $"Waves Survived: {waves}\n" +
                $"Kills: {kills}\n" +
                $"Damage Dealt: {damage}\n" +
                $"Gold Earned: {gold}";
        }

        if (_metaLabel != null)
        {
            _metaLabel.Text = $"+{metaGranted} Blood Marks\nTotal: {MetaSave.GetMetaCurrency()}";
        }

        if (_rootPanel != null)
        {
            _rootPanel.Visible = true;
        }
    }

    private void OnContinuePressed()
    {
        IsShowing = false;
        GetTree().Paused = false;
        GetTree().ChangeSceneToFile(MainMenuScenePath);
    }
}
