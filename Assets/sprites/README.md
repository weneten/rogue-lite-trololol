# Nightbane — Pixel Art

Everything visual in the game is generated from source by `tools/pixelforge`,
a small pixel-art toolkit. No asset here is hand-painted or imported from
outside the repo, so the whole look can be changed from one palette file.

```bash
python3 tools/build_art.py           # rebuild everything
python3 tools/build_art.py ui theme  # or just one group
```

Requires Pillow. Output is deterministic — a rebuild with no code changes
produces identical files.

## Where things live

| Path | Contents |
|------|----------|
| `characters/<id>/` | Hunter sheet + atlas JSON + portrait |
| `enemies/<id>/` | Enemy sheet + atlas JSON + portrait |
| `bosses/<id>/` | Boss sheet + atlas JSON + portrait |
| `weapons/<name>.png` | 32×32 inventory icons |
| `arena/` | Floor tiles, wall tiles, prop strip |
| `../UI/` | Nine-slice panels, buttons, bars, HUD icons, theme |
| `../Fonts/` | Bitmap font atlases + `.fnt` descriptors |

## Sheet format

- **Frame size:** 64×64 for hunters and enemies, 96×96 for bosses
- **Grid:** 6 columns, one animation per row
- **Facing:** right (`flip_h` for left)
- **Origin:** centre-x, feet (`origin` in the JSON)
- **JSON:** the schema `SpriteSheetCache` reads (`frameWidth`, `animations`,
  `fps`, `loop`)

| Row | Animation | Frames | Loop |
|-----|-----------|--------|------|
| 0 | `idle` | 4 | yes |
| 1 | `run` | 6 | yes |
| 2 | `attack` | 6 | no |
| 3 | `hurt` | 2 | no |
| 4 | `death` | 5 | no |
| 5 | `dash` | 4 | no |

`attack` is also exported under every alias the combat code asks for
(`attack_slash`, `attack_whip`, `shield_bash`, …) so a weapon class can never
fall through to `idle`.

## Scale

Sheets are authored at 1:1 and every entity uses `sprite_scale = 2.0`. With
the arena camera at `zoom = 1.5` that lands on exactly 3 screen pixels per art
pixel — an integer ratio, which is what keeps the pixels square. Size
differences between entities are baked into the rig's `stature`, not into
`sprite_scale`, so changing one enemy's size never breaks the grid.

Every sprite node renders with `TEXTURE_FILTER_NEAREST`. Filtering pixel art
destroys it; if something looks soft, that filter is the first thing to check.

## Adding a character

1. Add an `Entry` to `tools/pixelforge/cast.py` — pick ramps, a head, a cape,
   a weapon and a stature. Silhouette first: it should be recognisable in
   black at 44 pixels tall before colour is considered.
2. `python3 tools/build_art.py sprites`
3. Point the `.tres` at `Assets/sprites/<group>/<id>/<id>.png` and `.json`.

New weapon shapes go in `tools/pixelforge/weapons.py` and are registered in
`CATALOG`; the same shape code draws both the inventory icon and the copy the
character holds, so the two can never disagree.

## The toolkit

| Module | Responsibility |
|--------|----------------|
| `core.py` | Hard-edged raster primitives, shading ramps, sheet assembly |
| `palette.py` | The one shared colour family — start here to reskin |
| `rig.py` | The poseable humanoid every entity is built from |
| `cast.py` | Who exists and what makes each one look different |
| `sheets.py` | Frame rendering, atlas JSON, portraits |
| `weapons.py` | Weapon shapes, held copies and icons |
| `ui.py` | Nine-slice chrome, HUD icons, menu backdrop |
| `font.py` | The bitmap font, one atlas per UI size |
| `theme.py` | The generated Godot `Theme` resource |
| `arena.py` | Floor, wall and prop art |
