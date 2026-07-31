using System;
using System.Collections.Generic;
using Godot;
using Nightbane.Autoloads;
using Nightbane.PlayerCharacter;
using Nightbane.Resources;

namespace Nightbane.UI;

/// <summary>
/// Level-up choice screen: on EventBus.OnPlayerLevelUp it rolls a few random, non-repeating
/// upgrades from UpgradePool, shows RootPanel (ProcessMode.Always so its buttons still respond
/// while PlayerStats has paused the tree), and applies whichever one is picked to PlayerStats.
/// </summary>
public partial class LevelUpUI : CanvasLayer
{
    [Export] public UpgradePoolData UpgradePool { get; set; }
    [Export] public int ChoiceCount { get; set; } = 3;

    [ExportGroup("Wiring")]
    [Export] public NodePath RootPanelPath { get; set; }
    [Export] public NodePath[] ChoiceButtonPaths { get; set; } = Array.Empty<NodePath>();
    [Export] public NodePath[] ChoiceNamePaths { get; set; } = Array.Empty<NodePath>();
    [Export] public NodePath[] ChoiceDescriptionPaths { get; set; } = Array.Empty<NodePath>();

    private Control _rootPanel;
    private readonly List<Button> _choiceButtons = new();
    private readonly List<Label> _choiceNames = new();
    private readonly List<Label> _choiceDescriptions = new();
    private readonly List<UpgradeData> _currentChoices = new();

    public override void _Ready()
    {
        // Lets the buttons still receive input/process while GetTree().Paused is true for the
        // level-up screen itself; everything else in the run stays frozen (default Pausable).
        ProcessMode = ProcessModeEnum.Always;

        UpgradePool ??= GD.Load<UpgradePoolData>("res://Resources/UpgradeData/Data/StandardUpgradePool.tres");
        _rootPanel = GetNodeOrNull<Control>(RootPanelPath);

        for (int i = 0; i < ChoiceButtonPaths.Length; i++)
        {
            _choiceButtons.Add(GetNodeOrNull<Button>(ChoiceButtonPaths[i]));
            _choiceNames.Add(i < ChoiceNamePaths.Length ? GetNodeOrNull<Label>(ChoiceNamePaths[i]) : null);
            _choiceDescriptions.Add(i < ChoiceDescriptionPaths.Length ? GetNodeOrNull<Label>(ChoiceDescriptionPaths[i]) : null);

            int choiceIndex = i; // capture by value for the closure below
            if (_choiceButtons[i] != null)
            {
                _choiceButtons[i].Pressed += () => OnChoiceSelected(choiceIndex);
            }
        }

        if (_rootPanel != null)
        {
            _rootPanel.Visible = false;
        }

        EventBus.Instance.OnPlayerLevelUp += OnPlayerLevelUp;
    }

    private void OnPlayerLevelUp(int newLevel)
    {
        AudioManager.Instance?.PlaySfx("ui_levelup");
        RollChoices();

        if (_rootPanel != null)
        {
            _rootPanel.Visible = true;
        }
    }

    /// <summary>Weighted, non-repeating draw of ChoiceCount upgrades from the pool, then pushes the result into the choice cards.</summary>
    private void RollChoices()
    {
        _currentChoices.Clear();

        var remaining = new List<UpgradeData>(UpgradePool?.Upgrades ?? Array.Empty<UpgradeData>());
        int drawCount = Mathf.Min(ChoiceCount, remaining.Count);

        for (int i = 0; i < drawCount; i++)
        {
            UpgradeData picked = WeightedPick(remaining);
            _currentChoices.Add(picked);
            remaining.Remove(picked);
        }

        for (int i = 0; i < _choiceButtons.Count; i++)
        {
            if (_choiceButtons[i] == null)
            {
                continue;
            }

            bool hasChoice = i < _currentChoices.Count;
            _choiceButtons[i].Visible = hasChoice;
            _choiceButtons[i].Disabled = !hasChoice;

            if (hasChoice)
            {
                UpgradeData upgrade = _currentChoices[i];
                if (_choiceNames[i] != null) _choiceNames[i].Text = upgrade.DisplayName;
                if (_choiceDescriptions[i] != null) _choiceDescriptions[i].Text = upgrade.Description;
            }
        }
    }

    /// <summary>Weighted random pick over UpgradeData.Weight, mirroring WaveManager's enemy-pool roll.</summary>
    private static UpgradeData WeightedPick(List<UpgradeData> pool)
    {
        float totalWeight = 0f;
        foreach (UpgradeData upgrade in pool)
        {
            totalWeight += Mathf.Max(0f, upgrade.Weight);
        }

        if (totalWeight <= 0f)
        {
            return pool[0];
        }

        float roll = GD.Randf() * totalWeight;
        foreach (UpgradeData upgrade in pool)
        {
            roll -= Mathf.Max(0f, upgrade.Weight);
            if (roll <= 0f)
            {
                return upgrade;
            }
        }

        return pool[^1];
    }

    private void OnChoiceSelected(int index)
    {
        if (index >= _currentChoices.Count)
        {
            return;
        }

        ApplyUpgrade(_currentChoices[index]);

        if (_rootPanel != null)
        {
            _rootPanel.Visible = false;
        }

        PlayerStats.Instance?.ConfirmUpgradeSelected();
    }

    private static void ApplyUpgrade(UpgradeData upgrade)
    {
        PlayerStats stats = PlayerStats.Instance;
        if (stats == null)
        {
            return;
        }

        switch (upgrade.UpgradeType)
        {
            case UpgradeType.DamageBoost:
                stats.ApplyDamageUpgrade(upgrade.Value);
                break;
            case UpgradeType.MoveSpeedBoost:
                stats.ApplyMoveSpeedUpgrade(upgrade.Value);
                break;
            case UpgradeType.MaxHealthBoost:
                stats.ApplyMaxHealthUpgrade(Mathf.RoundToInt(upgrade.Value));
                break;
            case UpgradeType.Passive:
                // Stage stub: no relic/passive-item system exists yet, just acknowledge the pick.
                GD.Print($"[LevelUpUI] Passive relic '{upgrade.Id}' selected (placeholder, no effect yet).");
                break;
        }
    }
}
