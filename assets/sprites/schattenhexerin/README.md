# Nightbane — Schattenhexerin (Spieler-Sprite)

Abgeleitet aus dem Schattenhexerin-Konzept-Art: bodenlange zerrissene Robe,
spitze Kapuze, blasse Ritualmaske, okkulte Symbole, Talisman-Anhänger und
ein Schattenstab mit Halbmond und schwebendem Seelen-Orb. Gleicher
technischer Stil wie [der Jäger](../README.md) und [der Blutwolf](../blutwolf/README.md) —
prozedural erzeugt, Rim-Light + Outline als Postprocessing.

## Dateien

| Datei | Inhalt |
|---|---|
| `schattenhexerin.png` | Sprite-Sheet, 384×640, 6 Spalten × 10 Zeilen |
| `schattenhexerin.json` | Atlas: Frame-Indizes, fps, loop-Flag pro Animation |
| `schattenhexerin@4x.png` | Nur zum Anschauen (Nearest-Neighbour hochskaliert) |
| `strips/<anim>.png` | Einzelne Animationsstreifen (1 Zeile) |
| `preview.html` | Standalone-Preview, spielt alle Animationen ab |

## Format

- **Frame:** 64×64, transparenter Hintergrund
- **Blickrichtung:** rechts — für links horizontal spiegeln (`flip_h`)
- **Origin/Pivot:** x = 30, y = 58 (Bodenlinie unter dem Robensaum)
- Die Robe verdeckt die Beine vollständig — die Figur gleitet/schwebt statt
  zu laufen, passend zur Silhouette im Konzept-Art.

## Animationen

Direkt aus den fünf benannten Aktionen im Konzept-Art abgeleitet, plus die
üblichen Basis-Animationen:

| Zeile | Name | Frames | fps | Loop | Konzept-Aktion / Einsatz |
|---|---|---|---|---|---|
| 0 | `idle` | 4 | 6 | ja | Stand, Stab glimmt |
| 1 | `run` | 6 | 12 | ja | Gleiten, Robe peitscht nach hinten |
| 2 | `dash` | 5 | 16 | nein | Schattenschritt — Auflösen & Neuerscheinen |
| 3 | `attack_orbs` | 5 | 14 | nein | **Schattensphären** — geworfener Orb |
| 4 | `attack_nova` | 5 | 14 | nein | **Dunkler Nova** — radialer Flächenangriff |
| 5 | `soul_drain` | 4 | 8 | nein | **Seelensaug** — Lifesteal-Kanalisierung |
| 6 | `stakes` | 4 | 10 | nein | **Seelenpfähle** — Schattenspitzen aus dem Boden |
| 7 | `hurt` | 2 | 10 | nein | Treffer |
| 8 | `death` | 4 | 8 | nein | Sinkt zusammen, blendet aus |
| 9 | `ultimate` | 6 | 10 | nein | **Ultimate — Seelenopfer**, Geist erhebt sich |

### Timing-Hinweise für die Hitboxen

- `attack_orbs`: Orb trifft in Frame **4** am Ziel ein (Einschlagsradius dort).
- `attack_nova`: Radius wächst über alle 5 Frames von ca. 4 auf 30 px um
  den Origin — als AoE-Radius direkt verwendbar; Trigger ab Frame **2**.
- `soul_drain`: Kanal-Tick läuft über alle 4 Frames, Heil-/Lifesteal-Betrag
  gleichmäßig verteilen.
- `stakes`: Pfähle aktivieren nacheinander (versetzt), voll ausgefahren ab
  Frame **3** — Treffer dort auslösen.
- `dash`: Frames **1–3** sind die unsichtbare Phase (i-Frames), Frame 4 ist
  die Wiedererscheinung.

## Einbinden

Gleiches Verfahren wie beim Jäger — siehe [assets/sprites/README.md](../README.md#einbinden)
für Godot/Phaser/Unity-Beispiele. Frame-Indizes für dieses Sheet:

```json
"idle": [0,1,2,3],  "run": [6,7,8,9,10,11],  "dash": [12,13,14,15,16],
"attack_orbs": [18,19,20,21,22],  "attack_nova": [24,25,26,27,28],
"soul_drain": [30,31,32,33],  "stakes": [36,37,38,39],
"hurt": [42,43],  "death": [48,49,50,51],  "ultimate": [54,55,56,57,58,59]
```

## Ändern / Erweitern

Generator: `tools/gen_sprites_witch.py`. Importiert die gemeinsamen
Pixel-Primitive (`new_layer`, `thick_line`, `poly`, `rim_light`,
`outline_layer`, das Preview-Template, …) aus `tools/gen_sprites.py`, damit
alle drei Charaktere denselben visuellen Stil teilen, aber einen eigenen
Körperbau (`draw_witch`, `pose(...)`) und eigene Animationen (`anim_*`) haben.

```bash
python tools/gen_sprites_witch.py
```

- Palette: `ROBE_*`, `MASK_*`, `PUR_*` (Seelenenergie), `RIT_*` am Dateianfang
- Körperbau: `draw_witch()` und die `draw_*`-Teilfunktionen
- Neue Animation: Funktion `anim_x()` schreiben, die
  `(frames, fps, loop)` zurückgibt, und in `ANIMS` eintragen
