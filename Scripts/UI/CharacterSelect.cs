using System.Collections.Generic;
using Godot;
using Nightbane.Autoloads;
using Nightbane.Meta;
using Nightbane.Resources;

namespace Nightbane.UI;

/// <summary>
/// Character-select: scans CharacterDataFolder, greys out locked hunters, unlock-purchase via
/// meta-currency (MetaSave). Confirm stashes pick on GameManager and loads Arena.
/// </summary>
public partial class CharacterSelect : Control
{
    [Export] public string CharacterDataFolder { get; set; } = "res://Resources/CharacterData/Data";
    [Export] public string ArenaScenePath { get; set; } = "res://Scenes/Arena/Arena.tscn";

    [ExportGroup("Wiring")]
    [Export] public NodePath RosterContainerPath { get; set; }
    [Export] public NodePath NameLabelPath { get; set; }
    [Export] public NodePath LoreLabelPath { get; set; }
    [Export] public NodePath StatsLabelPath { get; set; }
    [Export] public NodePath PassiveLabelPath { get; set; }
    [Export] public NodePath DifficultyLabelPath { get; set; }
    [Export] public NodePath BeginButtonPath { get; set; }
    [Export] public NodePath BackButtonPath { get; set; }
    [Export] public NodePath MetaCurrencyLabelPath { get; set; }
    [Export] public NodePath UnlockButtonPath { get; set; }
    [Export] public NodePath UnlockStatusLabelPath { get; set; }

    private VBoxContainer _rosterContainer;
    private Label _nameLabel;
    private Label _loreLabel;
    private Label _statsLabel;
    private Label _passiveLabel;
    private Label _difficultyLabel;
    private Button _beginButton;
    private Button _backButton;
    private Label _metaCurrencyLabel;
    private Button _unlockButton;
    private Label _unlockStatusLabel;

    private readonly List<CharacterData> _roster = new();
    private readonly Dictionary<string, Button> _rosterButtons = new();
    private CharacterData _selected;
    private ButtonGroup _rosterButtonGroup;

    public override void _Ready()
    {
        MetaSave.EnsureLoaded();

        _rosterContainer = GetNodeOrNull<VBoxContainer>(RosterContainerPath);
        _nameLabel = GetNodeOrNull<Label>(NameLabelPath);
        _loreLabel = GetNodeOrNull<Label>(LoreLabelPath);
        _statsLabel = GetNodeOrNull<Label>(StatsLabelPath);
        _passiveLabel = GetNodeOrNull<Label>(PassiveLabelPath);
        _difficultyLabel = GetNodeOrNull<Label>(DifficultyLabelPath);
        _beginButton = GetNodeOrNull<Button>(BeginButtonPath);
        _backButton = GetNodeOrNull<Button>(BackButtonPath);
        _metaCurrencyLabel = GetNodeOrNull<Label>(MetaCurrencyLabelPath);
        _unlockButton = GetNodeOrNull<Button>(UnlockButtonPath);
        _unlockStatusLabel = GetNodeOrNull<Label>(UnlockStatusLabelPath);

        // Code-built labels if scene wiring omitted (placeholder-friendly).
        EnsureMetaUi();

        if (_beginButton != null)
        {
            _beginButton.Disabled = true;
            _beginButton.Pressed += OnBeginPressed;
        }

        if (_backButton != null)
        {
            _backButton.Pressed += OnBackPressed;
        }

        if (_unlockButton != null)
        {
            _unlockButton.Pressed += OnUnlockPressed;
        }

        RefreshMetaLabel();
        LoadRoster();
        BuildRosterButtons();
    }

