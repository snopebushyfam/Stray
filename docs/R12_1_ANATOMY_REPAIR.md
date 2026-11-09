# R12.1 – Anatomy & Rig Repair der R12-NPCs (2026-11-09)

Ausgangs-Commit `f0e9d7e`, gesichert als Branch `backup/pre-r12_1-2026-11-09`. Architektur erhalten: MakeHuman/MPFB →
ein Mesh, ein Atlas-Material pro NPC, vorab gebackene Quaternius-Animationen, R10 als Fallback.

## 1. Ausgangsfehler (gerendert: `tools/character/r12_audit.gd`, alle Bilder `production/qa/evidence/r12_1_anatomy/`)
| Figur | Sichtbar (VORHER-Zeilen der `*_compare_*.png`) |
|---|---|
| passerby_m | spitze, hochgezogene Hemdschultern; Arme ~20° abgespreizt; Oberkörper vorgebeugt; Krallenfinger beim Reden |
| passerby_f | gespreizte, nach hinten überstreckte Fächerhände (Idle + Talk); Arme abgespreizt |
| bouncer | Anzugschultern wie Superheld (spitz nach oben/außen); Arme abgespreizt; Krallenhände |

## 2. Nachgewiesene Ursachen
| # | Ursache | Ebene | Nachweis |
|---|---|---|---|
| 1 | **T-Pose ins Mesh gebacken.** MakeHumans Gewichte sind für die A-Pose gemalt. Mit T-Pose-Bindung muss Linear-Blend-Skinning die Schulter in jeder Idle/Walk-Pose ~80° zurückdrehen (statt ~40°) → kollabierte, spitze Schultern. | Export/Skinning | gleiche Figur ohne T-Konvertierung: natürliche Schultern (Experiment, `*_compare_poses.png` Spalte shoulder45); Gewichtsansicht: vorher praktisch kein Schlüsselbein-Einfluss sichtbar, nachher klar (rot) |
| 2 | **Finger mit fester lokaler Achse gekrümmt** (R11-Retargeting). Die Knochen der rechten/linken Hand sind gespiegelt → eine Hand bog nach hinten (Fächer), die andere zu stark (Kralle). | Retargeting | Messung: Fingerwinkel zur Hand bis 84° bzw. Rückwärtsbiegung; R11-Achsentest hatte nur eine Hand geprüft |
| 3 | **Handflächen-Verdrehung.** MakeHumans A-Pose dreht die Mittelhand nach vorn (Ruhe-Richtung z = 0,75). Die virtuelle Ausrichtung auf dem kürzesten Bogen ließ die Handfläche gegen die UAL-Handfläche verdreht. | Retargeting | Messung der Handrichtung + Renders |
| 4 | **Bulliges Quell-Mannequin.** UAL hält die Arme in Idle ~20° abgespreizt (breiter Rumpf). Schlanke Menschen übernahmen das 1:1. | Animationsquelle | Richtungsvergleich: Oberarm Quelle/Ziel 1° gleich – Fehler liegt in der Quelle, nicht im Mapping |
| 5 | **Schlüsselbein-Ruhepose 37° verschieden.** Die volle Mannequin-Bewegung rollte die Schultern 16° nach vorn/unten. | Retargeting | Richtungsvergleich Ruhe + Idle |
| 6 | Dezimierung des **zusammengefügten** Meshes. (Mein erster Reparaturversuch mit gewichteter Schutzgruppe ließ die Kleidung zu wenigen Dreiecken kollabieren – verworfen.) | Export | Renders der Experimente |

Keine Ursache: Gewichte sind normalisiert (0 nicht normalisierte Vertices, 4 Einflüsse), Hüfte/Beine/Fußkontakt korrekt (Knöchel ≥ 0,11 m im Gang, kein Versinken).

## 3. Reparaturen
**Export (`tools/character/build_r12_npc.py`):**
- Bindung bleibt in **MakeHumans A-Pose** (T-Pose nur noch mit `--tpose`).
- Dezimierung **pro Teil vor dem Zusammenfügen**, ohne Vertex-Gruppen: Kleidung 50 %, Schuhe 45 %, Haare 60 %, sichtbare Haut (Gesicht, Hände, Arme) 75 %, Augen/Brauen/Wimpern unverändert.

