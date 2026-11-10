# R12.5 – Echte Bewegungsaufnahmen für Gehen und Joggen der Spielfigur (2026-11-10)

Branch `claude/jolly-allen-b3y08s`, Ausgangsstand `36e33ec` (R12.4). Anlass: Nutzer-Video vom iPhone – Laufen
„besser, aber immer noch inakzeptabel“. Der Nutzer hat die Asset-Regel gelockert (fertige Skelette/Anatomie,
Hilfe aus dem Internet erlaubt).

## Ursache

Die CC0-Quaternius-Animationen sind für eine stilisierte Puppe gemacht (Jog = Comic-Sprint mit 25° Rumpfneigung,
Riesenschritten, 25 cm Flugphase). Nachträgliches Korrigieren (R12.4) blieb sichtbar künstlich: abgespreizte Arme,
gekrümmte Hände, geduckter Lauf.

## Lösung

Echte Motion-Capture-Daten der **CMU Graphics Lab Motion Capture Database** (Nutzungsbedingung: „may be copied,
modified, or redistributed without permission“, Details `assets/characters/mocap_cmu/SOURCE.txt`):

| Clip | Quelle | Schleife | natürliche Geschwindigkeit |
|---|---|---|---|
| Walk | CMU 35_01 „walk“ | 1,12 s (ein Doppelschritt) | 1,15 m/s |
| Jog_Fwd | CMU 35_17 „run/jog“ | 0,74 s | 3,01 m/s |
| Idle | bleibt die R12.2-UAL-Stehpose | – | – |
| Jump | bleibt UAL | – | – |

Pipeline:
- `tools/character/convert_cmu_bvh.py` (Blender): BVH importieren, beste Schleife automatisch suchen
  (Posen- und Geschwindigkeitsdifferenz an der Naht), neues Skelett mit der T-Pose (Bild 1 der BVH) als Ruhepose,
  Bewegung weltweit übertragen und gebacken, Richtung ausgerichtet, Vorwärtsdrift entfernt (auf der Stelle),
  Knochen auf die Unreal-Namen des MPFB-Rigs umbenannt, Hilfs-Fingerknochen für die Handausrichtung.
- `bake_npc_anims.gd`: Quelle pro Clip (`drivers`), eigene Retarget-Werte (`driver_retarget`: keine
  Arm-Adduktion, volle Schlüsselbeinbewegung, **Handgelenk nicht übertragen** – CMU-Handdaten knickten die Hände
  flach ab) und eigene Haltungskorrektur (`driver_motion`, gemessener T-Pose-Versatz: Walk Rumpf −7,3°,
  Jog Kopf −12°).
- `human_rig.gd`: neue Option `skip_bones`.
- `player_config.json`: Renngeschwindigkeit 4,5 → **3,8 m/s** (13,7 km/h). Der echte Jog ist bei 3,0 m/s natürlich;
  4,5 m/s hätte 1,5-faches Abspieltempo (~240 Schritte/min, hektisch) bedeutet.
- `touch_run_test`: misst die Spitzengeschwindigkeit (ein kreuzender Passant lenkte die Figur ab) und prüft
  „Rennen“ gegen volles Gehen.

Verworfen: CMU-Steh-Clips (40_10 „wait for bus“, 82_08 „stand still“) – gebückt, gestikulierend, Körper dreht sich;
die UAL-Stehpose mit R12.2-Korrektur wirkt ruhiger. Der Konverter hat dafür einen `idle`-Modus, er wird nicht benutzt.

## Prüfung

Bilder: `production/qa/evidence/r12_5_mocap/` – `jog_side_mocap.png` / `walk_side_mocap.png` (Seitenansicht,
6 Phasen), `jog_side_before_r12_4.png` (vorher), `user_video_frame_before.png`, Spielerkamera `1_idle` … `4_jump`,
Web-Export in Chromium. Tests: 29 Suites, 437 Prüfungen, `ALL_TESTS_EXIT=0`.

## Offen

- Hände beim Joggen offen statt locker geschlossen.
- Nur die Spielfigur hat Mocap; NPCs gehen weiterhin mit der korrigierten UAL-Animation.
- Sprung weiterhin UAL.
- FPS auf dem Gerät nicht gemessen.

## Build

`build/stray_web_itch.zip`, SHA-256 `e1c5c11b1674f7ffa1ee018da4113d4e0245edfab410908d87d87763ccbada41`.
