using Godot;

namespace Nightbane.Arena;

/// <summary>
/// Builds a Brotato-like playfield: warm checker dirt tiles, soft border, light clutter.
/// Pure procedural textures so we never depend on missing imports.
/// </summary>
public partial class ArenaVisuals : Node2D
{
    [Export] public Vector2 ArenaSize { get; set; } = new(1600, 1000);
    [Export] public int TileSize { get; set; } = 48;
    [Export] public int BorderThickness { get; set; } = 56;
    [Export] public int ClutterCount { get; set; } = 48;
    [Export] public int Seed { get; set; } = 1337;

    // Warm sand / clay — Brotato-ish readable floor.
    private static readonly Color TileA = new(0.72f, 0.58f, 0.40f, 1f);
    private static readonly Color TileB = new(0.66f, 0.52f, 0.36f, 1f);
    private static readonly Color TileC = new(0.76f, 0.62f, 0.44f, 1f);
    private static readonly Color Grout = new(0.48f, 0.36f, 0.24f, 1f);
    private static readonly Color BorderFill = new(0.38f, 0.30f, 0.22f, 1f);
    private static readonly Color BorderRim = new(0.28f, 0.22f, 0.16f, 1f);
    private static readonly Color OutsideVoid = new(0.18f, 0.16f, 0.14f, 1f);

    public override void _Ready()
    {
        // Kill any leftover dark global grade from older Arena scenes.
        CanvasModulate modulate = GetParent()?.GetNodeOrNull<CanvasModulate>("CanvasModulate");
        if (modulate != null)
        {
            modulate.Color = new Color(1.05f, 1.02f, 0.96f, 1f);
        }

        // Soft vignette only (was heavy purple fog).
        var vignette = GetTree()?.CurrentScene?.GetNodeOrNull<ColorRect>(
            "UI/VignetteOverlay_TODO_ReplaceWithRadialShader");
        if (vignette != null)
        {
            vignette.Color = new Color(0.05f, 0.03f, 0.02f, 0.14f);
        }

        BuildOutside();
        BuildFloor();
        BuildBorder();
        BuildClutter();
        BuildCornerAccents();
    }

    private void BuildOutside()
    {
        // Slightly larger dark plate so the camera never shows pure black emptiness.
        var outside = new Polygon2D
        {
            Name = "Outside",
            ZIndex = -20,
            Color = OutsideVoid,
            Polygon = new Vector2[]
            {
                new(-ArenaSize.X, -ArenaSize.Y),
                new(ArenaSize.X, -ArenaSize.Y),
                new(ArenaSize.X, ArenaSize.Y),
                new(-ArenaSize.X, ArenaSize.Y)
            }
        };
        // Scale up a bit beyond walls.
        outside.Scale = Vector2.One * 1.35f;
        AddChild(outside);
    }

    private void BuildFloor()
    {
        int halfW = Mathf.CeilToInt(ArenaSize.X * 0.5f / TileSize) * TileSize;
        int halfH = Mathf.CeilToInt(ArenaSize.Y * 0.5f / TileSize) * TileSize;
        int texW = halfW * 2;
        int texH = halfH * 2;

        Image image = Image.CreateEmpty(texW, texH, false, Image.Format.Rgba8);
        image.Fill(TileA);

        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong)Seed;

