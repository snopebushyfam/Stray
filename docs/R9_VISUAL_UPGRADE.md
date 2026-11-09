# R9 – Visual Upgrade: Hohenzollernring bei Nacht (2026-11-09)

Branch `claude/jolly-allen-b3y08s`, Ausgangsstand `5ca8f14`. Engine unverändert Godot 4.7.2, Compatibility-
Renderer (WebGL2). Keine neuen Spielsysteme, keine neuen Fremd-Assets.

## 1. Vorgehen

Vergleichsaufnahmen mit einem eigenen Modus `-- --r9shots` (`main.gd: _run_compare_shots`): gleiche feste
Kameras, gleiche Spielzeit (Sa 23:10/23:11), gleiche Wartezeit nach dem Start, Nacht und Tag. Die Mannequins und
der Verkehr bewegen sich, daher stehen Figuren nicht exakt gleich. Gerendert mit Godot unter Xvfb + Mesa llvmpipe.

| Perspektive | Kamera |
|---|---|
| 1 Spieler-Spawn | Spielerkamera am Spawn (Westbürgersteig, Blick nach Norden) |
| 2 NACHTFLUG | Clubbürgersteig 13 m südlich, 6,5 m vor der Fassade, Blick zur Tür |
| 3 KIOSK + Gegenseite | Ostbürgersteig 14 m südlich des KIOSK, Blick nordwestlich über den Ring |

## 2. Bestandsaufnahme – größte Schwächen (aus den Vorher-Bildern)

1. **Fassaden:** Alle LoD2-Gebäude hatten dasselbe Putzgrau und dasselbe Fensterraster, keine Rahmen, keine
   Unterschiede. Die Erdgeschosse waren leere Putzwände. Nachts waren die Fassaden bis auf Fenster schwarz.
2. **Schaufenster:** als flache cremefarbene Leuchttafeln, auch am Tag (bereits im QA-Lauf gedämpft, blieb flach).
3. **KIOSK:** Kühlschrank und Fenster als weiß überstrahlte Flächen.
4. **Asphalt:** fast schwarz (Albedo 0,035), ohne Struktur.
5. **Autos:** Quader, im Verkehr alle in der Farbe des ersten Autos (Material-Cache-Fehler `_mat("paint")`).
6. **Nachthimmel/Ferne:** bräunlich-schwarz, keine Stadtglocke.

## 3. Änderungen

| Bereich | Änderung | Dateien |
|---|---|---|
| Fassaden | Neuer Shader v2: je Gebäude (stabil aus der LoD2-Gebäude-ID gehasht, per Vertexfarbe) Material (7 Putzfarben, Sandstein-Quader, Klinker, moderne Platten), Fensterachsen, -größe, Geschosshöhe; Fensterrahmen (weiß/braun/anthrazit) mit Sprosse, Fensterbank, Laibungsschatten, Regenspuren, Gesimsbänder, Traufband; Glas spiegelt Himmelsfarbe. Erdgeschoss: dunkler Sockel, Ladenachsen mit Schaufenster (nachts warme Innenbeleuchtung mit Regalzone), geschlossenen Läden mit Rollladen, Schilderband mit farbigem Leuchtschriftzug. Nachts leichtes Streulicht der Straße auf die unteren Geschosse. Abwechslungsreichere beleuchtete Fenster (warm/neutral/TV-blau, Helligkeit, Jalousien, Anteil je Gebäude). | `assets/shaders/spatial_env_facade.gdshader`, `obj_mesh.gd` (`building_params`), Aufruf in `street_builder.gd` und `area_builder.gd` |
| Schaufenster | Leuchttafeln entfernt (Schaufenster kommen aus dem Shader); Licht auf den Gehweg bleibt | `street_builder.gd`, `godot_render.json` (`shopfront.panels=false`) |
| Straße | Asphalt heller (0,062) mit Ausbesserungsflicken und feinen Rissen; Gehwegplatten mit Kaugummiflecken und verwitterten Platten; Markierungen etwas gebrochen weiß | `spatial_env_street.gdshader`, `godot_render.json` |
| Licht | Laternen wärmer; additive Lichthöfe (Billboards) an Laternenköpfen, NACHTFLUG-Schriftzug und KIOSK-Schild, nur nachts; Nachthimmel dunkelblau, Dunst mit warmer Stadtglocke, etwas mehr Umgebungslicht | `street_builder.gd (_glow)`, `godot_render.json` |
| KIOSK | Kühlschrank als Gehäuse mit gedämpft leuchtender Glastür statt weißem Block; Fenster und Schild gedimmt | `street_builder.gd`, `godot_render.json` |
| Fahrzeuge | Gemeinsames Automodell (Motorhaube, Kofferraum, Glaskabine, Dach, B-Säule, Stoßfänger, Schweller, Spiegel, Scheinwerfer/Rückleuchten, Kennzeichenfeld, Felgen) für geparkte Autos und Verkehr; Verkehr hat wieder unterschiedliche Lackfarben; Streifenwagen angepasst | `src/p001/car_model.gd` (neu), `street_builder.gd`, `traffic.gd` |
| Messung | FPS-Ausgabe alle 5 s (`STRAY_DIAG fps=`), Vergleichsmodus `--r9shots` | `main.gd` |

