# QA-Evidence

## Godot (aktiv) — `godot/`

Aufgenommen 2026-11-08 in der Cloud-Umgebung mit Godot 4.7.2 (Compatibility-Renderer,
Software-OpenGL llvmpipe unter Xvfb) über `godot --path . -- --autoshots`:

* `P001_00_player_spawn_night.png` — Third-Person-Sicht am Spawn
* `P001_0[1-5]_*_night.png` / `_day.png` — Blickpunkte aus `data/p001/P001_Layout.json`
* `P001_web_chromium_webgl2.png` — derselbe Spawn im **Web-Export** in Chromium (WebGL 2, SwiftShader)
* `P001_autoshots_log.txt` — alle `STRAY_DIAG`-Zeilen (Build, Spawn, Bodenprüfung)
* `P001_tests_log.txt` — Unit-, Lauf- und Datentests

Nicht abgedeckt: echte Tablet-/Handy-GPU, Touch mit dem Finger, Bildrate auf echter Hardware.

## Unreal (archiviert) — keine Evidence

Unreal lief in keiner Umgebung. `docs/prototype-001/*.png` sind matplotlib-Datenvorschauen,
keine Spiel-Evidence.