**Retargeting (`src/p001/human_rig.gd`, wirkt beim Backen und auf die R11-Spielfigur):**
- **Virtuelle T-Pose:** Arme und Beine werden zur Laufzeit auf die UAL-Ruherichtungen ausgerichtet (statt Mesh-Umbau).
- **Unterarm und Hand:** Ausrichtung über vollständige Bezugssysteme (Knochenrichtung + Handflächen-Normale).
- **Finger:** MakeHumans entspannte Ruhehand plus leichte Beugung (0,04–0,12 rad pro Glied, Ringfinger und kleiner Finger etwas mehr). Die Beugeachse kommt aus Fingerrichtung × Handflächen-Normale (spiegelt korrekt), die Spreizung ist um 60 % reduziert.
- **Adduktion:** Hängende Oberarme werden zum Körper gedreht, pro Typ aus `npc_specs.json → retarget`: Passant 12°, Passantin 4° (schmale Schultern, breite Hüfte – mehr ließ die Hand in den Oberschenkel eintauchen), Türsteher 8°.
- **Schlüsselbein:** nur 40 % der Mannequin-Bewegung.

**Backen (`tools/character/bake_npc_anims.gd`):** übernimmt die Typ-Einstellungen. **QA:** `tools/character/r12_audit.gd` (Bindpose, Idle vorn/seitlich/hinten, Schulter 45°, beide Hände, Knochenachsen, Gewichtsansicht, Walk + Talk in je 6 Phasen); Startparameter `--qa-npc` (Blick auf Türsteher + Schlange, auch im Web-Build über die Test-HTML).

## 4. Vorher/Nachher (gleiche Kamera, Animationszeit, Licht)
- Pro Figur `<id>_compare_poses.png` (Idle vorn, seitlich, Schulter 45°, linke + rechte Hand, Gewichte) und `<id>_compare_animations.png` (Walk + Idle_Talking je 6 Phasen).
- Im Spiel: `R12_1_ingame_before_after.png` (NACHTFLUG bei Nacht, Türsteher + Schlange nah, Passant am Ring); Web: `R12_1_web_chromium_nachtflug.png`.

## 5. Bewertung je Figur (aus den Bildern)
| Figur | Ergebnis |
|---|---|
| passerby_m | **abgenommen.** Schultern rund, Arme hängen, entspannte Hände in Idle/Walk/Talk |
| passerby_f | **abgenommen.** Keine Fächer-/Krallenhände mehr, Hände nicht mehr im Oberschenkel, Schultern natürlich |
| bouncer | **abgenommen, mit Einschränkung:** Arme ruhig, Hände natürlich; die Anzugschultern sind breit (Kleidungsmodell `male_elegantsuit01` + kräftige Statur), aber nicht mehr spitz/deformiert |
| R11-Spielfigur | profitiert mit (entspannte Hände statt Krallen), `R11_player_with_new_retarget.png` |

## 6. Regressionstests
Alle **28 Suites, 427 Prüfungen grün**, Python OK (`tests.log`), darunter `npc_pilot_test` (Spawn, Lauf, Füße, Türsteher-Antwort, Schlange), `character_variant_test` (R11), Prolog, Speichern, Kollisionen. Web-Build in Chromium: lädt fehlerfrei, Türsteher und Passantin wie in Godot.

## 7. Performance (Cloud, Software-Rendering – keine Geräte-FPS)
| | R12 | R12.1 |
|---|---|---|
| Dreiecke pro NPC (m / f / Türsteher) | 15,5 k / 13,2 k / 14,5 k | 21,3 k / 20,7 k / 22,7 k |
| Draw Calls (3 NPCs, inkl. Schatten) | 13 | **13** |
| Dreiecke 3 NPCs nah / fern (inkl. Schattenpass) | 110 k / 29 k | 194 k / 47 k |
| Im Spiel: NACHTFLUG-Ansicht / Ring / NACHTFLUG Spielersicht | 167 k / 166 k / 134 k | 188 k / 167 k / 141 k (Draw Calls unverändert 200 / 524 / 288) |
| Texturspeicher | 46,7 MB | 46,7 MB (unverändert) |
| Animation pro NPC | 12 µs | 12 µs |
| Web-ZIP | 25,2 MB | 25,8 MB |

Begründung: +6–8 k Dreiecke pro NPC, weil die bisherige globale 42-%-Dezimierung Gelenk- und Handgeometrie traf. Im Spiel
+0,5–13 % Dreiecke, Draw Calls gleich.

## 8. Nicht gelöst
1. Leichte Vorbeuge des Oberkörpers im Stand und Gang – stammt aus den UAL-Animationen (Mannequin-Haltung), nicht aus dem Rig.
2. Breitbeiniger Stand in Idle (UAL).
3. Finger statisch (bewusst: korrekte statische Hand statt fehlerhafter Animation).
4. Türsteher-Anzug an den Schultern breit/kastig (Kleidungsmodell).
5. Keine echte Messung auf iPhone/Tablet mit R12.1.

## 9. Build
`build/stray_web_itch.zip`, SHA-256 `8ed541b0386c5f049888f9233926912444cfa7764a4ca52ca74733099d710a02`.
