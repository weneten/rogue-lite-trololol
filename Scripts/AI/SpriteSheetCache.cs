using System.Collections.Generic;
using System.Text.Json;
using Godot;

namespace Nightbane.AI;

/// <summary>
/// Builds and caches SpriteFrames from Nightbane sprite-sheet JSON + PNG pairs
/// (Assets/sprites/*/sheet.json + sheet.png). Shared across all enemy instances.
/// </summary>
public static class SpriteSheetCache
{
    private static readonly Dictionary<string, SpriteFrames> Cache = new();
    private static readonly Dictionary<string, Vector2> OriginCache = new();

    /// <summary>
    /// Loads or returns cached SpriteFrames for a sheet. jsonPath is optional — if empty,
    /// swaps .png → .json next to the sheet.
    /// </summary>
    public static SpriteFrames GetFrames(string sheetPath, string jsonPath = null)
    {
        if (string.IsNullOrEmpty(sheetPath))
        {
            return null;
        }

        if (Cache.TryGetValue(sheetPath, out SpriteFrames cached) && GodotObject.IsInstanceValid(cached))
        {
            return cached;
        }

        string resolvedJson = string.IsNullOrEmpty(jsonPath)
            ? System.IO.Path.ChangeExtension(sheetPath, ".json")
            : jsonPath;

        // Godot res:// paths: ChangeExtension works on "res://a/b.png" → "res://a/b.json"
        if (resolvedJson.StartsWith("res://") || resolvedJson.StartsWith("user://"))
        {
            int dot = sheetPath.LastIndexOf('.');
            if (string.IsNullOrEmpty(jsonPath) && dot > 0)
            {
                resolvedJson = sheetPath.Substring(0, dot) + ".json";
            }
        }

        Texture2D texture = GD.Load<Texture2D>(sheetPath);
        if (texture == null)
        {
            GD.PushError($"[SpriteSheetCache] Missing texture: {sheetPath}");
            return null;
        }

        if (!FileAccess.FileExists(resolvedJson))
        {
            GD.PushError($"[SpriteSheetCache] Missing json: {resolvedJson}");
            return null;
        }

        string jsonText;
        using (FileAccess file = FileAccess.Open(resolvedJson, FileAccess.ModeFlags.Read))
        {
            jsonText = file.GetAsText();
        }

        SheetMeta meta;
        try
        {
            meta = JsonSerializer.Deserialize<SheetMeta>(jsonText, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
        }
        catch (JsonException ex)
        {
            GD.PushError($"[SpriteSheetCache] Bad json '{resolvedJson}': {ex.Message}");
            return null;
        }

        if (meta == null || meta.Animations == null || meta.FrameWidth <= 0 || meta.FrameHeight <= 0)
        {
            GD.PushError($"[SpriteSheetCache] Incomplete meta: {resolvedJson}");
            return null;
        }

        int columns = meta.Columns > 0 ? meta.Columns : Mathf.Max(1, texture.GetWidth() / meta.FrameWidth);
        var frames = new SpriteFrames();

        foreach (KeyValuePair<string, AnimMeta> pair in meta.Animations)
        {
            string animName = pair.Key;
            AnimMeta anim = pair.Value;
            if (anim == null)
            {
                continue;
            }

            if (frames.HasAnimation(animName))
            {
                frames.RemoveAnimation(animName);
            }

            frames.AddAnimation(animName);
            frames.SetAnimationLoopMode(animName, anim.Loop
                ? SpriteFrames.LoopMode.Linear
                : SpriteFrames.LoopMode.None);
            float fps = anim.Fps > 0 ? anim.Fps : 10f;
            frames.SetAnimationSpeed(animName, fps);

            int[] indices = anim.Frames;
            if (indices == null || indices.Length == 0)
            {
                // Fall back to from/to inclusive range.
                int from = anim.From;
                int to = anim.To >= anim.From ? anim.To : anim.From;
                var list = new List<int>();
                for (int i = from; i <= to; i++)
                {
                    list.Add(i);
                }

                indices = list.ToArray();
            }

            foreach (int frameIndex in indices)
            {
                int col = frameIndex % columns;
                int row = frameIndex / columns;
                var atlas = new AtlasTexture
                {
                    Atlas = texture,
                    Region = new Rect2(
                        col * meta.FrameWidth,
                        row * meta.FrameHeight,
                        meta.FrameWidth,
                        meta.FrameHeight)
                };
                // Duration 1.0 in "frames" units; speed (fps) drives real-time playback.
                frames.AddFrame(animName, atlas, 1.0f);
            }
        }

        // Ensure baseline anims exist even if a sheet omits them (fallback to idle first frame).
        EnsureAnim(frames, "idle");
        EnsureAnim(frames, "run", fallback: "idle");
        EnsureAnim(frames, "hurt", fallback: "idle");
        EnsureAnim(frames, "death", fallback: "hurt");

        Cache[sheetPath] = frames;

        float ox = meta.Origin?.X ?? meta.FrameWidth * 0.5f;
        float oy = meta.Origin?.Y ?? meta.FrameHeight;
        // Offset so pivot (feet) sits on the CharacterBody2D origin when sprite is centered.
        OriginCache[sheetPath] = new Vector2(
            meta.FrameWidth * 0.5f - ox,
            meta.FrameHeight * 0.5f - oy);

        return frames;
    }

    public static Vector2 GetSpriteOffset(string sheetPath)
    {
        return OriginCache.TryGetValue(sheetPath, out Vector2 o) ? o : new Vector2(0, -26);
    }

    private static void EnsureAnim(SpriteFrames frames, string name, string fallback = null)
    {
        if (frames.HasAnimation(name) && frames.GetFrameCount(name) > 0)
        {
            return;
        }

        string source = fallback;
        if (source == null || !frames.HasAnimation(source) || frames.GetFrameCount(source) == 0)
        {
            // Pick any existing animation.
            string[] names = frames.GetAnimationNames();
            if (names == null || names.Length == 0)
            {
                return;
            }

            source = names[0];
        }

        if (frames.HasAnimation(name))
        {
            frames.RemoveAnimation(name);
        }

        frames.AddAnimation(name);
        frames.SetAnimationLoopMode(name, name is "idle" or "run"
            ? SpriteFrames.LoopMode.Linear
            : SpriteFrames.LoopMode.None);
        frames.SetAnimationSpeed(name, frames.GetAnimationSpeed(source));
        int count = frames.GetFrameCount(source);
        for (int i = 0; i < count; i++)
        {
            frames.AddFrame(name, frames.GetFrameTexture(source, i), frames.GetFrameDuration(source, i));
        }
    }

    private sealed class SheetMeta
    {
        public int FrameWidth { get; set; }
        public int FrameHeight { get; set; }
        public int Columns { get; set; }
        public OriginMeta Origin { get; set; }
        public Dictionary<string, AnimMeta> Animations { get; set; }
    }

    private sealed class OriginMeta
    {
        public float X { get; set; }
        public float Y { get; set; }
    }

    private sealed class AnimMeta
    {
        public int[] Frames { get; set; }
        public int From { get; set; }
        public int To { get; set; }
        public float Fps { get; set; } = 10f;
        public bool Loop { get; set; }
    }
}
