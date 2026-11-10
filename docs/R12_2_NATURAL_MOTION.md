# R12.2 – Natural Human Motion der R12-NPCs (2026-11-10)

Ausgangs-Commit `d7f0793`, gesichert als Branch `backup/pre-r12_2-2026-11-10`. Die R12.1-Anatomie (A-Pose-Bindung,
Schulterverformung, Handflächen, Finger) bleibt unverändert; geändert werden nur die **gebackenen Animationsdaten**.

## 1. Ursachen (gemessen mit `tools/character/motion_metrics.gd`)
Gleiche Kennzahlen an der Quelle (Quaternius UAL, CC0) und an den gebackenen NPCs:

| Problem | Quelle UAL | NPC vorher | Herkunft |
|---|---|---|---|
| Breiter Stand (Fußabstand / Hüftbreite) | 2,06 (0,36 m) | 1,91 (0,38 m) | **Quellanimation** |
| Vorgeneigter Oberkörper (Becken→Hals) | +8,0° Idle, +11,6° Walk | +8,3° / +11,1° | **Quellanimation** |
| Gebeugte Knie im Stand | 24° | 24° | **Quellanimation** |
| Kopf nach vorn geschoben (Hals→Kopf) | +16° | +26° | **Retargeting** (andere Hals-/Kopf-Ruhepose bei MakeHuman) |
| Fehlende Eigenbewegung im Stand | Becken 1,2 cm, Hand 4,5 cm | 1,1 cm / 3,9 cm | **Quellanimation** |
| Übertriebene Redegesten | Hand 17 cm | 15 cm | **Quellanimation** |
| Rutschende Füße beim Gehen | Standfuß 0,88 m/s | 0,78 m/s, Wiedergabe auf 0,97 m/s skaliert | **Konfiguration** (Wert aus dem Root-Motion-Modell) → ~20 % Rutschen |
| Armschwung | 36° (`Walk_Formal` nur 7°) | 35° | normal – kein Fehler |
| Übergänge | – | 0,25 s Überblendung | in Ordnung; profitierten vom engeren Stand |

Geprüfte Alternativen: `Walk_Formal` (steifer, 7° Armschwung) – nicht verwendet. Keine neuen Assets nötig.

## 2. Korrekturen (nur beim Backen, `tools/character/bake_npc_anims.gd`, Werte in `npc_specs.json → motion`)
| Was | Wie |
|---|---|
| Stand | Füße per Zwei-Knochen-Bein-IK nach innen (Faktor 0,65 → 0,25 m, 1,24 × Hüftbreite), Fußrotation bleibt, Becken um 2 cm angehoben (Knie streckt sich) |
| Haltung | `spine_01` 5–6° aufgerichtet, Kopf 7–8° zurück |
| Leben im Stand | Idle über 2 Quellzyklen (5 s): langsame Gewichtsverlagerung (Becken ±1,6 cm seitlich, Hüfte senkt sich auf der freien Seite, Beine neu gelöst → Füße bleiben stehen), Atmung, kleine Kopfdrehung; nahtlos geloopt |
| Reden | Armbewegung zu 65 % (Mischung mit dem Idle-Arm zur selben Zeit) |
| Gehen | Oberkörper 5° auf, Kopf 7° zurück; gemessene Standfuß-Geschwindigkeit (0,82 / 0,82 / 0,78 m/s) als Metadaten → `pedestrians.gd` skaliert damit (kein Rutschen) |
| Türsteher | Arm-Adduktion 8° → 15° (das kastige Sakko ließ die Arme weit abstehen) |

Laufzeit: unverändert – keine zusätzlichen Skelette, kein IK, keine Korrekturwinkel pro Bild.

## 3. Ergebnis (gemessen, NPC nachher)
| | vorher | nachher |
|---|---|---|
| Stand | 0,38 m | **0,25 m** |
| Oberkörper Idle / Walk | +8,3° / +11,1° | **+3,1° / +6,8°** |
| Kopf vor Hals | +26° | **+20,5°** |
| Knie Idle | 24° | **17°** |
| Becken-Bewegung Idle | 1,1 cm | **3,4 cm** |
| Hand Idle_Talking | 15 cm | **12 cm** |
| Walk-Wiedergabe | 0,97 m/s Annahme | gemessene 0,78–0,82 m/s |

## 4. Visuelle Prüfung
`production/qa/evidence/r12_2_motion/`:
- `<id>_sequences_before_after.png`: Idle 8 Bilder über 5 s (vorn + seitlich), Walk-Zyklus 8 Bilder (Kamera fährt mit Körpergeschwindigkeit, Bodenlinien alle 0,5 m), Idle_Talking 8 Bilder, Übergang Idle → Walk → Idle (12 Bilder, 0,25 s Überblendung wie im Spiel) – je vorher/nachher, gleiche Kamera.
- `<id>_detail_before_after.png` (vergrößert), `frames_after/` (Schulter 45°, beide Hände).
- Im Spiel: `R12_2_ingame_before_after.png`; Web: `R12_2_web_chromium_nachtflug.png`.

Bewertung: **sichtbar natürlicher.** Alle drei stehen aufrechter mit schmalerem Stand, der Kopf sitzt über den
Schultern, der Gang ist aufrechter, die Redegesten ruhiger. Der Türsteher steht souveräner mit anliegenden Armen.
Schultern, Hände und Finger aus R12.1 sind unverändert (Detailbilder).

## 5. Tests & Leistung
- Alle **28 Suites, 427 Prüfungen grün**, Python OK – Prolog, Schlange, Türsteher-Dialog, NPC-Bewegung, Touch-Steuerung (`touch_look_test`, `touch_run_test`), Speichern.
- Web-Build Chromium: lädt, NPCs wie in Godot.
- Draw Calls unverändert (NACHTFLUG 200, Ring 524); Animation pro NPC **12 µs** wie vorher (R10 15 µs, R11 75 µs);
  Animationsdateien 62 → 74 KB je Typ (5-s-Idle); Web-ZIP 25,8 → 25,9 MB.
- **Keine FPS-Aussage** für diese Version ohne Gerätemessung (R12.1: 60,2 FPS Ø über 5 s am iPhone vor NACHTFLUG).

## 6. Offen
1. Knie im Stand noch leicht gebeugt (17°); stärker strecken lässt die IK die Beine durchdrücken – bewusst begrenzt.
2. Gang selbst (Schrittzyklus, Armschwung) bleibt die UAL-Animation – solide, aber generisch; ein natürlicherer Gang bräuchte eine andere Quellanimation (z. B. Motion-Capture, CC0).
3. Redegesten wiederholen sich alle 2,9 s.
4. Fußrutschen nur über die Wiedergabegeschwindigkeit gelöst; bei Geschwindigkeitswechseln (Bremsen vor Hindernissen) kann es kurz rutschen.

## 7. Build
`build/stray_web_itch.zip` (25,9 MB), SHA-256 `180507262b76d596f6f8378656cc190172aad10e43745debd8c4aed9727fa941`.