        for (int y = 0; y < texH; y += TileSize)
        {
            for (int x = 0; x < texW; x += TileSize)
            {
                int tx = x / TileSize;
                int ty = y / TileSize;
                bool checker = ((tx + ty) & 1) == 0;
                Color baseCol = checker ? TileA : TileB;

                // Occasional third tone for variety (Brotato tiles aren't perfectly uniform).
                if (rng.Randf() < 0.12f)
                {
                    baseCol = TileC;
                }

                // Subtle per-tile brightness noise.
                float n = rng.RandfRange(-0.04f, 0.04f);
                Color fill = new(
                    Mathf.Clamp(baseCol.R + n, 0f, 1f),
                    Mathf.Clamp(baseCol.G + n * 0.9f, 0f, 1f),
                    Mathf.Clamp(baseCol.B + n * 0.7f, 0f, 1f),
                    1f);

                FillRect(image, x, y, TileSize, TileSize, fill);

                // Inner highlight (top-left) + soft shadow (bottom-right) → cheap 3D tile feel.
                Color hi = fill.Lightened(0.08f);
                Color sh = fill.Darkened(0.10f);
                DrawHLine(image, x + 1, x + TileSize - 2, y + 1, hi);
                DrawVLine(image, x + 1, y + 1, y + TileSize - 2, hi);
                DrawHLine(image, x + 2, x + TileSize - 2, y + TileSize - 2, sh);
                DrawVLine(image, x + TileSize - 2, y + 2, y + TileSize - 2, sh);

                // Speckles / dirt grit.
                int grit = rng.RandiRange(3, 8);
                for (int i = 0; i < grit; i++)
                {
                    int px = x + rng.RandiRange(3, TileSize - 4);
                    int py = y + rng.RandiRange(3, TileSize - 4);
                    Color speck = rng.Randf() < 0.5f ? fill.Darkened(0.12f) : fill.Lightened(0.08f);
                    image.SetPixel(px, py, speck);
                    if (rng.Randf() < 0.35f && px + 1 < x + TileSize - 2)
                    {
                        image.SetPixel(px + 1, py, speck);
                    }
                }

                // Thin grout lines between tiles.
                DrawHLine(image, x, x + TileSize - 1, y, Grout);
                DrawVLine(image, x, y, y + TileSize - 1, Grout);
            }
        }

        // Soft center brightening so the fight area reads clearer.
        ApplyRadialLift(image, 0.07f);

