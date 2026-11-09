# R11 – Real Human Character Prototype (2026-11-09)

Ausgangs-Commit `2c7dd5f`. Ergebnis: **ein** echt menschlich geformter, bekleideter Charakter (MakeHuman/MPFB,
CC0), animiert mit den vorhandenen Quaternius-Animationen, als **optionale** Spielfigur (Pausemenü „Figur“).
R10 bleibt Standard und Fallback; NPCs sind unverändert.

## 1. Umgebung (geprüft, nicht angenommen)

| Werkzeug | Befund |
|---|---|
| Blender, MakeHuman | nicht installiert |
| Blender 4.5.15 LTS (Linux x64) | von download.blender.org geladen, `blender -b` läuft (Werkzeug, nicht im Spiel) |
| MPFB 2.0.18 | von extensions.blender.org (SHA-256 `c075b3e9…2dad`, GPL-3.0 – Code, nicht Teil des Spiels), headless installiert |
| MakeHuman-Assetpakete | files.makehumancommunity.org erreichbar: `makehuman_system_assets_cc0.zip`, `shirts01_cc0`, `pants01_cc0`, `shoes01_cc0` |
| Godot 4.7.2 | vorhanden (Spiel, Tests, Web-Export) |

## 2. Quellen und Lizenzen (an den Originalquellen geprüft)

| Teil | Asset | Lizenz – Nachweis |
|---|---|---|
| Körper | MakeHuman-Basemesh + Makro-Targets | CC0 (Asset-Pack-Seite „makehuman_system_assets“, Spalte License) |
| Haut | `young_caucasian_male` (Textur `young_lightskinned_male_diffuse`) | CC0 (dieselbe Seite) |
| Augen / Brauen / Wimpern | `low-poly` + `brown`, `eyebrow001`, `eyelashes02` | CC0 (dieselbe Seite) |
| Haare | `short02` | CC0 (dieselbe Seite) |
| Kleidung | `male_casualsuit05` (Jacke, Hemd, Jeans), `shoes05` (weiße Sneaker) | CC0 – Seite + Dateikopf „This asset was explicitly released as CC0 in september 2020“ |
| Rig | MPFB `game_engine` | Teil der MPFB-Daten; das erzeugte Modell ist Nutzerinhalt (MakeHuman: Assets/Ausgabe CC0) |
| Animationen | Quaternius Universal Animation Library | CC0 (bestehend) |

Nicht verwendet: CC-BY-Pakete (z. B. „System eye materials 03“). Lizenzhinweis: `assets/characters/r11_human/LICENSE_CC0.txt`.

## 3. Modell und Rig

- Build reproduzierbar: `blender -b --python tools/character/build_r11_human.py -- <out.glb>` (Assets im MPFB-Userdatenordner).
  Mann, ca. 25 Jahre, Muskel 0,5 / Gewicht 0,48 / Größe 0,55 (MakeHuman-Skala) → **natürliche Proportionen**, 1,68 m.
- Körper unter der Kleidung über die Lösch-Gruppen der Kleidung ausgeblendet (kein Durchstechen, weniger Dreiecke).
- Rig `game_engine`: 53 Knochen, **gleiche Unreal-Namen wie die UAL-Animationen** (pelvis, spine_01–03, neck_01,
  upperarm_l …; nur `head`/`Head`, `Root`/`root` unterscheiden sich in der Schreibweise).
- Ruhepose auf **T-Pose** umgestellt (Arme waagerecht wie die UAL-Bindpose). Im Lauf gefundene Fehler: Arme zeigten
  zuerst nach vorn (Rig lag 0,84 m unter dem Mesh, weil MPFB nur das Mesh auf den Boden hebt) → `feet_on_ground` aus,
  Rig + Mesh danach gemeinsam angehoben (`R11_tpose_rest.png`).
- Export GLB 7,0 MB, Texturen auf 1024 px (Brauen/Wimpern 512 px), in Godot **VRAM-komprimiert mit Mipmaps** importiert.

## 4. Animation / Retargeting

`src/p001/human_rig.gd` (`StrayHumanRig`): ein unsichtbares UAL-Modell spielt die Animation; pro Bild wird für jeden
gleichnamigen Knochen die **Rotationsdifferenz zur Ruhepose im Weltraum** auf die Ruhepose des Menschen übertragen,
die Hüftverschiebung mit dem Hüfthöhen-Verhältnis (0,973) skaliert. Der AnimationPlayer liegt im Rig, daher läuft der
vorhandene Spieler-Code unverändert. Läuft nach dem AnimationPlayer (`process_priority`).

