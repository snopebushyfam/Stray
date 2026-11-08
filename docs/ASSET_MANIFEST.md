# STRAY — Asset-Manifest

**Stand:** 2026-11-08 (Audit durch Claude Code, Branch `claude/jolly-allen-b3y08s`).
Abschnitt 0 ist der **geprüfte Ist-Zustand**. Ab Abschnitt A folgt das ursprüngliche
Übergabe-Inventar aus dem Startpaket (unverändert, als Recherchegrundlage).

## 0. Geprüfter Ist-Zustand

### 0.1 Im Repository vorhanden und verwendet

| Asset | Pfad | Quelle / Lizenz | Status |
|---|---|---|---|
| LoD2-Gebäude Hohenzollernring (155 Gebäude, 6.029 Dreiecke, lokal) | `Content/Stray/Data/LoD2_P001_Hohenzollernring.obj` (+ `.mtl`, `.json` Georeferenz/Metadaten) | Geobasis NRW, Kachel `LoD2_32_355_5645_1_NW.gml`, dl-de/zero-2-0 | erzeugt + mit Python geprüft (Orientierung, Maßstab, Höhen); **in Unreal ungeprüft**; Git LFS |
| DGM1-Gelände P001 (2-m-Raster, 27.000 Dreiecke) | `Content/Stray/Data/DGM1_P001_Terrain.obj` | Geobasis NRW `dgm1_32_355_5645_1_nw_2022.tif`, dl-de/zero-2-0 | erzeugt + mit Python geprüft; **in Unreal ungeprüft**; Git LFS |
| 3dcityloader-Export „Friesenplatz Nord“ (DXF + Kartentextur) | `assets/geodata/3dcityloader_friesenplatz_nord/` | vom Projektinhaber, 3dcityloader.com; LoD2/DGM dl-de/zero-2-0, Textur ODbL | echt, Georeferenz gemessen (README dort); **nicht im Spiel**, liegt nördlich von P001; Git LFS |
| Fassaden- und Straßenoberflächen (Godot) | `assets/shaders/spatial_env_facade.gdshader`, `spatial_env_street.gdshader` | eigene Shader, keine Fremdtexturen | im Spiel geprüft (Screenshots) |
| Straßenmöbel P001 (Ampel, Bäume, Mülleimer, Radbügel, Eingänge, Kamera; geparkte Autos) | `data/p001/P001_Layout.json` → `furniture` | Positionen: OSM (ODbL); Autos prozedural; Geometrie: einfache Grundkörper | im Spiel geprüft; Autos/Figur sind Platzhalter-Formen |
| Spielfigur: Mannequin mit 43 Animationen (Idle, Walk, Jog, Sprint, Jump, Sitting, Dance, Driving, Talking, …) | `assets/characters/quaternius_ual/UAL1_Standard.glb` (+ `LICENSE_CC0.txt`) | Quaternius „Universal Animation Library [Standard]“, **CC0 1.0**, geladen 2026-11-08 von quaternius.itch.io | im Spiel geprüft (Idle/Walk, Screenshots + Lauf-Test); neutrale Figur, keine Kleidung/Gesicht; Git LFS |
| Schritte auf Beton (5 Varianten) | `assets/audio/footsteps_kenney/` (+ `LICENSE_CC0.txt`) | Kenney „Impact Sounds 1.0“, **CC0**, geladen 2026-11-08 von kenney.nl | im Spiel geprüft (Zähler pro Schritt), **nicht angehört** |
| Stadt-Atmo (30-s-Schleife), Clubbass „durch die Wand“ und Clubmusik drinnen (124 BPM) | `assets/audio/p001/*.wav` | **selbst synthetisiert** (`tools/audio/synth_p001.py`), keine Fremdrechte | gemessen (Spektrogramm `production/qa/evidence/audio/`), **nicht angehört**; Git LFS |
| Straßenlayout P001 | `Content/Stray/Data/P001_Layout.json` | abgeleitet aus LoD2 + OSM (ODbL, © OpenStreetMap-Mitwirkende); Annahmen in `provenance` | erzeugt, Unreal-Automation-Tests geschrieben, **nicht ausgeführt** |
| Datenvorschauen | `docs/prototype-001/*.png` | eigene matplotlib-Renderings | **kein Unreal-Bild**; Git LFS |
| Engine-Basisformen (Cube/Cylinder/Sphere, BasicShapeMaterial) | `/Engine/BasicShapes/` | Teil von Unreal Engine | wird zur Laufzeit referenziert |

