using Godot;
using Nightbane.Meta;

namespace Nightbane.UI;

/// <summary>Main menu: Start -> CharacterSelect, Settings overlay, Quit. Shows Blood Marks balance.</summary>
public partial class MainMenu : Control
{
    [Export] public NodePath StartButtonPath { get; set; }
    [Export] public NodePath QuitButtonPath { get; set; }
    [Export] public NodePath SettingsButtonPath { get; set; }
    [Export] public NodePath MetaCurrencyLabelPath { get; set; }
    [Export] public NodePath SettingsMenuPath { get; set; }

    /// <summary>"Begin the Hunt" leads to Hunter selection; Arena loads from CharacterSelect.</summary>
    [Export] public string CharacterSelectScenePath { get; set; } = "res://Scenes/UI/CharacterSelect.tscn";

    private Button _startButton;
    private Button _quitButton;
    private Button _settingsButton;
    private Label _metaCurrencyLabel;
    private SettingsMenu _settingsMenu;

    public override void _Ready()
    {
        MetaSave.EnsureLoaded();

        _startButton = GetNodeOrNull<Button>(StartButtonPath);
        _quitButton = GetNodeOrNull<Button>(QuitButtonPath);
        _settingsButton = GetNodeOrNull<Button>(SettingsButtonPath);
        _metaCurrencyLabel = GetNodeOrNull<Label>(MetaCurrencyLabelPath);
        _settingsMenu = GetNodeOrNull<SettingsMenu>(SettingsMenuPath);

        // Build missing Settings button / meta label if scene not yet extended.
        EnsureChrome();

        if (_startButton != null)
        {
            _startButton.Pressed += OnStartPressed;
        }

        if (_quitButton != null)
        {
            _quitButton.Pressed += OnQuitPressed;
        }

        if (_settingsButton != null)
        {
            _settingsButton.Pressed += OnSettingsPressed;
        }

        RefreshMetaLabel();
    }

    private void EnsureChrome()
    {
        Node vbox = GetNodeOrNull("CenterContainer/VBoxContainer");

        if (_metaCurrencyLabel == null)
        {
            _metaCurrencyLabel = new Label
            {
                Name = "MetaCurrencyLabel",
                HorizontalAlignment = HorizontalAlignment.Center,
                Text = "Blood Marks: 0"
            };
            _metaCurrencyLabel.AddThemeColorOverride("font_color", new Color(0.85f, 0.7f, 0.25f));
            if (vbox != null)
            {
                // Insert under subtitle if present.
                vbox.AddChild(_metaCurrencyLabel);
                int subtitleIdx = -1;
                for (int i = 0; i < vbox.GetChildCount(); i++)
                {
                    if (vbox.GetChild(i).Name == "Subtitle")
                    {
                        subtitleIdx = i;
                        break;
                    }
                }

                if (subtitleIdx >= 0)
                {
                    vbox.MoveChild(_metaCurrencyLabel, subtitleIdx + 1);
                }
            }
            else
            {
                AddChild(_metaCurrencyLabel);
            }
        }

        if (_settingsButton == null && vbox != null)
        {
            _settingsButton = new Button
            {
                Name = "SettingsButton",
                Text = "Settings"
            };
            vbox.AddChild(_settingsButton);
            // Place before Quit if possible.
            Node quit = vbox.GetNodeOrNull("QuitButton");
            if (quit != null)
            {
                vbox.MoveChild(_settingsButton, quit.GetIndex());
            }
        }

        if (_settingsMenu == null)
        {
            // Instance SettingsMenu scene if present; else build a minimal in-code shell.
            var packed = GD.Load<PackedScene>("res://Scenes/UI/SettingsMenu.tscn");
            if (packed != null)
            {
                _settingsMenu = packed.Instantiate<SettingsMenu>();
                AddChild(_settingsMenu);
            }
        }
    }

    private void RefreshMetaLabel()
    {
        if (_metaCurrencyLabel != null)
        {
            _metaCurrencyLabel.Text = $"Blood Marks: {MetaSave.GetMetaCurrency()}";
        }
    }

    private void OnStartPressed()
    {
        GetTree().ChangeSceneToFile(CharacterSelectScenePath);
    }

    private void OnSettingsPressed()
    {
        _settingsMenu?.Open();
    }

    private void OnQuitPressed()
    {
        GetTree().Quit();
    }
}
