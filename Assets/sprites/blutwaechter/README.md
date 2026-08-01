# Nightbane — Blutwächter (Spieler-Sprite)

Abgeleitet aus dem Blutwächter-Konzept-Art: gehörnter Vollhelm, Brustplatte
mit Kreuz, zerfetzter Wappenrock, Kite-Schild mit Kreuz-Emblem, Morgenstern
an rostiger Kette und eine ewige Laterne am Gürtel. Gleicher technischer
Stil wie [der Jäger](../README.md), [der Blutwolf](../blutwolf/README.md)
und [die Schattenhexerin](../schattenhexerin/README.md) — prozedural
erzeugt, Rim-Light + Outline als Postprocessing.

## Dateien

| Datei | Inhalt |
|---|---|
| `blutwaechter.png` | Sprite-Sheet, 384×640, 6 Spalten × 10 Zeilen |
| `blutwaechter.json` | Atlas: Frame-Indizes, fps, loop-Flag pro Animation |
| `blutwaechter@4x.png` | Nur zum Anschauen (Nearest-Neighbour hochskaliert) |
| `strips/<anim>.png` | Einzelne Animationsstreifen (1 Zeile) |
| `preview.html` | Standalone-Preview, spielt alle Animationen ab |

## Format

- **Frame:** 64×64, transparenter Hintergrund
- **Blickrichtung:** rechts — für links horizontal spiegeln (`flip_h`)
- **Origin/Pivot:** x = 30, y = 58 (Bodenlinie unter den Stiefeln)
- Schild-Arm liegt hinten (Rückenlage), Morgenstern-Arm vorn — als Tank
  bewusst mit dem Schild zur Kamera in der Idle-Haltung.

## Animationen

Direkt aus den fünf benannten Aktionen im Konzept-Art abgeleitet, plus die
üblichen Basis-Animationen:

| Zeile | Name | Frames | fps | Loop | Konzept-Aktion / Einsatz |
|---|---|---|---|---|---|
| 0 | `idle` | 4 | 6 | ja | Stand, Schild bereit |
| 1 | `run` | 6 | 10 | ja | Laufen, schwerfälliger Gang |
| 2 | `shield_bash` | 5 | 12 | nein | **Schildstoß** — Ausfallschritt, Knockback |
| 3 | `chain_swing` | 6 | 16 | nein | **Kettenschlag** — Morgenstern umkreist den Körper |
| 4 | `bastion` | 5 | 10 | nein | **Heilige Bastion** — Schutzkuppel-Buff |
| 5 | `taunt` | 4 | 8 | nein | **Büßeruf** — Aggro-Ruf, Lichtsäule |
| 6 | `guardian_leap` | 5 | 14 | nein | **Rache des Wächters** — Sprung + Einschlag |
| 7 | `hurt` | 2 | 10 | nein | Treffer |
| 8 | `death` | 4 | 8 | nein | Zusammenbruch, Kreuz erlischt |
| 9 | `ultimate` | 6 | 10 | nein | **Ultimate — Unzerbrechlich**, heiliges Licht |

### Timing-Hinweise für die Hitboxen

- `shield_bash`: Ausfallschritt in Frame **1–2**, Stoß-Impact (Knockback +
  Stun) auf Frame **3**, feste Trefferzone ca. 20 px vor dem Origin.
- `chain_swing`: die Kugel läuft einmal komplett um den Körper — Treffer
  über alle 6 Frames verteilt, Radius ca. 13 px um den Origin.
- `bastion`: Buff greift ab Frame **3**, wenn die Kuppel ihren vollen
  Radius (~28 px) erreicht.
- `taunt`: Aggro-Ruf + Debuff-Radius (Ring am Boden) aktiv ab Frame **2**.
- `guardian_leap`: Frame **0** ist Absprung, **1–2** Flugphase (i-Frames
  möglich), **3** Einschlag mit AoE-Radius ca. 22 px, **4** Recovery.

## Einbinden

Gleiches Verfahren wie bei den anderen drei Charakteren — siehe
[assets/sprites/README.md](../README.md#einbinden) für Godot/Phaser/Unity-Beispiele.
Frame-Indizes für dieses Sheet:

```json
"idle": [0,1,2,3],  "run": [6,7,8,9,10,11],  "shield_bash": [12,13,14,15,16],
"chain_swing": [18,19,20,21,22,23],  "bastion": [24,25,26,27,28],
"taunt": [30,31,32,33],  "guardian_leap": [36,37,38,39,40],
"hurt": [42,43],  "death": [48,49,50,51],  "ultimate": [54,55,56,57,58,59]
```

## Ändern / Erweitern

Generator: `tools/gen_sprites_guardian.py`. Importiert die gemeinsamen
Pixel-Primitive (`new_layer`, `thick_line`, `poly`, `rim_light`,
`outline_layer`, das Preview-Template, …) aus `tools/gen_sprites.py`, damit
alle vier Charaktere denselben visuellen Stil teilen, aber einen eigenen
Körperbau (`draw_guardian`, `pose(...)`) und eigene Animationen (`anim_*`)
haben.

```bash
python tools/gen_sprites_guardian.py
```

- Palette: `STL_*` (Stahl), `RUST_*` (Kette), `CLO_*` (Wappenrock),
  `GOLD_*` (heiliges Licht) am Dateianfang
- Körperbau: `draw_guardian()` und die `draw_*`-Teilfunktionen
- Neue Animation: Funktion `anim_x()` schreiben, die
  `(frames, fps, loop)` zurückgibt, und in `ANIMS` eintragen

**Gelernte Lektion (siehe Blutwolf/Schattenhexerin-READMEs):** Effekte, die
ein Zubehörteil (hier: der Schild) relativ zur Hand nach vorn schieben,
können mit anderen Brust-Details kollidieren (das Schild-Kreuz landete beim
`shield_bash` anfangs auf dem Brust-Kreuz). Bei neuen Angriffs-Animationen
den Bewegungsbereich der Anhänge vorher gegen die feste Körpermitte prüfen.