| Test | Ergebnis |
|---|---|
| Idle, Walk, Jog_Fwd (Rennen), Sprint, Dance, Idle_Talking | übertragen und gerendert (`R11_animations_walk_jog_sprint_dance_talk.png`, je 6 Phasen); Arme, Beine, Rumpf, Kopf korrekt |
| Knochenzuordnung | 23 von 53 Knochen übertragen (Körper); **Finger nicht**: Die Finger-Ruheposen der Rigs unterscheiden sich, Übertragung ergab „Krallen“. Finger bekommen eine feste, leicht gekrümmte Haltung (Achse in `R11_finger_axis_test.png` bestimmt) |
| Fußkontakt | Hüftskalierung zunächst falsch (0,061 – UAL-Skelett skaliert) → im gemeinsamen Raum gemessen; Test: Knöchel beim Gehen tiefster Punkt 0,11 m über Boden, nie unter −0,08 m |
| Kleidung | verformt sich mit (Skinning der MPFB-Kleidung); in den Bildern kein sichtbares Durchstechen; bei Sprint knickt der Jackenärmel an der Schulter etwas ein |
| Integrationstest `character_variant_test` | 8/8: Standard R10, Umschalten auf R11, Gehen animiert die Beine, Füße am Boden, Wahl wird gespeichert/geladen, zurück auf R10 |

## 5. Sichtbare Qualität

`production/qa/evidence/r11_human/`: Vorder-/Seiten-/Rückansicht, Gesicht und Kleidung nah, Vergleich mit dem
R10-Mannequin (`r11_vs_r10.png`), im Spiel bei Nacht und Tag (`R11_in_game_R10_vs_R11_night_day.png`), Web-Build
(`R11_web_chromium.png`). Deutlich menschlicher: Gesicht mit Augen, Nase, Mund, Ohren; echte Frisur; Jacke mit Taschen
und Kragen über einem Hemd, Jeans mit Waschung, Sneaker – alles Geometrie mit Texturen. Schwächen: Hände ohne
Fingeranimation; Haut im Gesicht wirkt bei hartem Licht etwas blass; Haar-Kanten leicht hart (Alpha).

## 6. Renderkosten (gemessen, Cloud-Software-Rendering)

Eine Figur allein (`tools/character/r11_preview.gd perf`, Grundlast der leeren Szene: 4 Draw Calls):

| | R10 | R11 |
|---|---|---|
| Draw Calls, 3 m (inkl. Schattenpass) | 6 | 19 (7 Materialien) |
| Dreiecke, 3 m | 27,5 k | 49,4 k |
| Dreiecke, 25 m (Godot-LOD) | 10,3 k | 11,6 k |
| Texturspeicher (Messung vor der VRAM-Kompression) | – | +32 MB |
| Datei | geteilt (UAL 7,6 MB) | +7,0 MB GLB + 6 MB Texturen |

Im Spiel als Spielfigur (`tools/perf/render_probe.gd`, R10 → R11): Ring 514 → 512 Draw Calls (164 k → 168 k Dreiecke),
NACHTFLUG 279 → 289, KIOSK 313 → 331, Hbf 147 → 153. Web-ZIP 12,9 → 18,2 MB. **Keine Aussage über Tablet-FPS** – mit
dem FPS-Knopf messen (R10 vs. R11 über das Pausemenü umschaltbar).

## 7. Verbleibende Probleme
1. Finger statisch (keine Fingeranimation).
2. 7 Materialien pro Figur – für viele NPCs zu teuer (s. Empfehlung).
3. Leichtes Einknicken der Jackenschulter bei extremen Posen (Sprint/Tanz).
4. Gesichtsbeleuchtung/Haut ohne Subsurface; Augen wirken bei Nacht dunkel.
5. Nicht auf echtem Tablet geprüft (Speicher, FPS).

## 8. Empfehlung für alle NPCs
- Pipeline funktioniert (Build-Skript + Laufzeit-Retargeting) → nächster Schritt **nicht** 18 Einzelfiguren, sondern
  ein **NPC-Baukasten**: 2–3 Körper (m/w, verschiedene Statur) mit **Proxy-Körper** (deutlich weniger Dreiecke),
  Kleidung/Haare/Haut in **einen Texturatlas** gebacken → 1–2 Materialien pro Figur, Varianten über Farbtöne.
- Retargeting für viele NPCs teurer (pro Figur ein unsichtbares Skelett): besser die Animationen einmalig in Blender
  auf das MPFB-Rig übertragen und mitexportieren (dann kein Laufzeit-Retargeting).
- Erst nach einer Tablet-Messung der R11-Spielfigur umstellen.

## 9. Tests und Build
- Alle Regressionstests: **27 Suites, 417 Prüfungen, grün**; Python OK.
- Web-Build in Chromium: Spiel startet, Pausemenü „Figur“ schaltet auf R11, Figur erscheint und läuft.
- `build/stray_web_itch.zip`, SHA-256 `8c4613bb8d683846d51b73bb07a01479a52b800022cea42654ece7606cb2e411`.
