# R12 – Real Human NPC Pilot (2026-11-09)

Ausgangs-Commit `e05b064`, gesichert als Branch `backup/pre-r12-2026-11-09`. Ergebnis: drei menschliche NPCs
(Passant, Passantin, Türsteher) aus einer **optimierten Pipeline** im laufenden Spiel; alle anderen NPCs bleiben R10.

## 1. Ausgangslage (gemessen)
- R10: Quaternius-Mannequin, 1 Material, gemeinsames Mesh, Animationen direkt.
- R11: MakeHuman-Figur, 7 Meshes/Materialien, 28,9 k Dreiecke, Animation per **Laufzeit-Retargeting** (zweites, unsichtbares Skelett pro Figur).
- Für viele NPCs zu teuer: 3 × R11 = **55 Draw Calls** (R10: 13) und 68 µs Animationszeit pro Figur (R10: 19 µs).

## 2. Pipeline (neu)
| Schritt | Datei | Ergebnis |
|---|---|---|
| Spezifikation | `tools/character/npc_specs.json` | Phänotyp, Haut, Haare, Kleidung je Typ |
| Bauen | `tools/character/build_r12_npc.py` (Blender 4.5 + MPFB 2.0.18) | wie R11, zusätzlich: **alle Texturen in einen 2048²-Atlas**, UVs umgerechnet, **alles zu einem Mesh mit einem Material** zusammengefügt, Alpha-Clip für Haare/Wimpern; **Dezimierung auf ~42 %**, Kopf über die Gewichtsgruppe `head` ausgenommen (Gesichter bleiben scharf) |
| Animationen | `tools/character/bake_npc_anims.gd` | UAL-Animationen (Idle, Walk, Idle_Talking) **einmalig** auf das NPC-Rig übertragen und als `AnimationLibrary` gespeichert (60 KB je Typ) → zur Laufzeit kein zweites Skelett |
| Laden | `src/p001/npc_human.gd` (`StrayNpcHuman`) | Modell + AnimationPlayer mit der Bibliothek; Meshes, Material und Animationen sind geteilte Ressourcen |
| Import | Atlas VRAM-komprimiert mit Mipmaps; Godot erzeugt LOD-Stufen beim Import | |

Beim Bauen gefundene Fehler: Die erste Animationsbibliothek war eingefroren – `Animation.optimize()` erwartet als
dritten Parameter eine **Ganzzahl**, `0.01` wurde zu 0 und reduzierte jede Spur auf einen Schlüssel. Zuerst hatte ich
eine andere Ursache vermutet (Abtasten des Skeletts) und das Abtasten umgebaut; das war nicht der Fehler, ist aber robuster.

## 3. Die drei Typen (alle CC0)
| Typ | Körper | Kleidung / Haare | Dreiecke |
|---|---|---|---|
| `passerby_m` | Mann ~30, durchschnittliche Statur, dunkle Haut | blaues Hemd, Jeans, Sneaker (male_casualsuit01, shoes02), Kurzhaar short04 | 15,5 k |
| `passerby_f` | Frau ~25, schlank | blaues T-Shirt, Jeans, Ankle-Boots (female_casualsuit01, toigo_ankle_boots_female), Pferdeschwanz ponytail01 | 13,2 k |
| `bouncer` | Mann ~35, groß und kräftig (Muskel 0,8, Größe 0,72), Glatze | dunkler Anzug mit Krawatte, schwarze Schuhe (male_elegantsuit01, shoes04) | 14,5 k |

Quellen/Lizenzen: `assets/characters/r12_npc/LICENSE_CC0.txt` (MakeHuman-Asset-Pack-Seiten, Spalte License + Dateiköpfe).

## 4. Renderkosten (Cloud, Software-Rendering – keine Geräte-FPS)
Drei Figuren nebeneinander, Walk, inkl. Schattenpass (`tools/character/r12_preview.gd perf`, leere Szene = 4 Draw Calls):

