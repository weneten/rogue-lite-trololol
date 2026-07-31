using System;
using Godot;
using Nightbane.Autoloads;

namespace Nightbane.UI;

/// <summary>
/// Volume sliders + key-rebind stub. Talks to AudioManager only via public API
/// (SetMasterVolume/SetMusicVolume/SetSfxVolume methods OR MasterVolume/MusicVolume/SfxVolume
/// properties) with null-checks — Audio stage owns AudioManager internals.
/// </summary>
public partial class SettingsMenu : CanvasLayer
{
    [Export] public NodePath RootPanelPath { get; set; }
    [Export] public NodePath MasterSliderPath { get; set; }
    [Export] public NodePath MusicSliderPath { get; set; }
    [Export] public NodePath SfxSliderPath { get; set; }
    [Export] public NodePath CloseButtonPath { get; set; }
    [Export] public NodePath RebindStubButtonPath { get; set; }
    [Export] public NodePath RebindStatusLabelPath { get; set; }

    private Control _rootPanel;
    private HSlider _masterSlider;
    private HSlider _musicSlider;
    private HSlider _sfxSlider;
    private Button _closeButton;
    private Button _rebindStubButton;
    private Label _rebindStatusLabel;

    public bool IsOpen { get; private set; }

    public override void _Ready()
    {
        ProcessMode = ProcessModeEnum.Always;
        Layer = 90;

        _rootPanel = GetNodeOrNull<Control>(RootPanelPath);
        _masterSlider = GetNodeOrNull<HSlider>(MasterSliderPath);
        _musicSlider = GetNodeOrNull<HSlider>(MusicSliderPath);
        _sfxSlider = GetNodeOrNull<HSlider>(SfxSliderPath);
        _closeButton = GetNodeOrNull<Button>(CloseButtonPath);
        _rebindStubButton = GetNodeOrNull<Button>(RebindStubButtonPath);
        _rebindStatusLabel = GetNodeOrNull<Label>(RebindStatusLabelPath);

        ConfigureSlider(_masterSlider, GetAudioVolume("Master"), OnMasterChanged);
        ConfigureSlider(_musicSlider, GetAudioVolume("Music"), OnMusicChanged);
        ConfigureSlider(_sfxSlider, GetAudioVolume("Sfx"), OnSfxChanged);

        if (_closeButton != null)
        {
            _closeButton.Pressed += Close;
        }

        if (_rebindStubButton != null)
        {
            _rebindStubButton.Pressed += OnRebindStubPressed;
        }

        if (_rootPanel != null)
        {
            _rootPanel.Visible = false;
        }

        IsOpen = false;
    }

    public void Open()
    {
        if (_rootPanel != null)
        {
            _rootPanel.Visible = true;
        }

        SyncSlidersFromAudio();
        IsOpen = true;
    }

    public void Close()
    {
        if (_rootPanel != null)
        {
            _rootPanel.Visible = false;
        }

        IsOpen = false;
    }

    private void ConfigureSlider(HSlider slider, float value, Action<float> onChanged)
    {
        if (slider == null)
        {
            return;
        }

        slider.MinValue = 0.0;
        slider.MaxValue = 1.0;
        slider.Step = 0.01;
        slider.Value = value;
        slider.ValueChanged += v => onChanged((float)v);
    }

    private void SyncSlidersFromAudio()
    {
        if (_masterSlider != null) _masterSlider.Value = GetAudioVolume("Master");
        if (_musicSlider != null) _musicSlider.Value = GetAudioVolume("Music");
        if (_sfxSlider != null) _sfxSlider.Value = GetAudioVolume("Sfx");
    }

    private void OnMasterChanged(float value) => SetAudioVolume("Master", value);
    private void OnMusicChanged(float value) => SetAudioVolume("Music", value);
    private void OnSfxChanged(float value) => SetAudioVolume("Sfx", value);

    private void OnRebindStubPressed()
    {
        if (_rebindStatusLabel != null)
        {
            _rebindStatusLabel.Text = "Key rebinding coming soon.";
        }
    }

    /// <summary>
    /// Prefer SetXVolume(float) if present; else assign XVolume property. Silent no-op if neither.
    /// </summary>
    private static void SetAudioVolume(string channel, float value)
    {
        AudioManager audio = AudioManager.Instance;
        if (audio == null)
        {
            return;
        }

        value = Mathf.Clamp(value, 0f, 1f);
        string method = $"Set{channel}Volume";
        if (audio.HasMethod(method))
        {
            audio.Call(method, value);
            return;
        }

        switch (channel)
        {
            case "Master":
                audio.MasterVolume = value;
                break;
            case "Music":
                audio.MusicVolume = value;
                break;
            case "Sfx":
                audio.SfxVolume = value;
                break;
        }
    }

    private static float GetAudioVolume(string channel)
    {
        AudioManager audio = AudioManager.Instance;
        if (audio == null)
        {
            return 1f;
        }

        return channel switch
        {
            "Master" => audio.MasterVolume,
            "Music" => audio.MusicVolume,
            "Sfx" => audio.SfxVolume,
            _ => 1f
        };
    }
}