        ImageTexture tex = ImageTexture.CreateFromImage(image);
        var floor = new Sprite2D
        {
            Name = "Floor",
            Texture = tex,
            Centered = true,
            TextureFilter = CanvasItem.TextureFilterEnum.Nearest,
            ZIndex = -10,
            Position = Vector2.Zero
        };
        AddChild(floor);
    }

    private void BuildBorder()
    {
        float hw = ArenaSize.X * 0.5f;
        float hh = ArenaSize.Y * 0.5f;
        float t = BorderThickness;

        // Four thick border slabs (darker packed earth / wood edge).
        AddBorderSlab("BorderN", new Rect2(-hw - t, -hh - t, ArenaSize.X + t * 2, t));
        AddBorderSlab("BorderS", new Rect2(-hw - t, hh, ArenaSize.X + t * 2, t));
        AddBorderSlab("BorderW", new Rect2(-hw - t, -hh, t, ArenaSize.Y));
        AddBorderSlab("BorderE", new Rect2(hw, -hh, t, ArenaSize.Y));

        // Inner rim line (lighter strip) so the playable edge is obvious like Brotato.
        var rim = new Line2D
        {
            Name = "PlayableRim",
            Width = 3f,
            DefaultColor = new Color(0.90f, 0.78f, 0.52f, 0.85f),
            ZIndex = -5,
            Antialiased = false,
            JointMode = Line2D.LineJointMode.Bevel,
            BeginCapMode = Line2D.LineCapMode.Box,
            EndCapMode = Line2D.LineCapMode.Box
        };
        rim.AddPoint(new Vector2(-hw + 2, -hh + 2));
        rim.AddPoint(new Vector2(hw - 2, -hh + 2));
        rim.AddPoint(new Vector2(hw - 2, hh - 2));
        rim.AddPoint(new Vector2(-hw + 2, hh - 2));
        rim.AddPoint(new Vector2(-hw + 2, -hh + 2));
        AddChild(rim);
    }

    private void AddBorderSlab(string name, Rect2 rect)
    {
        Image image = Image.CreateEmpty(Mathf.Max(2, (int)rect.Size.X), Mathf.Max(2, (int)rect.Size.Y),
            false, Image.Format.Rgba8);
        image.Fill(BorderFill);

        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong)(Seed + name.GetHashCode());

        // Brick / plank style banding.
        int band = 14;
        for (int y = 0; y < image.GetHeight(); y++)
        {
            for (int x = 0; x < image.GetWidth(); x++)
            {
                bool darkBand = ((y / band) + (x / (band * 2))) % 2 == 0;
                Color c = darkBand ? BorderFill : BorderFill.Lightened(0.05f);
                float n = rng.RandfRange(-0.03f, 0.03f);
                c = new Color(
                    Mathf.Clamp(c.R + n, 0f, 1f),
                    Mathf.Clamp(c.G + n, 0f, 1f),
                    Mathf.Clamp(c.B + n, 0f, 1f),
                    1f);
                image.SetPixel(x, y, c);
            }
        }

        // Outer edge darker.
        for (int x = 0; x < image.GetWidth(); x++)
        {
            image.SetPixel(x, 0, BorderRim);
            image.SetPixel(x, image.GetHeight() - 1, BorderRim);
        }

        for (int y = 0; y < image.GetHeight(); y++)
        {
            image.SetPixel(0, y, BorderRim);
            image.SetPixel(image.GetWidth() - 1, y, BorderRim);
        }

        ImageTexture tex = ImageTexture.CreateFromImage(image);
        var sprite = new Sprite2D
        {
            Name = name,
            Texture = tex,
            Centered = false,
            TextureFilter = CanvasItem.TextureFilterEnum.Nearest,
            ZIndex = -8,
            Position = rect.Position
        };
        AddChild(sprite);
    }

    private void BuildClutter()
    {
        var root = new Node2D { Name = "Clutter", ZIndex = -6 };
        AddChild(root);

        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong)(Seed + 99);

        float hw = ArenaSize.X * 0.5f - 40f;
        float hh = ArenaSize.Y * 0.5f - 40f;

        for (int i = 0; i < ClutterCount; i++)
        {
            // Bias clutter toward edges so center stays clear for combat readability.
            float edgeBias = rng.Randf();
            float x;
            float y;
            if (edgeBias < 0.7f)
            {
                // Near border ring.
                int side = rng.RandiRange(0, 3);
                float inset = rng.RandfRange(20f, 90f);
                switch (side)
                {
                    case 0: // N
                        x = rng.RandfRange(-hw, hw);
                        y = -hh + inset;
                        break;
                    case 1: // S
                        x = rng.RandfRange(-hw, hw);
                        y = hh - inset;
                        break;
                    case 2: // W
                        x = -hw + inset;
                        y = rng.RandfRange(-hh, hh);
                        break;
                    default: // E
                        x = hw - inset;
                        y = rng.RandfRange(-hh, hh);
                        break;
                }
            }
            else
            {
                x = rng.RandfRange(-hw * 0.7f, hw * 0.7f);
                y = rng.RandfRange(-hh * 0.7f, hh * 0.7f);
            }

            int kind = rng.RandiRange(0, 3);
            Node2D prop = kind switch
            {
                0 => MakePebble(rng),
                1 => MakeGrassTuft(rng),
                2 => MakeCrack(rng),
                _ => MakeBone(rng)
            };
            prop.Position = new Vector2(x, y);
            prop.Rotation = rng.RandfRange(0f, Mathf.Tau);
            prop.Modulate = new Color(1f, 1f, 1f, rng.RandfRange(0.55f, 0.9f));
            root.AddChild(prop);
        }
    }

    private void BuildCornerAccents()
    {
        float hw = ArenaSize.X * 0.5f - 30f;
        float hh = ArenaSize.Y * 0.5f - 30f;
        Vector2[] corners =
        {
            new(-hw, -hh), new(hw, -hh), new(-hw, hh), new(hw, hh)
        };

        foreach (Vector2 c in corners)
        {
            var plate = new Polygon2D
            {
                Color = new Color(0.42f, 0.34f, 0.24f, 0.9f),
                Polygon = new Vector2[]
                {
                    new(-18, -10), new(18, -10), new(14, 12), new(-14, 12)
                },
                Position = c,
                ZIndex = -7
            };
            AddChild(plate);

            var stud = new Polygon2D
            {
                Color = new Color(0.85f, 0.72f, 0.40f, 0.95f),
                Polygon = new Vector2[]
                {
                    new(-4, -4), new(4, -4), new(4, 4), new(-4, 4)
                },
                Position = c,
                ZIndex = -6
            };
            AddChild(stud);
        }
    }

    private static Node2D MakePebble(RandomNumberGenerator rng)
    {
        float s = rng.RandfRange(3f, 7f);
        return new Polygon2D
        {
            Color = new Color(0.45f, 0.40f, 0.34f, 1f),
            Polygon = new Vector2[]
            {
                new(-s, -s * 0.6f),
                new(s * 0.8f, -s * 0.5f),
                new(s, s * 0.5f),
                new(-s * 0.7f, s * 0.6f)
            }
        };
    }

    private static Node2D MakeGrassTuft(RandomNumberGenerator rng)
    {
        var root = new Node2D();
        int blades = rng.RandiRange(3, 5);
        for (int i = 0; i < blades; i++)
        {
            float h = rng.RandfRange(6f, 12f);
            float ox = rng.RandfRange(-4f, 4f);
            var blade = new Polygon2D
            {
                Color = new Color(0.35f + rng.Randf() * 0.1f, 0.48f, 0.28f, 0.9f),
                Polygon = new Vector2[]
                {
                    new(ox - 1.2f, 0),
                    new(ox + 1.2f, 0),
                    new(ox + rng.RandfRange(-2f, 2f), -h)
                }
            };
            root.AddChild(blade);
        }

        return root;
    }

    private static Node2D MakeCrack(RandomNumberGenerator rng)
    {
        var line = new Line2D
        {
            Width = rng.RandfRange(1.2f, 2.2f),
            DefaultColor = new Color(0.40f, 0.30f, 0.20f, 0.75f),
            Antialiased = false
        };
        float len = rng.RandfRange(10f, 22f);
        line.AddPoint(Vector2.Zero);
        line.AddPoint(new Vector2(len * 0.4f, rng.RandfRange(-3f, 3f)));
        line.AddPoint(new Vector2(len, rng.RandfRange(-4f, 4f)));
        return line;
    }

    private static Node2D MakeBone(RandomNumberGenerator rng)
    {
        float len = rng.RandfRange(8f, 14f);
        return new Polygon2D
        {
            Color = new Color(0.82f, 0.78f, 0.68f, 0.85f),
            Polygon = new Vector2[]
            {
                new(-len, -1.5f),
                new(len, -1.5f),
                new(len + 2f, 0),
                new(len, 1.5f),
                new(-len, 1.5f),
                new(-len - 2f, 0)
            }
        };
    }

    private static void FillRect(Image image, int x, int y, int w, int h, Color color)
    {
        int x1 = Mathf.Clamp(x + w, 0, image.GetWidth());
        int y1 = Mathf.Clamp(y + h, 0, image.GetHeight());
        x = Mathf.Clamp(x, 0, image.GetWidth());
        y = Mathf.Clamp(y, 0, image.GetHeight());
        for (int py = y; py < y1; py++)
        {
            for (int px = x; px < x1; px++)
            {
                image.SetPixel(px, py, color);
            }
        }
    }

    private static void DrawHLine(Image image, int x0, int x1, int y, Color color)
    {
        if (y < 0 || y >= image.GetHeight())
        {
            return;
        }

        if (x0 > x1)
        {
            (x0, x1) = (x1, x0);
        }

        x0 = Mathf.Clamp(x0, 0, image.GetWidth() - 1);
        x1 = Mathf.Clamp(x1, 0, image.GetWidth() - 1);
        for (int x = x0; x <= x1; x++)
        {
            image.SetPixel(x, y, color);
        }
    }

    private static void DrawVLine(Image image, int x, int y0, int y1, Color color)
    {
        if (x < 0 || x >= image.GetWidth())
        {
            return;
        }

        if (y0 > y1)
        {
            (y0, y1) = (y1, y0);
        }

        y0 = Mathf.Clamp(y0, 0, image.GetHeight() - 1);
        y1 = Mathf.Clamp(y1, 0, image.GetHeight() - 1);
        for (int y = y0; y <= y1; y++)
        {
            image.SetPixel(x, y, color);
        }
    }

    private static void ApplyRadialLift(Image image, float amount)
    {
        int w = image.GetWidth();
        int h = image.GetHeight();
        float cx = w * 0.5f;
        float cy = h * 0.5f;
        float maxR = Mathf.Sqrt(cx * cx + cy * cy);

        // Sample every 2px for speed — still looks smooth at game scale.
        for (int y = 0; y < h; y += 2)
        {
            for (int x = 0; x < w; x += 2)
            {
                float dx = (x - cx) / maxR;
                float dy = (y - cy) / maxR;
                float d = Mathf.Sqrt(dx * dx + dy * dy);
                float lift = (1f - Mathf.Clamp(d, 0f, 1f)) * amount;
                if (lift <= 0.001f)
                {
                    continue;
                }

                for (int oy = 0; oy < 2 && y + oy < h; oy++)
                {
                    for (int ox = 0; ox < 2 && x + ox < w; ox++)
                    {
                        Color c = image.GetPixel(x + ox, y + oy);
                        image.SetPixel(x + ox, y + oy, c.Lightened(lift));
                    }
                }
            }
        }
    }
}