### 0.2 Werden beim ersten Editorstart automatisch erzeugt (noch nicht im Repo)

| Asset | Erzeugt durch |
|---|---|
| `/Game/Stray/Materials/M_Stray_Surface`, `M_Stray_Emissive` | `Content/Python/stray_setup_p001.py` |
| `/Game/Stray/Maps/L_P001_Street` (leere Map + `StrayStreetBuilder`) | `Content/Python/stray_setup_p001.py` |

Nach dem ersten Start diese `.uasset`/`.umap` committen (LFS-Regeln sind gesetzt).

### 0.3 Nicht verfügbar (gesucht, nicht gefunden)

| Gesucht | Wo gesucht | Ergebnis |
|---|---|---|
| Eigene Köln-3D-Karte des Projektinhabers (die frühere) | Repo `Stray` (alle Branches), `game-studio-template`, `video-skills`, Upload-ZIP | **nicht vorhanden**; nachgereicht wurde ein neuer 3dcityloader-Export (siehe 0.1) |
| Altes UE-5.8.2-Projekt, Commits `6fd0a5c`/`e5f0b56`, `AStrayStreetBlockout` | dito | **nicht vorhanden** |
| Spielerfigur mit Rig/Animationen | dito | fehlt → Platzhalterkörper; Third-Person-Content-Pack per `Config/DefaultGame.ini` einhängbar |
| Texturen (Asphalt, Platten, Fassaden), Fahrzeuge, NPCs, Audio, Smartphone-UI | dito | fehlen (einfarbige Materialien) |

### 0.4 Rohdaten (nicht im Git, reproduzierbar)

| Datei | Größe | SHA-256 (Anfang) | Bezug |
|---|---|---|---|
| `LoD2_32_355_5645_1_NW.gml` | 69.278.147 B | `c59a948cecd5e8d1324f249f8a529c389e1b95c8ca5038c948ec5ba7ef5a675b` | https://www.opengeodata.nrw.de/produkte/geobasis/3dg/lod2_gml/lod2_gml/LoD2_32_355_5645_1_NW.gml |
| `dgm1_32_355_5645_1_nw_2022.tif` | 1.964.442 B | – | https://www.opengeodata.nrw.de/produkte/geobasis/hm/dgm1_tiff/dgm1_tiff/dgm1_32_355_5645_1_nw_2022.tif |
| OSM-Ausschnitt | ~1,8 MB | – | https://api.openstreetmap.org/api/0.6/map?bbox=6.9375,50.9375,6.9420,50.9412 |

Beide landen durch `tools/geodata/build_p001.py` in `tools/geodata/cache/` (gitignored).

### 0.5 Lizenzpflichten

* **OSM (ODbL 1.0):** Bei Veröffentlichung Attribution „© OpenStreetMap-Mitwirkende“ (Credits).
* **LoD2 (dl-de/zero-2-0):** keine Pflichten; Quellenangabe empfohlen.
* KIOSK und NACHTFLUG sind **fiktiv**; die Kiosk-Fassade liegt nahe einem real kartierten Kiosk,
  dessen Name/Marke nicht übernommen wurde.

---

## A. Bekannt aus früheren Gesprächen, aber nicht als Datei zugänglich
| Element | Stand | Aktion |
|---|---|---|
| Vom Nutzer früher besorgte echte Köln-3D-Map | Herkunft/Format/Dateipfad nicht nachweisbar, keine abrufbare Originaldatei | Originaldatei oder Herkunftslink vom Nutzer in erreichbaren Projektordner kopieren |
| Altes Unreal-5.8.2-Projekt | Früher lokaler Prototyp bekannt, derzeit nicht verfügbar | Lokalen Projektordner auf Windows-PC suchen |
| Frühe Git-Baseline | Commit-Kürzel `6fd0a5c`; laut früherer Sitzung 849 Dateien, 753 LFS-Assets | Lokale Git-Remotes/History prüfen, LFS verifizieren |
| `feature/prototype-001-street` | Commit-Kürzel `e5f0b56`; früherer C++-Blockout | Nur nach Verifikation aus lokalem Repository auslesen |
| `AStrayStreetBlockout` | Früherer Straßen-Actor: etwa 150 m, Gehwege, Gebäude, NACHTFLUG, KIOSK | Vor eventueller Wiederverwendung C++-Quellen und Unreal-Level prüfen |
| GitHub `snopebushyfam/Stray` | Zum Prüfzeitpunkt existent, **0 Repository-Size**, leer | Für einen sauberen Start nutzbar; **nicht** fälschlich als alte Unreal-Version behandeln |

