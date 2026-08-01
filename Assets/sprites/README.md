# Nightbane — Jäger (Spieler-Sprite)

Abgeleitet aus dem Konzept-Art: zerrissener Umhang, breitkrempiger Hut, Ledergurte
mit Ausrüstung, glühende Augen, Peitsche-Sichel und geweihtes Kreuz.

## Dateien

| Datei | Inhalt |
|---|---|
| `nightbane_hunter.png` | Sprite-Sheet, 384×576, 6 Spalten × 9 Zeilen |
| `nightbane_hunter.json` | Atlas: Frame-Indizes, fps, loop-Flag pro Animation |
| `nightbane_hunter@4x.png` | Nur zum Anschauen (Nearest-Neighbour hochskaliert) |
| `strips/<anim>.png` | Einzelne Animationsstreifen (1 Zeile) |
| `preview.html` | Standalone-Preview, spielt alle Animationen ab |

## Format

- **Frame:** 64×64, transparenter Hintergrund
- **Blickrichtung:** rechts — für links horizontal spiegeln (`flip_h`)
- **Origin/Pivot:** x = 30, y = 58 (Bodenlinie unter den Füßen)
- **Zeile = Animation**, Spalte = Frame; ungenutzte Spalten am Zeilenende sind leer

## Animationen

| Zeile | Name | Frames | fps | Loop | Einsatz |
|---|---|---|---|---|---|
| 0 | `idle` | 4 | 6 | ja | Stand, Atmung |
| 1 | `run` | 6 | 12 | ja | Laufen |
| 2 | `dash` | 5 | 16 | nein | Ausweichen, mit Nachbildern |
| 3 | `attack_whip` | 6 | 14 | nein | Peitschen-Angriff, Bogen nach vorn |
| 4 | `attack_cross` | 6 | 14 | nein | Kreuz-Wirbel, Flächenangriff |
| 5 | `potion` | 4 | 8 | nein | Trank nutzen |
| 6 | `hurt` | 2 | 10 | nein | Treffer |
| 7 | `death` | 4 | 8 | nein | Zusammenbruch, blendet aus |
| 8 | `ultimate` | 6 | 10 | nein | Blutmond |

### Timing-Hinweise für die Hitboxen

- `attack_whip`: aktive Frames **1–3** (der Bogen vor dem Körper), Reichweite ca. 20 px
  vor dem Origin. Frames 4–5 sind Recovery.
- `attack_cross`: aktive Frames **1–4**, Radius wächst von ca. 5 auf 24 px um den Origin.
- `dash`: Frames **1–3** sind die Bewegungsphase (dort i-Frames setzen), Frame 4 ist Landung.

## Einbinden

**Godot 4** — `AnimatedSprite2D`, SpriteFrames aus dem Sheet, 6×9 Grid,
`texture_filter = Nearest`, Offset y = −58 relativ zum Origin.

**Phaser 3**
```js
this.load.spritesheet('hunter', 'assets/sprites/nightbane_hunter.png',
  { frameWidth: 64, frameHeight: 64 });
// dann pro Eintrag aus nightbane_hunter.json:
this.anims.create({ key: 'dash', frames: this.anims.generateFrameNumbers('hunter',
  { start: 12, end: 16 }), frameRate: 16, repeat: 0 });
```

**Unity** — Sprite Mode `Multiple`, Grid By Cell Size 64×64, Pivot `Custom` (0.47, 0.09),
Filter Mode `Point`, Compression `None`.

## Ändern / Erweitern

Alle Sprites werden prozedural erzeugt — nichts von Hand nachmalen, sondern
`tools/gen_sprites.py` anpassen und neu generieren:

```bash
python tools/gen_sprites.py
```

- Palette: Konstanten am Dateianfang (`CLK_*`, `LEA_*`, `RED_*`, …)
- Körperbau: `draw_hunter()` und die `draw_*`-Teilfunktionen
- Posen: `pose(...)` — jede Animation überschreibt nur die Felder, die sie braucht
- Neue Animation: Funktion `anim_x()` schreiben, die
  `(frames, fps, loop)` zurückgibt, und in `ANIMS` eintragen

Rim-Light und Outline laufen automatisch als Nachbearbeitung über jeden Frame,
damit die Silhouette auf dunklem Hintergrund lesbar bleibt.
