using System.Collections.Generic;
using Godot;

namespace Nightbane.Autoloads;

/// <summary>
/// Music/SFX hub. Shop phase = calm track; combat waves = layered base+percussion with
/// intensity-driven percussion volume; boss = public PlayBossMusic/StopBossMusic plus
/// defensive EventBus boss-signal hooks (Bosses stage may add them later). Volume API
/// routes through Master/Music/SFX AudioServer buses for SettingsMenu.
/// </summary>
public partial class AudioManager : Node
{
    public static AudioManager Instance { get; private set; }

    private const string BusMaster = "Master";
    private const string BusMusic = "Music";
    private const string BusSfx = "SFX";

    private const int SfxPoolSize = 8;
    private const float CrossfadeSeconds = 0.85f;
    private const float IntensityLerpSpeed = 2.5f;

    /// <summary>Boss-wave fallback until Bosses stage wires PlayBossMusic / OnBossEncounter*.</summary>
    private static readonly HashSet<int> BossFallbackWaves = new() { 10, 15, 20 };

    [Export] public float MasterVolume { get; set; } = 1.0f;
    [Export] public float MusicVolume { get; set; } = 1.0f;
    [Export] public float SfxVolume { get; set; } = 1.0f;

    // --- Stream placeholders (null = silence-safe; assign assets later) ---
    // TODO: replace with final audio asset
    [Export] public AudioStream ShopMusicStream { get; set; }
    // TODO: replace with final audio asset
    [Export] public AudioStream CombatBaseStream { get; set; }
    // TODO: replace with final audio asset
    [Export] public AudioStream CombatPercussionStream { get; set; }
    // TODO: replace with final audio asset
    [Export] public AudioStream BossMusicStream { get; set; }
    // TODO: replace with final audio asset
    [Export] public AudioStream MenuMusicStream { get; set; }

    // SFX stream map filled in _Ready with null placeholders until assets land.
    private readonly Dictionary<string, AudioStream> _sfxStreams = new();

    private AudioStreamPlayer _shopMusic;
    private AudioStreamPlayer _combatBase;
    private AudioStreamPlayer _combatPercussion;
    private AudioStreamPlayer _bossMusic;
    private AudioStreamPlayer _menuMusic;

    private readonly List<AudioStreamPlayer> _sfxPool = new();
    private int _sfxPoolIndex;

    private enum MusicMode
    {
        None,
        Menu,
        Shop,
        Combat,
        Boss
    }

    private MusicMode _mode = MusicMode.None;
    private MusicMode _targetMode = MusicMode.None;
    private float _crossfadeT = 1f;
    private float _intensity; // 0..1, drives percussion layer
    private float _targetIntensity;
    private bool _bossActive;
    private int _currentWave;

    public override void _EnterTree()
    {
        Instance = this;
    }

    public override void _ExitTree()
    {
        if (Instance == this)
        {
            Instance = null;
        }
    }

    public override void _Ready()
    {
        EnsureBuses();
        BuildPlayers();
        RegisterPlaceholderSfx();
        ApplyAllVolumes();
        SubscribeGameplay();
        TrySubscribeBossSignals();

        // Default: menu bed when booting into MainMenu.
        PlayMusic("menu");
    }

    public override void _Process(double delta)
    {
        float dt = (float)delta;
        UpdateIntensity(dt);
        UpdateCrossfade(dt);
        ApplyPercussionVolume();
    }

    // -------------------------------------------------------------------------
    // Public API (stable)
    // -------------------------------------------------------------------------

    public void PlaySfx(string sfxId)
    {
        if (string.IsNullOrEmpty(sfxId))
        {
            return;
        }

        _sfxStreams.TryGetValue(sfxId, out AudioStream stream);
        // Silence-safe: missing/null stream = no audible output, still log for hook wiring.
        if (stream == null)
        {
            // TODO: replace with final audio asset
            return;
        }

        AudioStreamPlayer player = _sfxPool[_sfxPoolIndex];
        _sfxPoolIndex = (_sfxPoolIndex + 1) % _sfxPool.Count;
        player.Stream = stream;
        player.Play();
    }

    public void PlayMusic(string trackId)
    {
        if (string.IsNullOrEmpty(trackId))
        {
            return;
        }

        switch (trackId.ToLowerInvariant())
        {
            case "menu":
                RequestMode(MusicMode.Menu);
                break;
            case "shop":
                RequestMode(MusicMode.Shop);
                break;
            case "combat":
            case "wave":
                if (!_bossActive)
                {
                    RequestMode(MusicMode.Combat);
                }
                break;
            case "boss":
                PlayBossMusic();
                break;
            case "stop":
            case "none":
                RequestMode(MusicMode.None);
                break;
            default:
                GD.Print($"[AudioManager] Unknown music trackId '{trackId}'");
                break;
        }
    }

