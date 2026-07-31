using System.Collections.Generic;
using Godot;

namespace Nightbane.AI;

/// <summary>
/// Builds and caches SpriteFrames from Nightbane sprite-sheet JSON + PNG pairs
/// under Assets/sprites. Shared across all enemy instances.
/// </summary>
public static class SpriteSheetCache
{
    private static readonly Dictionary<string, SpriteFrames> Cache = new();
    private static readonly Dictionary<string, Vector2> OriginCache = new();

    /// <summary>
    /// Loads or returns cached SpriteFrames. Prefer passing an already-imported
    /// <paramref name="preloadedTexture"/> (from EnemyData.SpriteSheet) — path-only
    /// GD.Load can fail with "No loader found" if import state is flaky.
    /// </summary>
    public static SpriteFrames GetFrames(string sheetPath, string jsonPath = null, Texture2D preloadedTexture = null)
    {
        string cacheKey = !string.IsNullOrEmpty(sheetPath)
            ? sheetPath
            : preloadedTexture?.ResourcePath ?? preloadedTexture?.GetInstanceId().ToString();

        if (string.IsNullOrEmpty(cacheKey))
        {
            return null;
        }

        if (Cache.TryGetValue(cacheKey, out SpriteFrames cached) && GodotObject.IsInstanceValid(cached))
        {
            return cached;
        }

        Texture2D texture = preloadedTexture;
        if (texture == null || !GodotObject.IsInstanceValid(texture))
        {
            texture = LoadTexture(sheetPath);
        }

        if (texture == null)
        {
            GD.PushError($"[SpriteSheetCache] Missing texture: {sheetPath}");
            return null;
        }

        string resolvedJson = ResolveJsonPath(sheetPath, jsonPath);
        if (string.IsNullOrEmpty(resolvedJson) || !FileAccess.FileExists(resolvedJson))
        {
            GD.PushError($"[SpriteSheetCache] Missing json: {resolvedJson}");
            return null;
        }

        string jsonText;
        using (FileAccess file = FileAccess.Open(resolvedJson, FileAccess.ModeFlags.Read))
        {
            if (file == null)
            {
                GD.PushError($"[SpriteSheetCache] Cannot open json: {resolvedJson}");
                return null;
            }

            jsonText = file.GetAsText();
        }

        // Prefer Godot JSON — no System.Text.Json dependency / AOT issues.
        var parser = new Json();
        Error parseErr = parser.Parse(jsonText);
        if (parseErr != Error.Ok)
        {
            GD.PushError($"[SpriteSheetCache] Bad json '{resolvedJson}': {parser.GetErrorMessage()}");
            return null;
        }

        if (parser.Data.VariantType != Variant.Type.Dictionary)
        {
            GD.PushError($"[SpriteSheetCache] JSON root is not an object: {resolvedJson}");
            return null;
        }

        Godot.Collections.Dictionary meta = parser.Data.AsGodotDictionary();
        int frameWidth = DictInt(meta, "frameWidth", "frame_width");
        int frameHeight = DictInt(meta, "frameHeight", "frame_height");
        int columns = DictInt(meta, "columns");
        if (frameWidth <= 0 || frameHeight <= 0)
        {
            GD.PushError($"[SpriteSheetCache] Incomplete meta (frame size): {resolvedJson}");
            return null;
        }

        if (columns <= 0)
        {
            columns = Mathf.Max(1, texture.GetWidth() / frameWidth);
        }

        if (!meta.ContainsKey("animations") || meta["animations"].VariantType != Variant.Type.Dictionary)
        {
            GD.PushError($"[SpriteSheetCache] Incomplete meta (animations): {resolvedJson}");
            return null;
        }

        Godot.Collections.Dictionary animations = meta["animations"].AsGodotDictionary();
        var frames = new SpriteFrames();

        // Drop engine default "default" anim so we don't flash empty.
        if (frames.HasAnimation("default"))
        {
            frames.RemoveAnimation("default");
        }

        foreach (Variant animKey in animations.Keys)
        {
            string animName = animKey.AsString();
            if (string.IsNullOrEmpty(animName))
            {
                continue;
            }

            Variant animVar = animations[animKey];
            if (animVar.VariantType != Variant.Type.Dictionary)
            {
                continue;
            }

            Godot.Collections.Dictionary anim = animVar.AsGodotDictionary();
            if (frames.HasAnimation(animName))
            {
                frames.RemoveAnimation(animName);
            }

            frames.AddAnimation(animName);
            bool loop = DictBool(anim, "loop");
            frames.SetAnimationLoopMode(animName, loop
                ? SpriteFrames.LoopMode.Linear
                : SpriteFrames.LoopMode.None);
            float fps = DictFloat(anim, "fps", 10f);
            if (fps <= 0f)
            {
                fps = 10f;
            }

            frames.SetAnimationSpeed(animName, fps);

            int[] indices = ReadFrameIndices(anim);
            foreach (int frameIndex in indices)
            {
                int col = frameIndex % columns;
                int row = frameIndex / columns;
                var atlas = new AtlasTexture
                {
                    Atlas = texture,
                    Region = new Rect2(
                        col * frameWidth,
                        row * frameHeight,
                        frameWidth,
                        frameHeight),
                    FilterClip = true
                };
                frames.AddFrame(animName, atlas, 1.0f);
            }
        }

        EnsureAnim(frames, "idle");
        EnsureAnim(frames, "run", fallback: "idle");
        EnsureAnim(frames, "hurt", fallback: "idle");
        EnsureAnim(frames, "death", fallback: "hurt");

        Cache[cacheKey] = frames;

        float ox = frameWidth * 0.5f;
        float oy = frameHeight;
        if (meta.ContainsKey("origin") && meta["origin"].VariantType == Variant.Type.Dictionary)
        {
            Godot.Collections.Dictionary origin = meta["origin"].AsGodotDictionary();
            ox = DictFloat(origin, "x", ox);
            oy = DictFloat(origin, "y", oy);
        }

        // Offset so pivot (feet) sits on CharacterBody2D origin when sprite is centered.
        OriginCache[cacheKey] = new Vector2(frameWidth * 0.5f - ox, frameHeight * 0.5f - oy);

        GD.Print($"[SpriteSheetCache] Loaded '{cacheKey}' — {frames.GetAnimationNames().Length} anims, {frameWidth}x{frameHeight}.");
        return frames;
    }