Die Fassaden sind **generisch**: Material und Fensterbild sind pro Gebäude zufällig, aber stabil gewählt und
geben **nicht** die echte Fassade des jeweiligen Gebäudes wieder. Echt sind weiterhin Lage, Grundriss und Höhe
(LoD2).

## 4. Im Lauf gefundene und behobene Fehler

| Fehler | Ursache | Behebung |
|---|---|---|
| Körniges Punktmuster auf Schaufenstern, Rollläden und Schilderbändern | Die Vertexfarbe mit den Gebäudewerten kommt pro Pixel mit ~1e-7 Rundungsrauschen an; die `sin`-Hashfunktion verstärkt das, so dass einzelne Pixel andere Ladenachsen „würfelten“. Gefunden durch Ausschluss: Rillenmuster entfernt → blieb; Schattenbias → blieb; Debug-Ausgabe der Gebäudewerte → konstant; Spiegelterm entfernt → blieb. | Gebäudewerte vor dem Hashen auf das 8-Bit-Raster gerundet, Hash-Eingaben ganzzahlig |
| Mögliches Z-Fighting an deckungsgleichen Wänden benachbarter LoD2-Gebäude (wird mit unterschiedlichen Materialien sichtbar) | gemeinsame Wandflächen | Wände je Gebäude 0,2–2 cm entlang der Normalen versetzt (vorbeugend; nicht der Hauptgrund des Punktmusters) |
| Glanz-Funkeln auf sehr glattem Glas | Rauheit 0,06–0,08 im Compatibility-Renderer | Glas-Rauheit ≥ 0,3, Spiegelwirkung über die Himmelsfarbe |
| Verkehr: alle Autos gleich lackiert | Material-Cache mit festem Schlüssel `paint` | gemeinsames Automodell cached nach Farbe |

## 5. Vorher/Nachher (gleiche Kamera, Zeit, Wartezeit)

Alle Bilder: `production/qa/evidence/r9_visual/` – `before_*.png`, `after_*.png`, nebeneinander `compare_*.png`.

| Szene | Nacht | Tag |
|---|---|---|
| 1 Spawn | `compare_1_spawn_night.png` | `compare_1_spawn_day.png` |
| 2 NACHTFLUG | `compare_2_nachtflug_night.png` | `compare_2_nachtflug_day.png` |
| 3 KIOSK + Gegenseite | `compare_3_kiosk_opposite_night.png` | `compare_3_kiosk_opposite_day.png` |

Bewertung (aus den Bildern):

- **Fassaden/Gebäude:** deutlich besser. Unterschiedliche Materialien und Farben, Fenster mit Rahmen und Sprossen,
  Erdgeschosse lesen sich als Ladenzeile (Schaufenster, Rollläden, Schilderbänder). Die Wiederholung ist
  innerhalb eines Gebäudes weiterhin regelmäßig – wie bei Nachkriegsbauten üblich, aber sichtbar prozedural.
