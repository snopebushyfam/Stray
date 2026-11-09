# R10 – Character Upgrade (2026-11-09)

Ausgangsstand `e131755`. Ziel: graue Mannequins durch bekleidete Menschen ersetzen, Leistung halten,
Polizei-Anzeige lesbar machen.

## 1. Bestand und Assetsuche

| Was | Befund |
|---|---|
| Vorhandene Figur | Quaternius **Universal Animation Library** (`assets/characters/quaternius_ual/UAL1_Standard.glb`, **CC0 1.0**, LICENSE im Ordner): Mannequin, 65 Knochen, 43 Animationen (Idle, Walk, Jog_Fwd, Sprint, Dance, Idle_Talking, Interact …), 2 Flächen (Körper + Gelenke), 8.546 Vertices |
| Nutzung | Spieler (`player.gd`), 15 Passant:innen + 5 in der Schlange (`pedestrians.gd`), Club: DJ, ~10 Tanzende, Barkeeper, Lea (`club_interior.gd`), Türsteher (`interactions.gd`) – alle mit derselben Szene, nur umgefärbt |
| Suche nach CC0-Kleidung für dieses Rig | [Universal Base Characters](https://quaternius.itch.io/universal-base-characters) (CC0, passendes Rig): nur Körper in Unterwäsche/minimaler Kleidung, kostenlos nur 2 Basismodelle. [Modular Character Outfits – Fantasy](https://quaternius.com/packs/modularcharacteroutfitsfantasy.html) (CC0, passend): mittelalterliche Kleidung. **Keine moderne, lizenzsichere Alltagskleidung für dieses Rig gefunden.** Andere Pakete hätten ein fremdes Rig (Retargeting-Risiko) – nicht importiert. |

**Entscheidung (wie im Auftrag vorgesehen):** eigene, kleine Lösung auf der vorhandenen CC0-Figur. Keine neuen
Fremd-Assets, Rig und alle Animationen bleiben unverändert (kein Retargeting nötig).

## 2. Umsetzung

| Datei | Inhalt |
|---|---|
| `src/p001/character_look.gd` (neu) | Baut einmal ein **gemeinsames** Mesh: beide Mannequin-Flächen zu **einer** zusammengefasst (1 statt 2 Draw Calls pro Figur), automatische LODs (`ImporterMesh.generate_lods`), in der Vertexfarbe die Ruhepose-Position. Liest Landmarken aus dem Skelett (Schulter, Ellbogen, Handgelenk, Hals, Becken, Knöchel, Kopf). Ein `ShaderMaterial` pro Look, geteilt. |
| `assets/shaders/spatial_char_clothing.gdshader` (neu) | Kleidung über Zonen in der Ruhepose (gerade, saubere Grenzen): Haare (oder Glatze), Gesicht mit Augen/Brauen, Hals/Kragen, Oberteil (Jacke mit Reißverschluss oder Hoodie mit Tasche, Saum, Bündchen), T-Shirt-Ärmel mit nackten Unterarmen, Hose mit Köper-Struktur, Schuhe mit heller Sohle, Hände. Stoffstruktur per Rauschen, keine Texturen. |
| `data/p001/character_looks.json` (neu) | 18 Looks in Gruppen: Spieler (olivgrüner Hoodie, dunkle Jeans, weiße Sneaker), Straße (8: Navy-Jacke, grauer Hoodie, beiger Mantel, Lederjacke, Jeansjacke, rote Steppjacke, Parka, T-Shirt), Schlange (6), Club (7), Türsteher (schwarzer Blouson, Glatze), Barkeeper, Lea. Verschiedene Hauttöne und Haarfarben. |
| `player.gd`, `pedestrians.gd`, `club_interior.gd`, `interactions.gd` | statt Umfärben `StrayCharacterLook.apply(model, look)`; Spawn, Kollision, Animation unverändert |
| `ui.gd` | Polizei-Anzeige als Text: `Polizei 3/5 - beobachtet` (Stufen: unauffällig, aufmerksam, beobachtet, gesucht, Fahndung) statt der Zeichen ●/○ |

Was **nicht** geht (ehrlich): Die Körperform bleibt die des athletischen Mannequins (breite Schultern, Segmentlinien
schimmern durch). Ein „Aufpolstern“ der Kleidung entlang der Normalen öffnete Risse zwischen den Segmenten und wurde
verworfen. Keine Frisuren-Geometrie, keine Kapuze als Form, keine echten Gesichter. Für deutlich natürlichere Menschen
braucht es ein echtes Kleidungs-Modell (z. B. Quaternius Source-Paket der Base Characters + eigene Kleidung in
Blender) – das ist ein eigener Schritt.

## 3. Prüfung im gerenderten Spiel

Vorher/Nachher aus genau denselben Aufnahmen (`--r9shots`, `--autoshots`; Vorher = Stand `e131755`):
`production/qa/evidence/r10_characters/R10_before_after.png` – Spawn am Ring, Schlange/Türsteher, Club-Tanzfläche,
Lea + Barkeeper, Prolog am Hbf, Polizeikontrolle mit neuer Anzeige. Dazu `R10_looks_lineup_walk.png` (alle 18 Looks
in der Laufanimation), `R10_player_closeup.png`, `R10_web_touch.png` (Chromium).

Animationen geprüft: Gehen/Rennen/Stehen (Spieler, Passanten), Idle_Talking (Schlange, Lea), Dance (Club), Idle
(Barkeeper, Türsteher) – alle laufen mit den neuen Looks (Screenshots aus dem laufenden Spiel). „Interact“ wird im Spiel
derzeit nicht abgespielt; das Rig ist unverändert, die Animation daher weiter verfügbar.

## 4. Render-Kosten (tools/perf/render_probe.gd, gleiche Messpunkte)

| Ort | Draw Calls vorher → nachher | Dreiecke vorher → nachher |
|---|---|---|
| Ring (Spawn) | 539 → **514** | 187 k → 164 k |
| NACHTFLUG | 300 → **279** | 149 k → 140 k |
| KIOSK | 326 → **313** | 148 k → 134 k |
| Club innen | 105 → **88** | 122 k → 113 k |
| U-Bahn | 63 → 62 | 8,9 k → 14,9 k (nur der Spieler, nah; volle LOD-Stufe des zusammengefassten Meshes) |
| Hbf | 149 → 147 | 49 k → 48 k |

Ein Mesh und 18 Materialien für alle Figuren; Speicher: ein zusätzliches Mesh (8.546 Vertices) statt pro Figur.
**Keine Aussage über Tablet-FPS** – die Werte oben sind Render-Last, gemessen in der Cloud (Software-Rendering).
Da Draw Calls und Dreiecke an allen belebten Orten leicht sinken, ist kein Leistungsverlust zu erwarten; belegt wird
das erst mit der FPS-Anzeige auf dem Tablet.

## 5. Tests

| Prüfung | Ergebnis |
|---|---|
| Alle Regressionstests | **26 Suites, 409 Prüfungen, grün**; Python OK |
| Neu in `ui_state_test` | Polizei-Anzeige als lesbarer Text ohne ●/○ |
| Web-Build Chromium (Touch) | Prolog startet, Spielfigur bekleidet, FPS-Knopf funktioniert |

## 6. Lizenzen
- Figur und Animationen: Quaternius Universal Animation Library, **CC0 1.0** (unverändert, nur zur Laufzeit eingefärbt).
- Kleidung/Looks: eigener Shader und eigene Daten (keine Fremdrechte).

## 7. Build
`build/stray_web_itch.zip`, SHA-256 `51760b4b439bc7a6da2bec53049bce2e367b232386af3920f0528dab0bfad73f`.