    public static Vector2 GetSpriteOffset(string sheetPath)
    {
        if (!string.IsNullOrEmpty(sheetPath) && OriginCache.TryGetValue(sheetPath, out Vector2 o))
        {
            return o;
        }

        return new Vector2(0, -26);
    }

    private static Texture2D LoadTexture(string sheetPath)
    {
        if (string.IsNullOrEmpty(sheetPath))
        {
            return null;
        }

        // 1) Normal resource load (preferred when .import is healthy).
        if (ResourceLoader.Exists(sheetPath))
        {
            Texture2D viaLoader = ResourceLoader.Load<Texture2D>(sheetPath);
            if (viaLoader != null)
            {
                return viaLoader;
            }
        }

        Texture2D viaGd = GD.Load<Texture2D>(sheetPath);
        if (viaGd != null)
        {
            return viaGd;
        }

        // 2) Fallback: decode PNG bytes ourselves (works even when importer is broken).
        if (!FileAccess.FileExists(sheetPath))
        {
            return null;
        }

        byte[] bytes = FileAccess.GetFileAsBytes(sheetPath);
        if (bytes == null || bytes.Length == 0)
        {
            return null;
        }

        var image = new Image();
        Error err = image.LoadPngFromBuffer(bytes);
        if (err != Error.Ok)
        {
            // Try generic image load via globalized path.
            string global = ProjectSettings.GlobalizePath(sheetPath);
            err = image.Load(global);
            if (err != Error.Ok)
            {
                GD.PushError($"[SpriteSheetCache] Image decode failed for {sheetPath}: {err}");
                return null;
            }
        }

        var imageTex = ImageTexture.CreateFromImage(image);
        GD.PushWarning($"[SpriteSheetCache] Used ImageTexture fallback for {sheetPath}");
        return imageTex;
    }

    private static string ResolveJsonPath(string sheetPath, string jsonPath)
    {
        if (!string.IsNullOrEmpty(jsonPath))
        {
            return jsonPath;
        }

        if (string.IsNullOrEmpty(sheetPath))
        {
            return null;
        }

        int dot = sheetPath.LastIndexOf('.');
        return dot > 0 ? sheetPath.Substring(0, dot) + ".json" : sheetPath + ".json";
    }

    private static int[] ReadFrameIndices(Godot.Collections.Dictionary anim)
    {
        if (anim.ContainsKey("frames") && anim["frames"].VariantType == Variant.Type.Array)
        {
            Godot.Collections.Array arr = anim["frames"].AsGodotArray();
            var list = new List<int>(arr.Count);
            foreach (Variant v in arr)
            {
                list.Add(v.AsInt32());
            }

            if (list.Count > 0)
            {
                return list.ToArray();
            }
        }

        int from = DictInt(anim, "from");
        int to = DictInt(anim, "to", fallback: from);
        if (to < from)
        {
            to = from;
        }

        var range = new int[to - from + 1];
        for (int i = 0; i < range.Length; i++)
        {
            range[i] = from + i;
        }

        return range;
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

    private static int DictInt(Godot.Collections.Dictionary d, string key, string altKey = null, int fallback = 0)
    {
        if (d.ContainsKey(key))
        {
            return d[key].AsInt32();
        }

        if (!string.IsNullOrEmpty(altKey) && d.ContainsKey(altKey))
        {
            return d[altKey].AsInt32();
        }

        return fallback;
    }

    private static float DictFloat(Godot.Collections.Dictionary d, string key, float fallback = 0f)
    {
        if (!d.ContainsKey(key))
        {
            return fallback;
        }

        return d[key].AsSingle();
    }

    private static bool DictBool(Godot.Collections.Dictionary d, string key, bool fallback = false)
    {
        if (!d.ContainsKey(key))
        {
            return fallback;
        }

        return d[key].AsBool();
    }
}