## B. Verifizierte externe Datengrundlagen

### Geobasis NRW — LoD2-Gebäude
URL: https://www.opengeodata.nrw.de/produkte/geobasis/3dg/lod2_gml/lod2_gml/

- Amtliche CityGML-Gebäudegeometrie, EPSG:25832 / ETRS89 UTM Zone 32N
- Lizenz laut offizieller Quelle: Datenlizenz Deutschland — Zero — Version 2.0
- Zum Start relevante Kacheln (aus offiziellen Einträgen):
  - `LoD2_32_355_5645_1_NW.gml` — 66.1 MB — Friesenplatz
  - `LoD2_32_355_5644_1_NW.gml` — 73.0 MB — südliche Ringe / Rudolfplatz
  - `LoD2_32_356_5645_1_NW.gml` — 53.7 MB — Hauptbahnhof-Umfeld
- Diese Zuordnung beruht auf Koordinaten des Zielortes und 1-km-UTM-Kachelraster; endgültige Flächenabdeckung vor Produktion kontrollieren.
- Nur Geometrie mit typisierten Dächern, keine fertige fotorealistische Spielwelt.
- Ein kleines Testgebiet vor großen Downloads konvertieren.

NRW Datensatz/Lizenz: https://data.gov.de/suche/daten/3d-gebaudemodell-nw-lod28b9df
NRW Downloadportal: https://www.opengeodata.nrw.de/produkte/geobasis/3dg/lod2_gml/lod2_gml/

### Offizielle Kölner Visualisierung (nur Ansicht, kein behaupteter Asset-Download)
https://www.stadt-koeln.de/artikel/66735/index.html

### Straßen-/Wegedaten: OpenStreetMap
https://download.geofabrik.de/europe/germany/nordrhein-westfalen.html
- Für Köln Gebietsdaten räumlich zuschneiden (keinen kompletten NRW-Datensatz unbesehen importieren).
- Lizenz: ODbL. Lizenz-/Attributionspflichten für eine spätere Veröffentlichung gesondert prüfen.
- Der OSM-Datensatz besteht aus Geodaten, nicht aus fertig texturierten 3D-Unreal-Leveln.

### CityGML → Blender
https://github.com/virtualcitySYSTEMS/blender-citygml-importer-exporter
- Open-Source-Importer vorhanden; Kompatibilität mit installierter Blender-Version prüfen.
- Nur kleine Beispielkachel importieren, Georeferenz/Einheiten erhalten und Material-/Collider-Pipeline dokumentieren.

### Unreal Engine Georeferencing
https://dev.epicgames.com/documentation/unreal-engine/georeferencing-a-level-in-unreal-engine

## C. Assets für den fertigen Prototyp, derzeit NICHT verifiziert
- Spielerfigur/Rig/Animationen
- Asphalt/Platten/Fassaden/Schilder/Neon-Texturen
- Verkehrsfahrzeuge, Straßenmöbel, Straßenmarkierungen
- NPC-Meshes, Animationen und Verhaltensbibliothek
- Innenräume / Club-Audio / Umgebungsgeräusche
- Smartphone UI / Icons
Jedes Asset mit Quelle, Nutzungsrecht, Version, Pfad und Importstatus im echten Projekt manifestieren.

## D. Kritische technische Regeln
- `.umap`/`.uasset` nicht als Textdateien vortäuschen.
- Git-LFS-Pointer != heruntergeladene Binärdateien.
- Massenhaft CityGML nicht ungeprüft ins normale Git-Repository laden.
- Unreal-Editor-Start, PIE und visueller Test müssen tatsächlich durchgeführt sein, ehe „spielbar“ oder „fertig“ behauptet wird.