    /// <summary>Boss encounter spike. Bosses stage should call this when a boss spawns.</summary>
    public void PlayBossMusic()
    {
        _bossActive = true;
        RequestMode(MusicMode.Boss);
        _targetIntensity = 1f;
    }

    /// <summary>End boss theme; returns to combat layers if a wave is active, else shop.</summary>
    public void StopBossMusic()
    {
        _bossActive = false;
        if (WaveManager.Instance != null && WaveManager.Instance.IsWaveActive)
        {
            RequestMode(MusicMode.Combat);
        }
        else
        {
            RequestMode(MusicMode.Shop);
        }
    }

    public void SetMasterVolume(float linear01)
    {
        MasterVolume = Mathf.Clamp(linear01, 0f, 1f);
        SetBusLinear(BusMaster, MasterVolume);
    }

    public void SetMusicVolume(float linear01)
    {
        MusicVolume = Mathf.Clamp(linear01, 0f, 1f);
        SetBusLinear(BusMusic, MusicVolume);
    }

    public void SetSfxVolume(float linear01)
    {
        SfxVolume = Mathf.Clamp(linear01, 0f, 1f);
        SetBusLinear(BusSfx, SfxVolume);
    }

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    private void EnsureBuses()
    {
        // Master always exists. Music + SFX are created if missing so SettingsMenu can drive them
        // without a hand-authored default_bus_layout.tres.
        EnsureBus(BusMusic, BusMaster);
        EnsureBus(BusSfx, BusMaster);
    }

    private static void EnsureBus(string name, string sendTo)
    {
        if (AudioServer.GetBusIndex(name) >= 0)
        {
            return;
        }

        int idx = AudioServer.BusCount;
        AudioServer.AddBus();
        AudioServer.SetBusName(idx, name);
        AudioServer.SetBusSend(idx, sendTo);
    }

    private void BuildPlayers()
    {
        _shopMusic = MakeMusicPlayer("ShopMusic", ShopMusicStream);
        _combatBase = MakeMusicPlayer("CombatBase", CombatBaseStream);
        _combatPercussion = MakeMusicPlayer("CombatPercussion", CombatPercussionStream);
        _bossMusic = MakeMusicPlayer("BossMusic", BossMusicStream);
        _menuMusic = MakeMusicPlayer("MenuMusic", MenuMusicStream);

        for (int i = 0; i < SfxPoolSize; i++)
        {
            var sfx = new AudioStreamPlayer
            {
                Name = $"SfxPool_{i}",
                Bus = BusSfx,
                VolumeDb = 0f
            };
            AddChild(sfx);
            _sfxPool.Add(sfx);
        }
    }

    private AudioStreamPlayer MakeMusicPlayer(string name, AudioStream stream)
    {
        var player = new AudioStreamPlayer
        {
            Name = name,
            Bus = BusMusic,
            Stream = stream, // may be null — silence-safe until assets assigned
            VolumeDb = -80f,
            Autoplay = false
        };
        // TODO: replace with final audio asset
        AddChild(player);
        return player;
    }

    private void RegisterPlaceholderSfx()
    {
        // Keys used by EventBus hooks + call-site wires. Streams stay null until assets land.
        // TODO: replace with final audio asset
        string[] ids =
        {
            "enemy_death",
            "player_hit",
            "player_death",
            "weapon_melee",
            "weapon_ranged",
            "weapon_firearm",
            "weapon_magic",
            "weapon_holy",
            "weapon_cursed",
            "weapon_aoe",
            "weapon_summon",
            "weapon_trap",
            "weapon_hit",
            "ui_click",
            "ui_levelup",
            "ui_shop_open",
            "ui_purchase"
        };

        foreach (string id in ids)
        {
            _sfxStreams[id] = null; // silence-safe placeholder
            // TODO: replace with final audio asset
        }
    }

    private void ApplyAllVolumes()
    {
        SetMasterVolume(MasterVolume);
        SetMusicVolume(MusicVolume);
        SetSfxVolume(SfxVolume);
    }

    private static void SetBusLinear(string busName, float linear01)
    {
        int idx = AudioServer.GetBusIndex(busName);
        if (idx < 0)
        {
            return;
        }

        // 0 linear = mute (-80 dB floor); Godot LinearToDb(0) is -inf which AudioServer rejects.
        float db = linear01 <= 0.0001f ? -80f : Mathf.LinearToDb(linear01);
        AudioServer.SetBusVolumeDb(idx, db);
        AudioServer.SetBusMute(idx, linear01 <= 0.0001f);
    }

