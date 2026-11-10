# R12.4 – Spielfigur als Mensch (2026-11-10)

Branch `claude/jolly-allen-b3y08s`, Ausgangsstand `6fd689e` (R12.3). Auftrag: „mach den Hauptcharakter auch mit dieser
Anatomie“. Backup: Branch `backup/pre-r12_4-2026-11-10`.

## Änderungen

| Bereich | Änderung |
|---|---|
| Figur | Neuer Typ `player` in `npc_specs.json` (Look des R11-Prototyps: junger Mann, Jacke, Hemd, Jeans, Sneaker, kurze Haare), gebaut mit der R12.3-Pipeline (Rig an den Körper angepasst): `assets/characters/r12_npc/player.glb`, 18 974 Dreiecke, 1 Material, 1,83 m |
| Animationen | `bake_npc_anims.gd`: Clipliste pro Typ (`anims`); Spieler bekommt Idle, Walk, Jog_Fwd, Jump vorgebacken (Idle/Walk mit R12.2-Haltungskorrektur). Gemessene natürliche Geschwindigkeit je Clip als Meta `natural_speed` (Walk 0,91 m/s, Jog nach der Nachbesserung 3,31 m/s) → Abspieltempo passt zur Laufgeschwindigkeit |
| Spieler | `player.gd`: Variante `human` ist Standard (lädt über `StrayNpcHuman`, keine Laufzeit-Umrechnung mehr); `r10` (Puppe) bleibt im Pausenmenü umschaltbar. Alte Spielstände mit `r11` laden als `human`; Spielstände ohne Eintrag ebenfalls |
| Menü | „Figur: Mensch“ / „Figur: Puppe (R10)“ |
| Tests | `character_variant_test` auf das neue Verhalten umgestellt (9 Prüfungen), `npc_rig_fit_test` prüft auch den Spieler |
| Werkzeug | `tools/character/r12_player_shots.gd`: Spielerkamera bei Stehen/Gehen/Joggen/Sprung |

Der R11-Prototyp (`build_r11_human.py`, Laufzeit-Retarget) wird vom Spiel nicht mehr benutzt; `StrayHumanRig` bleibt als
Sampler für das Backen.

## Prüfung

Bilder: `production/qa/evidence/r12_4_player_human/`.
- Einzelbilder vorn/seitlich/hinten/45°/Gehen (`player_sheet.png`): menschliche Proportionen (Kopfgelenk bei 0,909 der Körperhöhe), natürliche Schultern.
- Im Spiel aus der Spielerkamera (`1_idle` … `4_jump`) und im Web-Export in Chromium (`web_chromium_nachtflug.png`).
- Tests: 29 Suites, 437 Prüfungen, `ALL_TESTS_EXIT=0`.

## Nachbesserung Joggen (Nutzer-Feedback: „das sieht nicht menschlich aus mit der Beugung und dem Rücken“)

Die einzige Laufanimation der CC0-Bibliothek (`Jog_Fwd`) ist ein stilisierter Sprint. Gemessen (`motion_metrics.gd`):

| | Quelle UAL | gebacken vorher | gebacken nachher | echter Jogger (Richtwert) |
|---|---|---|---|---|
| Rumpfneigung nach vorn | 25,4° | 30,9° | 8,6° | ~5–12° |
| Armschwung | 91,7° | 90,7° | 55,7° | moderat, Ellbogen ~90° |
| Becken auf/ab | 24 cm | 26 cm | 17 cm (inkl. seitlich) | ~8–10 cm vertikal |
| natürliche Geschwindigkeit | 5,64 m/s | 5,83 m/s | 3,31 m/s | – |

Neue Back-Optionen (`npc_specs.json` → `motion.Jog_Fwd`): `lean_back_deg` 26, `head_back_deg` −5,
`leg_swing_scale` 0,6 (Oberschenkel/Unterschenkel zum Clip-Mittel → kürzere Schritte), `flight_cm` 5 (der tiefste
Fuß schwebt höchstens 5 cm über dem Bodenniveau), `upperarm_to_idle` 0,65 (Oberarme hängen näher am Körper,
Ellbogen bleiben gebeugt). Bei Rennen mit 4,5 m/s ergibt das ~175 Schritte/min.
Bilder: `jog_ingame_before_after.png` (gleiche Stelle wie der Nutzer-Screenshot), `jog_side_after.png`.
Werkzeug: `tools/character/r12_clip_side.gd` (Seitenansicht eines Clips in Phasen).

## Offen

- FPS auf dem Gerät nicht gemessen. Die Figur hat ~19 000 Dreiecke statt der Mannequin-Geometrie, weiterhin 1 Draw Call.
- Jump ist ohne zusätzliche Haltungskorrektur gebacken (so wie die Quelle).
- Die meisten Passanten sind weiterhin R10-Mannequins.

## Build

`build/stray_web_itch.zip`, SHA-256 `e14eec6e2c7a3a78bcfccbc9730f0f51d8ee4fe8543880bd7a44085ce3f5b6ad`.
