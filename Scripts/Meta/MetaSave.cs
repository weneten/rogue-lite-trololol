using System.Collections.Generic;
using System.Text.Json;
using Godot;

namespace Nightbane.Meta;

/// <summary>
/// Persistent meta-progression: meta-currency + unlocked characters/weapons.
/// JSON at user://nightbane_meta.json via Godot FileAccess.
/// </summary>
public static class MetaSave
{
    public const string SavePath = "user://nightbane_meta.json";

    /// <summary>Default free starter hunters (by CharacterName). All base roster playable at first launch.</summary>
    private static readonly string[] DefaultUnlockedCharacters =
    {
        "Witch Hunter",
        "The Reaper",
        "Silver Priest",
        "Bloodletter",
        "Bloodstained Crusader",
        "Pyromancer",
        "Grave Warden",
        "Moonlit Duelist",
        "Alchemist",
        "Cursed Noble",
    };

    public static int MetaCurrency { get; private set; }

    private static readonly HashSet<string> UnlockedCharacters = new();
    private static readonly HashSet<string> UnlockedWeapons = new();
    private static bool _loaded;

    public static void EnsureLoaded()
    {
        if (_loaded)
        {
            return;
        }

        Load();
    }

    public static void Load()
    {
        UnlockedCharacters.Clear();
        UnlockedWeapons.Clear();
        MetaCurrency = 0;

        if (!FileAccess.FileExists(SavePath))
        {
            ApplyDefaults();
            Save();
            _loaded = true;
            return;
        }

        using FileAccess file = FileAccess.Open(SavePath, FileAccess.ModeFlags.Read);
        if (file == null)
        {
            GD.PushWarning($"[MetaSave] Failed to open '{SavePath}' for read.");
            ApplyDefaults();
            _loaded = true;
            return;
        }

        string json = file.GetAsText();
        try
        {
            var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            MetaSaveDto data = JsonSerializer.Deserialize<MetaSaveDto>(
                string.IsNullOrWhiteSpace(json) ? "{}" : json, options) ?? new MetaSaveDto();

            MetaCurrency = Mathf.Max(0, data.MetaCurrency);
            if (data.UnlockedCharacters != null)
            {
                foreach (string name in data.UnlockedCharacters)
                {
                    if (!string.IsNullOrEmpty(name))
                    {
                        UnlockedCharacters.Add(name);
                    }
                }
            }

            if (data.UnlockedWeapons != null)
            {
                foreach (string name in data.UnlockedWeapons)
                {
                    if (!string.IsNullOrEmpty(name))
                    {
                        UnlockedWeapons.Add(name);
                    }
                }
            }
        }
        catch (JsonException ex)
        {
            GD.PushWarning($"[MetaSave] Corrupt save, resetting. {ex.Message}");
            UnlockedCharacters.Clear();
            UnlockedWeapons.Clear();
            MetaCurrency = 0;
        }

        ApplyDefaults();
        _loaded = true;
    }

    public static void Save()
    {
        var data = new MetaSaveDto
        {
            MetaCurrency = MetaCurrency,
            UnlockedCharacters = new List<string>(UnlockedCharacters),
            UnlockedWeapons = new List<string>(UnlockedWeapons)
        };

        string json = JsonSerializer.Serialize(data, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });
        using FileAccess file = FileAccess.Open(SavePath, FileAccess.ModeFlags.Write);
        if (file == null)
        {
            GD.PushError($"[MetaSave] Failed to open '{SavePath}' for write: {FileAccess.GetOpenError()}");
            return;
        }

        file.StoreString(json);
    }

    public static int GetMetaCurrency()
    {
        EnsureLoaded();
        return MetaCurrency;
    }

    public static void AddMetaCurrency(int amount)
    {
        EnsureLoaded();
        if (amount <= 0)
        {
            return;
        }

        MetaCurrency += amount;
        Save();
    }

    public static bool TrySpendMetaCurrency(int amount)
    {
        EnsureLoaded();
        if (amount < 0 || MetaCurrency < amount)
        {
            return false;
        }

        MetaCurrency -= amount;
        Save();
        return true;
    }

    public static bool IsCharacterUnlocked(string characterName)
    {
        EnsureLoaded();
        if (string.IsNullOrEmpty(characterName))
        {
            return false;
        }

        return UnlockedCharacters.Contains(characterName);
    }

    public static bool IsWeaponUnlocked(string weaponName)
    {
        EnsureLoaded();
        if (string.IsNullOrEmpty(weaponName))
        {
            return false;
        }

        return UnlockedWeapons.Contains(weaponName);
    }

    /// <summary>Unlock cost from DifficultyRating (1-5). Diff 1 free-tier; others scale.</summary>
    public static int GetCharacterUnlockCost(int difficultyRating)
    {
        int d = Mathf.Clamp(difficultyRating, 1, 5);
        if (d <= 1)
        {
            return 0;
        }

        // Diff2=50, Diff3=150, Diff4=300, Diff5=500
        return d * (d - 1) * 25;
    }

    public static bool TryUnlockCharacter(string characterName, int cost)
    {
        EnsureLoaded();
        if (string.IsNullOrEmpty(characterName) || UnlockedCharacters.Contains(characterName))
        {
            return false;
        }

        if (cost > 0 && !TrySpendMetaCurrency(cost))
        {
            return false;
        }

        UnlockedCharacters.Add(characterName);
        Save();
        return true;
    }

    public static bool TryUnlockWeapon(string weaponName, int cost)
    {
        EnsureLoaded();
        if (string.IsNullOrEmpty(weaponName) || UnlockedWeapons.Contains(weaponName))
        {
            return false;
        }

        if (cost > 0 && !TrySpendMetaCurrency(cost))
        {
            return false;
        }

        UnlockedWeapons.Add(weaponName);
        Save();
        return true;
    }

    public static IReadOnlyCollection<string> GetUnlockedCharacters()
    {
        EnsureLoaded();
        return UnlockedCharacters;
    }

    public static IReadOnlyCollection<string> GetUnlockedWeapons()
    {
        EnsureLoaded();
        return UnlockedWeapons;
    }

    private static void ApplyDefaults()
    {
        foreach (string name in DefaultUnlockedCharacters)
        {
            UnlockedCharacters.Add(name);
        }
    }
}

/// <summary>DTO for user://nightbane_meta.json (System.Text.Json).</summary>
public sealed class MetaSaveDto
{
    public int MetaCurrency { get; set; }
    public List<string> UnlockedCharacters { get; set; } = new();
    public List<string> UnlockedWeapons { get; set; } = new();
}