    // -------------------------------------------------------------------------
    // Event wiring
    // -------------------------------------------------------------------------

    private void SubscribeGameplay()
    {
        if (EventBus.Instance == null)
        {
            return;
        }

        EventBus.Instance.OnEnemyKilled += OnEnemyKilledSfx;
        EventBus.Instance.OnPlayerDamaged += OnPlayerDamagedSfx;
        EventBus.Instance.OnPlayerDied += OnPlayerDiedSfx;
        EventBus.Instance.OnWaveStart += OnWaveStartMusic;
        EventBus.Instance.OnWaveEnd += OnWaveEndMusic;
        // Level-up chime fired from LevelUpUI call site (not EventBus) to avoid double-play.
    }

    /// <summary>
    /// Bosses stage may add OnBossEncounterStart/End on EventBus concurrently. Connect by
    /// string name only if present so this autoload never hard-depends on missing signals.
    /// </summary>
    private void TrySubscribeBossSignals()
    {
        EventBus bus = EventBus.Instance;
        if (bus == null)
        {
            return;
        }

        // Typed C# events match EventBus signatures (name+wave / name+defeated).
        // Prefer these over zero-arg Callables so Godot never arity-mismatches.
        bus.OnBossEncounterStart += OnBossEncounterStartMusic;
        bus.OnBossEncounterEnd += OnBossEncounterEndMusic;
    }

    private void OnBossEncounterStartMusic(string bossName, int waveNumber)
    {
        PlayBossMusic();
    }

    private void OnBossEncounterEndMusic(string bossName, bool defeated)
    {
        StopBossMusic();
    }

    private void OnEnemyKilledSfx(Node enemy, int currencyReward, int experienceReward)
    {
        PlaySfx("enemy_death");
    }

    private void OnPlayerDamagedSfx(float damageAmount, float currentHealth)
    {
        PlaySfx("player_hit");
    }

    private void OnPlayerDiedSfx()
    {
        PlaySfx("player_death");
    }

    private void OnWaveStartMusic(int waveNumber)
    {
        _currentWave = waveNumber;

        // BossManager owns music via OnBossEncounterStart; only start combat bed here.
        // (Fallback waves kept as soft intensity bump if boss spawn fails.)
        if (!_bossActive)
        {
            if (BossFallbackWaves.Contains(waveNumber))
            {
                // Soft spike if BossManager has not yet flipped _bossActive this frame.
                _targetIntensity = 1f;
            }

            PlayMusic("combat");
        }
    }

    private void OnWaveEndMusic(int waveNumber)
    {
        if (_bossActive)
        {
            StopBossMusic();
        }

        PlayMusic("shop");
        PlaySfx("ui_shop_open");
        _targetIntensity = 0f;
    }

    // -------------------------------------------------------------------------
    // Music state / intensity
    // -------------------------------------------------------------------------

    private void RequestMode(MusicMode mode)
    {
        if (_targetMode == mode && _mode == mode && _crossfadeT >= 1f)
        {
            return;
        }

        _targetMode = mode;
        _crossfadeT = 0f;
        EnsureModePlaying(mode);
    }

    private void EnsureModePlaying(MusicMode mode)
    {
        // Start target players (looping streams) at low volume; crossfade ramps them.
        switch (mode)
        {
            case MusicMode.Menu:
                SafePlay(_menuMusic);
                break;
            case MusicMode.Shop:
                SafePlay(_shopMusic);
                break;
            case MusicMode.Combat:
                SafePlay(_combatBase);
                SafePlay(_combatPercussion);
                break;
            case MusicMode.Boss:
                SafePlay(_bossMusic);
                break;
        }
    }

    private static void SafePlay(AudioStreamPlayer player)
    {
        if (player == null || player.Stream == null)
        {
            // TODO: replace with final audio asset
            return;
        }

        if (!player.Playing)
        {
            player.Play();
        }
    }

