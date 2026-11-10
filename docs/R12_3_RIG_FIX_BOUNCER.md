# R12.3 – Türsteher neu aufgebaut, Rig-Fehler aller R12-Figuren behoben (2026-11-10)

Branch `claude/jolly-allen-b3y08s`, Ausgangsstand `98eb9e1` (R12.2). Anlass: Nutzer-Feedback zum R12.2-Türsteher
(„sieht so ein Mensch aus oder eher ein Monster?“). Das Feedback war berechtigt.

## 1. Ehrliche Einordnung

In R12.1/R12.2 habe ich die Figuren nur **relativ zum Vorher-Stand** und auf kleinen Bildern bewertet, nicht gegen echte
menschliche Proportionen. Dadurch ist ein grundlegender Fehler unentdeckt geblieben.

## 2. Ursache (gemessen)

`tools/character/build_r12_npc.py` baute die Figuren mit `detailed_helpers: False`. Diese Option löscht die
`joint-*`-Vertexgruppen, aus denen MPFB die Gelenkpositionen des Rigs berechnet. Folge: **Alle drei NPCs bekamen das
Standard-Skelett** – unabhängig vom Körper:

| Figur | Körperhöhe | Kopfgelenk vorher (Anteil Körperhöhe) | Schultergelenk x vorher | nachher Kopf | nachher Schulter |
|---|---|---|---|---|---|
| Passantin | 1,61 m | 1,533 m (0,95 – Gelenk im Kopf) | 0,170 | 0,911 | 0,153 |
| Passant | 1,83 m (vorher 1,94) | 1,536 m | 0,170 | 0,915 | 0,193 |
| Türsteher | 1,87 m (vorher 1,95) | 1,519 m (0,78 – 27 cm zu tief) | 0,170 (Körper: 0,20) | 0,917 | 0,195 |

Jede Animation drehte Schultern und Hals daher um falsche Punkte. Beim großen, breiten Türsteher entstanden so die
aufgeblähten „Schulterpolster“ und der gestauchte Hals. Die Messung in Godot (Skin-Bindposen und Skelett-Ruhelage)
zeigte identische Skelette für alle drei; die Kontrolle in Blender zeigte, dass das Rig direkt nach dem Erzeugen
nicht angepasst war.

## 3. Änderungen

| Bereich | Änderung |
|---|---|
| Build | `detailed_helpers: True`, zusätzlich `RigService.refit_existing_armature` als Absicherung; Log `R12 rig refit` |
| Türsteher | Durchschnittlicher Körperbau (muscle/weight 0,55), ~1,87 m, schwarzes T-Shirt + dunkle Hose (`male_casualsuit06`, per Atlas eingefärbt, neue `tint`-Option) statt gepolstertem Anzug; Arm-Adduktion 6° |
| Passant | Größe 0,6 → 0,52 (1,94 m → 1,83 m) |
| Alle drei | neu gebaut, neu importiert, Animationen neu gebacken (`walk_natural_speed` m 0,91 / f 0,73 / Türsteher 0,94) |
| Test | neu `tests/unit/p001/npc_rig_fit_test.gd`: Kopfgelenk bei 88–94 % der Körperhöhe, verschiedene Körper → verschiedene Skelette (hätte den alten Stand mit 0,78/0,95 erkannt) |

## 4. Prüfung

Bilder: `production/qa/evidence/r12_3_rig_fix/`.

- Türsteher von vorn/seitlich/hinten/45°: normale Schultern, sichtbarer Hals, Arme hängen am Körper. Proportionen im
  Bild: ~7,3 Kopfhöhen, Schulterbreite ~2 Kopfhöhen – im menschlichen Bereich.
- Alle drei Figuren (`after_sheet_all_npcs.png`, `after_walk.png`): lesen sich als normale Menschen, auch im Gehen.
- Im Spiel am NACHTFLUG (`r123_*.png`) und im Web-Export in Chromium (`web_chromium_nachtflug.png`).
- Haltungsmessung (`motion_metrics.gd`): Kopf-/Rumpfwinkel im Bereich der Quell-Animation, keine Überkorrektur.
- Tests: 29 Suites, `ALL_TESTS_EXIT=0`.

## 5. Offene Punkte (ehrlich)

- Es bleiben MakeHuman-Figuren mit CC0-Kleidung: gut als „normale Leute“, aber nicht auf dem Niveau professionell
  modellierter Spielfiguren (Gesichter glatt, Kleidung einfach, T-Shirt trägt ein schwaches MakeHuman-Logo).
- Passantin: Schuhe erscheinen weiß/flach (Material der CC0-Schuhe) – nicht in R12.3 behandelt.
- Die übrigen NPCs sind weiterhin R10-Mannequins.
- FPS auf dem Gerät **nicht gemessen**; Dreiecke je Figur unverändert in der Größenordnung (Türsteher 18 752).

## 6. Build

`build/stray_web_itch.zip` (`tools/release/package_itch.sh`), SHA-256 `ea30bdbf753d53c14883f980b2480c59004fafc22644c1aeed22de57eded22f5`.
