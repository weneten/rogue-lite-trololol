using Godot;

namespace Nightbane.UI;

/// <summary>
/// In-run pause overlay: Resume / Settings / Quit to Main Menu. ESC (ui_cancel) toggles.
/// ProcessMode Always so it still runs while the tree is paused.
/// </summary>
public partial class PauseMenu : CanvasLayer
{
    [Export] public NodePath RootPanelPath { get; set; }
    [Export] public NodePath ResumeButtonPath { get; set; }
    [Export] public NodePath SettingsButtonPath { get; set; }
    [Export] public NodePath QuitButtonPath { get; set; }
    [Export] public NodePath SettingsMenuPath { get; set; }
    [Export] public string MainMenuScenePath { get; set; } = "res://Scenes/MainMenu/MainMenu.tscn";

    private Control _rootPanel;
    private Button _resumeButton;
    private Button _settingsButton;
    private Button _quitButton;
    private SettingsMenu _settingsMenu;
    private bool _open;

    public override void _Ready()
    {
        ProcessMode = ProcessModeEnum.Always;
        Layer = 80;

        _rootPanel = GetNodeOrNull<Control>(RootPanelPath);
        _resumeButton = GetNodeOrNull<Button>(ResumeButtonPath);
        _settingsButton = GetNodeOrNull<Button>(SettingsButtonPath);
        _quitButton = GetNodeOrNull<Button>(QuitButtonPath);
        _settingsMenu = GetNodeOrNull<SettingsMenu>(SettingsMenuPath);

        if (_resumeButton != null)
        {
            _resumeButton.Pressed += Close;
        }

        if (_settingsButton != null)
        {
            _settingsButton.Pressed += OnSettingsPressed;
        }

        if (_quitButton != null)
        {
            _quitButton.Pressed += OnQuitPressed;
        }

        if (_rootPanel != null)
        {
            _rootPanel.Visible = false;
        }

        _open = false;
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        // Don't steal ESC while death screen owns the run end.
        if (DeathScreen.IsShowing)
        {
            return;
        }

        if (@event.IsActionPressed("ui_cancel"))
        {
            if (_settingsMenu != null && _settingsMenu.IsOpen)
            {
                _settingsMenu.Close();
                GetViewport().SetInputAsHandled();
                return;
            }

            if (_open)
            {
                Close();
            }
            else
            {
                Open();
            }

            GetViewport().SetInputAsHandled();
        }
    }

    public void Open()
    {
        if (_open)
        {
            return;
        }

        _open = true;
        if (_rootPanel != null)
        {
            _rootPanel.Visible = true;
        }

        GetTree().Paused = true;
    }

    public void Close()
    {
        if (!_open)
        {
            return;
        }

        _open = false;
        if (_rootPanel != null)
        {
            _rootPanel.Visible = false;
        }

        _settingsMenu?.Close();
        GetTree().Paused = false;
    }

    private void OnSettingsPressed()
    {
        _settingsMenu?.Open();
    }

    private void OnQuitPressed()
    {
        GetTree().Paused = false;
        GetTree().ChangeSceneToFile(MainMenuScenePath);
    }
}
