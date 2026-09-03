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
| `weapons/mounted/<name>.png` | 60x60, the copy carried on the ring around the character, pointing right |
| `items/<id>.png` | 32×32 shop relic icons |
| `cosmetics/` | Loadout aura and charm chrome worn by the Hunter |
| `arena/` | Floor tiles, wall tiles, prop strip |
| `../UI/` | Nine-slice panels, buttons, bars, HUD icons, theme |
| `../Fonts/` | Bitmap font atlases + `.fnt` descriptors |

## The weapon fights, not the Hunter

Hunter sheets are drawn empty-handed (`weapon="none"` in `pixelforge/cast.py`)
and have no attack animation at all (`sheets.anims_for`). Both belong to the
weapons instead: the only weapons a Hunter shows in the arena are the ones the
player actually owns, drawn from `weapons/mounted/` by
`Scripts/Combat/WeaponVisual.gd`, and the swing is played there too.

Baking a weapon into the sheet meant a starting Hunter held a scythe they did
not own while their real weapon rode beside them. Animating the body meant six
weapons on their own cooldowns re-triggered an attack pose several times a
second, so the character twitched through the whole wave.

Enemies and bosses buy nothing and attack with their bodies, so they keep both.

## Sheet format

- **Frame size:** 64×64 for hunters and enemies, 96×96 for bosses
- **Grid:** 8 columns, one animation per row
- **Facing:** right (`flip_h` for left)
- **Origin:** centre-x, feet (`origin` in the JSON)
- **JSON:** the schema `SpriteSheetCache` reads (`frameWidth`, `animations`,
  `fps`, `loop`)

| Row | Animation | Frames | FPS | Loop |
|-----|-----------|--------|-----|------|
| 0 | `idle` | 6 | 7 | yes |
| 1 | `run` | 8 | 15 | yes |
| 2 | `attack` | 7 | 16 | no (enemies and bosses only) |
| 3 | `hurt` | 3 | 15 | no |
| 4 | `death` | 7 | 10 | no |
| 5 | `dash` | 5 | 18 | no |

Eight columns, not six. A six-frame run is two frames short of a
contact/down/pass/up beat per leg, and four idle frames is close enough to a
two-frame flicker that a standing Hunter read as a breathing statue. Nothing
on the Godot side is pinned to either number: `SpriteSheetCache` takes the
column count, the frame indices, the fps and the loop flag straight out of the
atlas JSON, so changing `sheets.COLUMNS` or `sheets.ANIMS` needs no engine
change at all.

## What makes a pose read as a body

Everything in `rig.py` used to ride one shared sine, which is a pulse rather
than a body: lungs, spine, arms and cloth all reached their extreme on the
same frame. Three things fix that, and they are worth keeping in mind when
adding an animation:

* **Lag.** Each layer trails the one driving it — the spine follows the lungs,
  the limbs and the cape trail both. Nothing peaks together, so the loop has no
  visible seam.
* **`sway`, `twist`, `head_lead`.** Lateral weight shift, shoulder-line
  rotation and how far the head leads the spine. A few pixels each, and they
  are most of the difference between a rig moving and a body moving. `twist` is
  as much three-quarter turn as a side-on rig can show.
* **Weight.** The run hip is lowest at each contact — where the legs are most
  spread — and highest at the pass where they cross, and the contact shadow
  tightens with it. The robe hem is carried by the legs inside it, so it parts
  around the leading foot instead of swinging as a rigid bell.

### The feet are planted by moving the body

The rig is built hip-downward, so the feet land wherever the leg angles put
them. A straight-legged stance reaches about `18 * stature`; a stance spread
30° reaches only about `15.6 * stature`. Something has to close that gap, or
the character walks two and a half pixels above the floor.

`build_pose` closes it by translating the **whole figure** until the lower foot
sits on the ground line — never by moving the feet. Moving the feet was the
original approach and it was wrong twice over: the shins stretched by up to
five pixels on a forty-pixel character, and because it moved *both* feet by the
same amount neither foot ever lifted or planted. The legs scissored while the
boots stayed glued together at one height — a shuffle on stilts.

Two consequences worth knowing:

* `foot_plant` (0..1) says how hard the pin holds. The run drops it to 0.5 at
  the pass so the figure keeps some of its own lift between steps — that is the
  flight phase. `death` sets it to 0, because the whole point there is that the
  body goes down through its own stance.
* Anything that lifts the hips takes the feet off the floor with them, and the
  pin then cancels it exactly. So idle breathes with `chest_rise`, which raises
  the ribcage and leaves the pelvis alone, and `sway` rides the spine rather
  than displacing the whole figure. Sliding the character sideways looks fine
  in the arena and reads as a shuffle in the character-select panel, which is
  the same sprite held still at 3x zoom.

Hunter sheets have **no** `attack` row, so they are five rows and their later
animations sit one row higher. Nothing on the Godot side hardcodes a row: the
atlas JSON carries the row and frame indices, and `SpriteSheetCache` reads them.

`attack` is also exported under every alias the combat code asks for
(`attack_slash`, `attack_whip`, `shield_bash`, …) so an enemy's weapon class can
never fall through to `idle`.

## Depth

Every living fighter — player and enemies alike — draws at `z_index` 0 and is
ordered purely by Y-sorting, and enemies are parented into the same node as the
Player so that sorting can actually compare them. Both halves matter: Y-sort
only orders siblings, and `z_index` outranks Y-sort entirely, so a single
sprite left one layer up draws over everyone regardless of where its feet are.

Corpses drop to -1, pickups to -2, the aura to -3; the arena floor and props
sit at -10 to -5.

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
`CATALOG`; the same shape code draws the inventory icon, the copy baked into
the character sheet, and the mounted copy carried in the arena, so the three
can never disagree.

## Adding a relic

1. Draw it in `tools/pixelforge/items.py` and register it in `ICONS` under the
   id you intend to use — the key IS the `PassiveItemData.id`, so a missing
   icon is a build-time `KeyError` rather than a blank square in the shop.
2. `python3 tools/build_art.py items`
3. Add `Resources/PassiveItemData/Data/<id>.tres` pointing at
   `Assets/sprites/items/<id>.png`, and list it in `StandardShopPool.tres`.

If the relic needs a stat nothing else grants, add a case to
`PassiveItemData.PassiveEffectType` (append only — the .tres files store the
numeric value), a label in `EFFECT_LABEL`, an `apply_*` on `PlayerStats`, and a
branch in `ShopUI._apply_passive_effect`. An unhandled type pushes a warning
instead of silently doing nothing.

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