    private void EnsureMetaUi()
    {
        // Prefer scene-wired nodes; otherwise attach a small bar under Title area.
        if (_metaCurrencyLabel == null)
        {
            _metaCurrencyLabel = new Label
            {
                Name = "MetaCurrencyLabel",
                Text = "Blood Marks: 0",
                HorizontalAlignment = HorizontalAlignment.Right
            };
            _metaCurrencyLabel.AddThemeColorOverride("font_color", new Color(0.85f, 0.7f, 0.25f));
            _metaCurrencyLabel.SetAnchorsPreset(LayoutPreset.TopWide);
            _metaCurrencyLabel.OffsetTop = 20;
            _metaCurrencyLabel.OffsetRight = -24;
            _metaCurrencyLabel.OffsetBottom = 48;
            AddChild(_metaCurrencyLabel);
        }

        if (_unlockButton == null || _unlockStatusLabel == null)
        {
            Node detail = GetNodeOrNull("Margin/HBox/Detail");
            if (detail is VBoxContainer vbox)
            {
                if (_unlockStatusLabel == null)
                {
                    _unlockStatusLabel = new Label
                    {
                        Name = "UnlockStatusLabel",
                        AutowrapMode = TextServer.AutowrapMode.WordSmart
                    };
                    _unlockStatusLabel.AddThemeColorOverride("font_color", new Color(0.7f, 0.55f, 0.55f));
                    // Insert above spacer if present.
                    int spacerIdx = -1;
                    for (int i = 0; i < vbox.GetChildCount(); i++)
                    {
                        if (vbox.GetChild(i).Name == "Spacer")
                        {
                            spacerIdx = i;
                            break;
                        }
                    }

                    if (spacerIdx >= 0)
                    {
                        vbox.AddChild(_unlockStatusLabel);
                        vbox.MoveChild(_unlockStatusLabel, spacerIdx);
                    }
                    else
                    {
                        vbox.AddChild(_unlockStatusLabel);
                    }
                }

                if (_unlockButton == null)
                {
                    _unlockButton = new Button
                    {
                        Name = "UnlockButton",
                        Text = "Unlock",
                        Visible = false
                    };
                    Node buttonRow = vbox.GetNodeOrNull("ButtonRow");
                    if (buttonRow != null)
                    {
                        buttonRow.AddChild(_unlockButton);
                        buttonRow.MoveChild(_unlockButton, 0);
                    }
                    else
                    {
                        vbox.AddChild(_unlockButton);
                    }
                }
            }
        }
    }

    private void LoadRoster()
    {
        _roster.Clear();

        DirAccess dir = DirAccess.Open(CharacterDataFolder);
        if (dir == null)
        {
            GD.PushWarning($"[CharacterSelect] Could not open CharacterDataFolder '{CharacterDataFolder}'.");
            return;
        }

        dir.ListDirBegin();
        for (string fileName = dir.GetNext(); fileName != ""; fileName = dir.GetNext())
        {
            if (dir.CurrentIsDir() || !fileName.EndsWith(".tres"))
            {
                continue;
            }

            var data = GD.Load<CharacterData>($"{CharacterDataFolder}/{fileName}");
            if (data != null)
            {
                _roster.Add(data);
            }
        }
        dir.ListDirEnd();

        _roster.Sort((a, b) => string.CompareOrdinal(a.CharacterName, b.CharacterName));
    }

    private void BuildRosterButtons()
    {
        if (_rosterContainer == null)
        {
            return;
        }

        foreach (Node child in _rosterContainer.GetChildren())
        {
            child.QueueFree();
        }

        _rosterButtons.Clear();
        _rosterButtonGroup = new ButtonGroup();

        CharacterData firstUnlocked = null;

        foreach (CharacterData data in _roster)
        {
            bool unlocked = MetaSave.IsCharacterUnlocked(data.CharacterName);
            int cost = MetaSave.GetCharacterUnlockCost(data.DifficultyRating);

            var button = new Button
            {
                Text = unlocked
                    ? $"{data.CharacterName}  (Diff {data.DifficultyRating}/5)"
                    : $"???  {data.CharacterName}  [{cost} BM]",
                ToggleMode = true,
                ButtonGroup = _rosterButtonGroup,
                Modulate = unlocked ? Colors.White : new Color(0.45f, 0.45f, 0.5f, 1f)
            };
            CharacterData captured = data;
            button.Pressed += () => SelectCharacter(captured);
            _rosterContainer.AddChild(button);
            _rosterButtons[data.CharacterName] = button;

            if (unlocked && firstUnlocked == null)
            {
                firstUnlocked = data;
            }
        }

        CharacterData initial = firstUnlocked ?? (_roster.Count > 0 ? _roster[0] : null);
        if (initial != null)
        {
            SelectCharacter(initial);
            if (_rosterButtons.TryGetValue(initial.CharacterName, out Button btn))
            {
                btn.ButtonPressed = true;
            }
        }
    }