- **Straßenmaterialien:** Asphalt grau statt schwarz, Flicken und Risse erkennbar, Gehweg lebendiger. Markierungen
  bleiben einfache Streifen.
- **Nachtbeleuchtung:** Fassaden nicht mehr schwarz, warme Ladenzonen, vielfältige Fensterlichter, Lichthöfe an
  Laternen. Keine überbelichteten weißen Flächen mehr in den drei Szenen.
- **NACHTFLUG/KIOSK:** NACHTFLUG-Schriftzug lesbar wie vorher, mit leichtem Lichthof; KIOSK-Schild lesbar, der
  weiße Kühlschrankblock ist weg.
- **Figuren/Fahrzeuge:** Autos mit erkennbarer Silhouette (Haube, Kabine, Kofferraum, Lichter) statt Quadern.
  Figuren sind weiterhin neutrale Mannequins (keine passenden, rechtlich klaren Figuren-Assets im Projekt).
- **Grafikfehler:** keine neuen gesehen nach Behebung des Punktmusters (39 Screenshots des kompletten Durchlaufs
  geprüft: Ring, KIOSK, Club, Wohnung, Handy, Polizei, U-Bahn, Hbf, Prolog).

## 6. Tests und Messungen

| Prüfung | Ergebnis |
|---|---|
| Regressionstests (22 Godot-Suites, 370 Einzelprüfungen) + Python-Datentests | alle grün (`ALL_TESTS_EXIT=0`) |
| Kompletter Screenshot-Durchlauf (`--autoshots`) | 39 Bilder, angesehen, Prolog/U-Bahn/Club/Wohnung/Polizei funktionieren |
| Web-Export in Chromium (WebGL2 über SwiftShader) | lädt, Prolog startet, neuer Shader rendert (`web_chromium_r9_hbf.png`) |
| Bildrate Web, Chromium **mit Software-Grafik** (rAF-Zählung über 15 s am Hbf, je 2 Läufe) | vorher 0,96 / 0,91 fps, nachher 0,89 / 0,88 fps (≈ −5 %) |
| Bildrate Godot-Fenster, llvmpipe (Spawn) | vorher 1,8–1,9 fps, nachher 1,6–1,8 fps |

**Die Bildraten sind keine Tablet-Messung.** Beide Umgebungen rendern komplett in Software; sie zeigen nur, dass
der neue Stand nicht drastisch teurer ist. Auf dem echten Tablet **ungetestet**.

## 7. Offene Probleme

| Prio | Problem |
|---|---|
| 1 | Bildrate auf dem echten Tablet ungemessen (der Fassaden-Shader ist pro Pixel aufwendiger als vorher) – Spiel zeigt jetzt alle 5 s `STRAY_DIAG fps=` in der Browser-Konsole |
| 2 | Figuren sind graue/einfarbige Mannequins – sichtbarste verbleibende Schwäche; braucht CC0-Figuren mit Kleidung (bewusst nicht ohne Freigabe heruntergeladen) |
| 2 | Dächer und Hbf-Halle/Dom ohne eigenes Material (Dom einfarbiger Sandstein, Halle wie Bürogebäude) |
| 3 | Fensterraster pro Gebäude streng regelmäßig; keine Balkone, Erker, Vordächer (LoD2 hat keine) |
| 3 | Straßenmarkierungen ohne Abnutzung, keine Zebrastreifen-/Haltelinien-Details |
| 3 | Laternen ohne Schatten (Compatibility-Artefakte, siehe TECHNICAL_PLAN) |
| 4 | Ladenzonen liegen auch hinter Einfahrten/Toren, wo es real keine Läden gibt |

## 8. Build

`build/stray_web_itch.zip`, SHA-256 `9d90f5913b2d7756480feba570b4a1a58fce184423da96e85dd72b6ad75f6cf6`
(`tools/release/package_itch.sh`). Upload auf die itch.io-Seite durch den Konto-Inhaber (`docs/RELEASE_ITCH.md`).
