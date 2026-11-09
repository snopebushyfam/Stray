# R9.1 – FPS-Anzeige für die Messung auf echter Hardware (2026-11-09)

Ausgangs-Commit `df6bf46`. Keine Änderung an Spielmechanik oder Grafikqualität.

## Bedienung

| Gerät | Ein/Aus |
|---|---|
| Tablet / Touch | Knopf **„FPS“** oben links (neben „Tag/Nacht“ und „Menü“) |
| Desktop | Taste **F3** |

Standard: **aus**. Anzeige oben rechts unter Bargeld/Ruf, grün:
`FPS 58 · Ø 10 s: 54.3` – aktuelle Bildrate (letzte ~0,5 s) und gleitender Durchschnitt der letzten 10 Sekunden.
Solange noch keine 10 s gesammelt sind, steht die Sekundenzahl dahinter, z. B. `(4 s)`. Jedes Einschalten startet
die Messung neu.

**Messanleitung Tablet:** Spiel starten → FPS einschalten → 10–15 s an der zu messenden Stelle stehen oder laufen →
Ø-Wert ablesen (Screenshot). Sinnvolle Stellen: Spawn am Ring, NACHTFLUG-Eingang, Hbf-Vorplatz, Club innen.

## Umsetzung

| Datei | Inhalt |
|---|---|
| `src/p001/fps_meter.gd` (neu) | reine Logik: Bilddauern sammeln, aktuelle FPS, 10-s-Durchschnitt |
| `src/p001/main.gd` | Label (ignoriert Touch/Maus, blockiert also weder Kamera-Wischen noch Joystick), `toggle_fps()`, Touch-Knopf 64 × 40 px, Hinweis „F3: FPS“ in der Hilfezeile |
| `data/p001/player_config.json` | Aktion `toggle_fps` = F3 |

Gemessen wird mit der **Wanduhr** (`Time.get_ticks_usec`) zwischen zwei Bildern, nicht mit Godots `delta`:
Godot begrenzt `delta` bei sehr langsamen Bildern. Im ersten Browser-Test zeigte die Anzeige deshalb „8 FPS“,
während der Browser nur ~1 Bild/s ausgab. Nach der Korrektur stimmt die Anzeige (0,9 FPS) mit einer
unabhängigen Browser-Messung (requestAnimationFrame) überein.

## Prüfung

| Prüfung | Ergebnis |
|---|---|
| `fps_meter_test` (Durchschnitt, Abfall, 10-s-Fenster) | 7/7 |
| `fps_display_test` (aus per Standard, F3 zeigt, Text, kein Touch-Fang, Steuerung unverändert, wieder aus) | 6/6 |
| alle Regressionstests | 24 Suites, 383 Prüfungen, grün; Python OK |
| Web-Build Chromium, Desktop: F3 an/aus | funktioniert (`production/qa/evidence/r9_1_fps/web_desktop_fps_*.png`) |
| Web-Build Chromium, simuliertes Touch: Knopf an/aus | funktioniert (`web_touch_fps_*.png`); erster Test fand den Knopf zu klein → auf 64 × 40 px vergrößert |

**Die Cloud-Werte (≈ 0,9 FPS) sind Software-Rendering ohne Grafikkarte und keine Tablet-Leistung.** Die echte
Messung kann nur auf dem Gerät erfolgen.

## Build

`build/stray_web_itch.zip`, SHA-256 `c8e44cfeff7363b5e06ef35f98bdfa2b6db808bcb6f3e627bb55ee7c7b26a466`.
