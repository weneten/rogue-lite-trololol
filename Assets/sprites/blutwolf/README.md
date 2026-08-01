# Nightbane — Blutwolf (Spieler-Sprite)

Abgeleitet aus dem Blutwolf-Konzept-Art: verfluchtes Fell, vernarbte Brust,
zerrissene Dornen-Rüstung, Wolfsamulett, Schädel-Anhänger, Klauenhände und
digitigrade Beine. Gleicher technischer Stil wie [der Jäger](../README.md) —
prozedural erzeugt, Rim-Light + Outline als Postprocessing.

## Dateien

| Datei | Inhalt |
|---|---|
| `blutwolf.png` | Sprite-Sheet, 384×640, 6 Spalten × 10 Zeilen |
| `blutwolf.json` | Atlas: Frame-Indizes, fps, loop-Flag pro Animation |
| `blutwolf@4x.png` | Nur zum Anschauen (Nearest-Neighbour hochskaliert) |
| `strips/<anim>.png` | Einzelne Animationsstreifen (1 Zeile) |
| `preview.html` | Standalone-Preview, spielt alle Animationen ab |

## Format

- **Frame:** 64×64, transparenter Hintergrund
- **Blickrichtung:** rechts — für links horizontal spiegeln (`flip_h`)
- **Origin/Pivot:** x = 30, y = 58 (Bodenlinie unter den Pfoten)

## Animationen

Direkt aus den fünf benannten Aktionen im Konzept-Art abgeleitet, plus die
üblichen Basis-Animationen:

| Zeile | Name | Frames | fps | Loop | Konzept-Aktion / Einsatz |
|---|---|---|---|---|---|
| 0 | `idle` | 4 | 6 | ja | Stand, Atmung |
| 1 | `run` | 6 | 12 | ja | Laufen, gebeugter Gang |
| 2 | `dash` | 5 | 16 | nein | **Bestiensprung** — Sprung mit Krallen |
| 3 | `attack_slash` | 5 | 14 | nein | Klauen-Hieb, Nahkampf-Basisangriff |
| 4 | `attack_spin` | 5 | 14 | nein | **Wirbelnde Klingen** — Flächenangriff |
| 5 | `rage` | 4 | 10 | nein | **Raserei** — Buff, Aura verdichtet sich |
| 6 | `howl` | 4 | 8 | nein | **Blutmond Heulen** — Debuff/Buff-Aura |
| 7 | `hurt` | 2 | 10 | nein | Treffer |
| 8 | `death` | 4 | 8 | nein | Zusammenbruch, blendet aus |
| 9 | `ultimate` | 6 | 10 | nein | **Ultimate — Vollmond**-Verwandlung |

### Timing-Hinweise für die Hitboxen

- `dash` (Bestiensprung): aktive Frames **1–3**, i-Frames dort setzen.
- `attack_slash`: aktive Frames **1–3** (Krallenhiebe vor dem Körper).
- `attack_spin`: Radius wächst über alle 5 Frames von ca. 10 auf 20 px um
  den Origin — als AoE-Radius direkt verwendbar.
- `howl`: Debuff/Buff-Trigger auf Frame **2–3**, wenn der äußerste Ring sein
  Maximum erreicht.
- `rage`: Buff greift ab Frame **3** (letzter Frame, volle Aura).

## Einbinden

Gleiches Verfahren wie beim Jäger — siehe [assets/sprites/README.md](../README.md#einbinden)
für Godot/Phaser/Unity-Beispiele. Frame-Indizes für dieses Sheet:

```json
"idle": [0,1,2,3],  "run": [6,7,8,9,10,11],  "dash": [12,13,14,15,16],
"attack_slash": [18,19,20,21,22],  "attack_spin": [24,25,26,27,28],
"rage": [30,31,32,33],  "howl": [36,37,38,39],
"hurt": [42,43],  "death": [48,49,50,51],  "ultimate": [54,55,56,57,58,59]
```

## Ändern / Erweitern

Generator: `tools/gen_sprites_wolf.py`. Importiert die gemeinsamen
Pixel-Primitive (`new_layer`, `thick_line`, `poly`, `rim_light`,
`outline_layer`, das Preview-Template, …) aus `tools/gen_sprites.py`, damit
beide Charaktere denselben visuellen Stil teilen, aber einen eigenen
Körperbau (`draw_wolf`, `pose(...)`) und eigene Animationen (`anim_*`) haben.

```bash
python tools/gen_sprites_wolf.py
```

- Palette: `FUR_*`, `ARM_*`, `RST_*`, `CLAW_*` am Dateianfang
- Körperbau: `draw_wolf()` und die `draw_*`-Teilfunktionen
- Neue Animation: Funktion `anim_x()` schreiben, die
  `(frames, fps, loop)` zurückgibt, und in `ANIMS` eintragen