    private void SelectCharacter(CharacterData data)
    {
        _selected = data;
        bool unlocked = MetaSave.IsCharacterUnlocked(data.CharacterName);
        int cost = MetaSave.GetCharacterUnlockCost(data.DifficultyRating);

        if (_nameLabel != null)
        {
            _nameLabel.Text = unlocked ? data.CharacterName : $"{data.CharacterName} (LOCKED)";
        }

        if (_loreLabel != null)
        {
            _loreLabel.Text = unlocked ? data.LoreBlurb : "Locked. Spend Blood Marks to unlock this Hunter.";
        }

        if (_difficultyLabel != null)
        {
            _difficultyLabel.Text = $"Difficulty: {data.DifficultyRating}/5";
        }

        if (_statsLabel != null)
        {
            _statsLabel.Text = unlocked
                ? $"HP {data.MaxHealth}   Speed {data.MoveSpeed:F0}   Armor {data.StartingArmor}\n" +
                  $"Dodge {data.StartingDodgeChance:P0}   Crit {data.StartingCritChance:P0}   Magic x{data.StartingMagicPower:F1}"
                : "Stats hidden until unlocked.";
        }

        if (_passiveLabel != null)
        {
            if (unlocked)
            {
                string passiveName = string.IsNullOrEmpty(data.PassiveName) ? "—" : data.PassiveName;
                _passiveLabel.Text = $"{passiveName}\n{data.PassiveDescription}";
            }
            else
            {
                _passiveLabel.Text = "Passive hidden.";
            }
        }

        if (_beginButton != null)
        {
            _beginButton.Disabled = !unlocked;
        }

        if (_unlockButton != null)
        {
            _unlockButton.Visible = !unlocked;
            _unlockButton.Disabled = unlocked || MetaSave.GetMetaCurrency() < cost;
            _unlockButton.Text = unlocked ? "Unlocked" : $"Unlock ({cost} Blood Marks)";
        }

        if (_unlockStatusLabel != null)
        {
            if (unlocked)
            {
                _unlockStatusLabel.Text = "Ready to hunt.";
            }
            else if (MetaSave.GetMetaCurrency() < cost)
            {
                _unlockStatusLabel.Text = $"Need {cost} Blood Marks (have {MetaSave.GetMetaCurrency()}).";
            }
            else
            {
                _unlockStatusLabel.Text = $"Unlock for {cost} Blood Marks.";
            }
        }
    }

    private void OnUnlockPressed()
    {
        if (_selected == null)
        {
            return;
        }

        if (MetaSave.IsCharacterUnlocked(_selected.CharacterName))
        {
            return;
        }

        int cost = MetaSave.GetCharacterUnlockCost(_selected.DifficultyRating);
        if (!MetaSave.TryUnlockCharacter(_selected.CharacterName, cost))
        {
            if (_unlockStatusLabel != null)
            {
                _unlockStatusLabel.Text = "Not enough Blood Marks.";
            }

            return;
        }

        RefreshMetaLabel();
        RefreshRosterButton(_selected);
        SelectCharacter(_selected);
    }

    private void RefreshRosterButton(CharacterData data)
    {
        if (!_rosterButtons.TryGetValue(data.CharacterName, out Button button))
        {
            return;
        }

        bool unlocked = MetaSave.IsCharacterUnlocked(data.CharacterName);
        button.Text = unlocked
            ? $"{data.CharacterName}  (Diff {data.DifficultyRating}/5)"
            : $"???  {data.CharacterName}  [{MetaSave.GetCharacterUnlockCost(data.DifficultyRating)} BM]";
        button.Modulate = unlocked ? Colors.White : new Color(0.45f, 0.45f, 0.5f, 1f);
    }

    private void RefreshMetaLabel()
    {
        if (_metaCurrencyLabel != null)
        {
            _metaCurrencyLabel.Text = $"Blood Marks: {MetaSave.GetMetaCurrency()}";
        }
    }

    private void OnBeginPressed()
    {
        if (_selected == null || !MetaSave.IsCharacterUnlocked(_selected.CharacterName))
        {
            return;
        }

        GameManager.Instance.SelectedCharacter = _selected;
        GameManager.Instance.StartNewRun();
        GetTree().ChangeSceneToFile(ArenaScenePath);
    }

    private void OnBackPressed()
    {
        GetTree().ChangeSceneToFile("res://Scenes/MainMenu/MainMenu.tscn");
    }
}
