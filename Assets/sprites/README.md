# Nightbane — Modern 2D Art

Gothic blood-moon roguelite art (Hades / Dead Cells inspired cel-shading).

## Layout

| Path | Contents |
|------|----------|
| `characters/<id>/` | Hunter sheet + JSON + portrait + optional pose keyframes |
| `enemies/<id>/` | Enemy sheet + JSON + portrait |
| `bosses/<id>/` | Boss sheet + JSON + portrait |
| `weapons/<name>.png` | Inventory icons (128×128, transparent) |
| `_style/style_anchor.jpg` | Shared style reference for generation |

## Sheet format

- **Frame size:** 128×128 RGBA
- **Grid:** 6 columns × N rows (one animation per row)
- **Facing:** right (`flip_h` for left)
- **Origin:** center-x, near feet (`origin` in JSON)
- **JSON:** same schema as `SpriteSheetCache` (`frameWidth`, `animations`, `fps`, `loop`)

### Standard animations

| Name | Loop | Notes |
|------|------|--------|
| `idle` | yes | subtle breath |
| `run` | yes | uses `run_pose` keyframe when present |
| `attack` | no | + aliases `attack_slash`, `shield_bash`, `attack_whip`, `attack_orbs` |
| `hurt` | no | |
| `death` | no | |
| `dash` | no | |

## Rebuild sheets

```bash
python3 tools/package_modern_sprites.py --all-static
python3 tools/package_modern_sprites.py --weapons
```

Place optional `run_pose.jpg` / `attack_pose.jpg` next to the base in each entity folder before packaging.

## Style contract

- Flat magenta key `#FF00AA` on source bases (keyed out by packager)
- Cel-shaded, bold silhouette, blood-moon palette (crimson / iron / bone / silver)
- Full body, three-quarter view facing right