    private void UpdateCrossfade(float dt)
    {
        if (_crossfadeT >= 1f && _mode == _targetMode)
        {
            return;
        }

        _crossfadeT = Mathf.Min(1f, _crossfadeT + dt / CrossfadeSeconds);
        float t = Smooth01(_crossfadeT);

        // Fade all music players toward their target role volumes.
        float menuVol = _targetMode == MusicMode.Menu ? t : (_mode == MusicMode.Menu ? 1f - t : 0f);
        float shopVol = _targetMode == MusicMode.Shop ? t : (_mode == MusicMode.Shop ? 1f - t : 0f);
        float combatVol = _targetMode == MusicMode.Combat ? t : (_mode == MusicMode.Combat ? 1f - t : 0f);
        float bossVol = _targetMode == MusicMode.Boss ? t : (_mode == MusicMode.Boss ? 1f - t : 0f);

        // When starting a fade from None, outgoing is 0; when finishing, lock mode.
        if (_mode == MusicMode.None && _targetMode != MusicMode.None)
        {
            menuVol = _targetMode == MusicMode.Menu ? t : 0f;
            shopVol = _targetMode == MusicMode.Shop ? t : 0f;
            combatVol = _targetMode == MusicMode.Combat ? t : 0f;
            bossVol = _targetMode == MusicMode.Boss ? t : 0f;
        }

        SetPlayerLinear(_menuMusic, menuVol);
        SetPlayerLinear(_shopMusic, shopVol);
        SetPlayerLinear(_combatBase, combatVol);
        // Percussion uses combatVol * intensity (applied in ApplyPercussionVolume).
        SetPlayerLinear(_bossMusic, bossVol);

        if (_crossfadeT >= 1f)
        {
            StopIfSilent(_menuMusic, menuVol);
            StopIfSilent(_shopMusic, shopVol);
            StopIfSilent(_combatBase, combatVol);
            StopIfSilent(_bossMusic, bossVol);
            if (_targetMode != MusicMode.Combat)
            {
                StopIfSilent(_combatPercussion, 0f);
            }

            _mode = _targetMode;
        }
    }

    private void ApplyPercussionVolume()
    {
        float combatPresence = 0f;
        if (_targetMode == MusicMode.Combat)
        {
            combatPresence = _mode == MusicMode.Combat ? 1f : _crossfadeT;
        }
        else if (_mode == MusicMode.Combat)
        {
            combatPresence = 1f - _crossfadeT;
        }

        SetPlayerLinear(_combatPercussion, combatPresence * _intensity);
    }

    private void UpdateIntensity(float dt)
    {
        if (_bossActive || _targetMode == MusicMode.Boss)
        {
            _targetIntensity = 1f;
        }
        else if (_targetMode == MusicMode.Combat || _mode == MusicMode.Combat)
        {
            _targetIntensity = ComputeCombatIntensity();
        }
        else
        {
            _targetIntensity = 0f;
        }

        _intensity = Mathf.MoveToward(_intensity, _targetIntensity, dt * IntensityLerpSpeed);
    }

    /// <summary>
    /// Blends wave number progress, active-wave time progress, and live enemy density (0..1).
    /// Percussion layer rides this so late/dense waves feel heavier.
    /// </summary>
    private float ComputeCombatIntensity()
    {
        // Wave ladder: wave 1 ~0.15, wave 20+ saturates.
        float waveFactor = Mathf.Clamp(_currentWave / 20f, 0f, 1f);

        float timeFactor = 0.5f;
        WaveManager waves = WaveManager.Instance;
        if (waves != null && waves.IsWaveActive)
        {
            // Prefer remaining-time progress; fall back if duration unknown.
            double remaining = waves.WaveTimeRemaining;
            // Approximate total duration from remaining growth: use 45s mid as soft ref.
            float approxTotal = Mathf.Clamp(20f + 3f * (_currentWave - 1), 20f, 90f);
            float elapsedFrac = 1f - Mathf.Clamp((float)remaining / approxTotal, 0f, 1f);
            timeFactor = elapsedFrac;
        }

        float density = 0f;
        SceneTree tree = GetTree();
        if (tree != null)
        {
            int enemies = tree.GetNodesInGroup("Enemy").Count;
            // Soft cap ~24 live enemies = full density layer.
            density = Mathf.Clamp(enemies / 24f, 0f, 1f);
        }

        return Mathf.Clamp(0.25f * waveFactor + 0.35f * timeFactor + 0.40f * density, 0f, 1f);
    }

    private static void SetPlayerLinear(AudioStreamPlayer player, float linear01)
    {
        if (player == null)
        {
            return;
        }

        linear01 = Mathf.Clamp(linear01, 0f, 1f);
        player.VolumeDb = linear01 <= 0.0001f ? -80f : Mathf.LinearToDb(linear01);
    }

    private static void StopIfSilent(AudioStreamPlayer player, float linear01)
    {
        if (player != null && linear01 <= 0.0001f && player.Playing)
        {
            player.Stop();
        }
    }

    private static float Smooth01(float t)
    {
        // Smoothstep ease for crossfades.
        t = Mathf.Clamp(t, 0f, 1f);
        return t * t * (3f - 2f * t);
    }
}