| | 3 × R10 | 3 × R11 | **3 × R12** |
|---|---|---|---|
| Draw Calls (4 m) | 13 | 55 | **13** |
| Dreiecke 4 m / 25 m | 124 k / 31 k | 161 k / 36 k | **110 k / 29 k** |
| Puffer-Speicher | 7,3 MB | 10,2 MB | 8,8 MB |
| Texturspeicher (über Grundlast) | 0 | +6,7 MB (1 Figur, 7 Texturen) | +16 MB (3 eigene 2048²-Atlanten) |
| Animation pro Figur (CPU) | 19 µs | 68 µs | **12 µs** |

Im Spiel (`tools/character/r12_scene_shots.gd`, gleiche Kamera vorher/nachher): NACHTFLUG-Ansicht 200 → **200** Draw Calls
(167 k → 167 k Dreiecke), Ring-Spawn 524 → **524** (162 k → 166 k), NACHTFLUG Spielersicht 288 → **288** (131 k → 134 k).
Web-ZIP 18,2 → 25,2 MB (3 Atlanten, VRAM-komprimiert für Desktop **und** Mobil).

## 5. Integration (nur drei NPCs)
`npc_config.json → r12_pilot`: Passant 0 am Ring = `passerby_m`, Schlange Platz 0 = `passerby_f`, Türsteher = `bouncer`.
Gleiche Kollisionsformen, Laufspuren, Animationen-Namen und Dialoge; Fallback auf R10, wenn die Dateien fehlen.

## 6. Prüfung
- `npc_pilot_test` 10/10: richtige drei NPCs, alle anderen 18 R10, Beine animiert, Passant läuft weiter (1,6 m in 1,5 s), Füße am Boden (tiefster Knöchel 0,11 m), Türsteher antwortet.
- Alle Regressionstests: **28 Suites, 427 Prüfungen, grün**; Python OK.
- Bilder (`production/qa/evidence/r12_npc/`): `R12_ingame_before_after.png` (NACHTFLUG bei Nacht, Türsteher + Schlange nah, Passant am Ring – gleiche Kameras), `R12_faces_closeup.png`, `R12_animations_walk_talk.png`, Lineup vorne/hinten.
- Web-Build in Chromium: lädt ohne Fehler, Ring mit NPCs sichtbar (`R12_web_chromium.png`); die Pilot-NPCs selbst habe ich im Browser **nicht** einzeln aus der Nähe geprüft.

## 7. Offene Probleme
1. Haare des Passanten wirken grau statt schwarz (Alpha-Clip/Glanz des Haar-Atlas) – prüfen.
2. Gesichter heller Haut wirken bei hartem Licht blass; Arme im Idle relativ weit vom Körper (UAL-Animation).
3. Finger fest gekrümmt (keine Fingeranimation, wie R11).
4. Jeder Typ hat einen eigenen 2048²-Atlas (+5 MB VRAM je Typ); für viele Typen besser gemeinsame Kleidungs-Atlanten oder 1024² für entfernte NPCs.
5. Nur 3 Animationen gebacken (Idle, Walk, Idle_Talking); Tanzen/Rennen für Club-NPCs fehlen.
6. Echte iPhone-/Tablet-FPS mit diesen NPCs ungemessen.

## 8. Empfehlung
Die Pipeline erfüllt das Ziel: R12-NPCs kosten so viele Draw Calls wie R10 und weniger als R11. Vor einer Umstellung
weiterer NPCs: FPS am NACHTFLUG auf dem iPhone über ≥ 10 s messen (FPS-Knopf). Danach schrittweise, je 2–3 weitere
Typen, mit gemeinsamen Atlanten.

## 9. Build
`build/stray_web_itch.zip`, SHA-256 `bb6f223f87d2b31f1a9e481fa9387f9e9103d403053cbe9a599d1dacb7c194e9`.
