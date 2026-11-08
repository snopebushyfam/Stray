# STRAY — Technischer Plan

**Stand:** 2026-11-08 · **Aktive Engine:** Godot 4.7.2 (GDScript, Compatibility-Renderer) · **Archiv:** Unreal 5.8 C++ unter `Unreal/` · **Branch:** `claude/jolly-allen-b3y08s`

> **Status Prototype 001 (Godot): GESPIELT UND GEPRÜFT in der Cloud-Umgebung** — Godot 4.7.2 lief
> unter Xvfb mit Software-OpenGL (llvmpipe) und als Web-Export in Chromium (WebGL 2). Belege:
> `production/qa/evidence/godot/` (12 Screenshots, Log, Testlog).
> Nicht geprüft: echte Tablet-/Handy-Hardware, Touch-Bedienung mit dem Finger, Performance auf GPU.
>
> **Unreal-Version (`Unreal/`): weiterhin nie kompiliert oder gestartet** (kein Unreal in der Cloud).

## 0. Godot-Version (aktiv)

| | |
|---|---|
| Projekt | `project.godot` (Repo-Wurzel), Hauptszene `src/p001/main.tscn` |
| Code | `src/p001/street_layout.gd` (Daten + Mathe), `obj_mesh.gd` (OBJ-Leser), `street_builder.gd` (Straße, Gelände, Gebäude, Licht), `player.gd` (Third-Person, Maus/Tastatur/Gamepad/Touch), `main.gd` (Spawn, HUD, VirtualJoystick, Auto-Screenshots) |
| Daten | `data/p001/` — gemeinsam mit Unreal: `P001_Layout.json`, LoD2-/DGM1-OBJ; Godot-spezifisch: `godot_render.json` (Licht/Farben), `player_config.json` (Tempo, Kamera, Tastenbelegung) |
| Koordinaten | Godot X = Ost, Y = oben, Z = −Nord (reine Rotation, keine Spiegelung); Godot-Frontfläche = im Uhrzeigersinn |
| Licht | 45 dynamische Lichter (12 Straßenlampen, 29 Schaufenster, KIOSK, NACHTFLUG, Mond). Limit Compatibility: 16 pro Objekt / 64 gesamt → Straße in 12-m-Stücken, ein Netz pro Gebäude |
| Steuerung | WASD/Pfeile + Maus, Gamepad, Touch: VirtualJoystick links (Godot 4.7), Wischen rechts = Kamera, Buttons Springen + Tag/Nacht. N = Tag/Nacht |

**Ausführen / prüfen**

```bash
godot --path .                                             # spielen (Editor: godot -e --path .)
godot --path . -- --autoshots                              # 11 Beweis-Screenshots -> production/qa/evidence/godot/
GODOT=godot tests/run_tests.sh                             # Unit- + Lauf-Tests + Python-Datentests
godot --headless --path . --export-release "Web" build/web/index.html   # Web-Build (WebGL 2)
```

**Testergebnis 2026-11-08 (Stand Ausbau 1):** `street_layout_test` 15/15, `walk_test` 11/11 (zusätzlich: freie Bordsteinstelle gefunden, geparktes Auto blockiert); erste Fassung `walk_test` 9/9 (Spawn auf Gehweg,
4,8 m in 3 s gegangen, Bordstein hinab, Fassade blockiert, Endwand hält, nicht durch die Welt
gefallen), Python 12/12. Gegenprobe: ohne Straßen-/Gebäudekollision schlagen 3 Lauf-Tests fehl.
Gefundene und behobene Fehler beim echten Lauf: Schaufenster flimmerten (Z-Fighting), Lampen zu
schwach, Schattenkeile an Lampen (Spot-Schatten im Compatibility-Renderer → Lampenschatten aus).

**Ausbau 1 „glaubwürdige Straße“ (2026-11-08, gespielt + getestet):**

| Element | Quelle | Umsetzung |
|---|---|---|
| Fassaden mit Stockwerken, Fensterrahmen, Glas, nachts zufällig erleuchtete Fenster (stabil pro Fenster) | prozedural | `assets/shaders/spatial_env_facade.gdshader` (Weltkoordinaten, keine UVs nötig) |
| Asphalt (Körnung, Flecken), Betonplatten 40 × 40 cm mit Fugen, Bordstein-/Mittelstreifensteine | prozedural | `assets/shaders/spatial_env_street.gdshader`, an der Straßenachse ausgerichtet |
| Fußgängerampel + Furt + Haltlinien | **OSM** `highway=traffic_signals` (s = −41,4 m) | Masten an beiden Bordsteinen + Mittelstreifen, Fahrzeug grün / Fußgänger rot |
| 2 Bäume, 2 Mülleimer, 2 Fahrradständer (je 5 Bügel), 1 Überwachungskamera | **OSM**-Knoten | mit Kollision (Stamm, Mülleimer, Bügel) |
| Hauseingänge (5 von 23 frei platzierbar, Rest unter Schaufenstern) | **OSM** `entrance=*`, auf die echte Fassade eingerastet | Tür, Rahmen, Leuchte |
| 25 geparkte Autos | **prozedural** (Seed 5150), Abstand zu Ampel, Fahrradständern und Kamerapunkten | Karosserie, Fenster, Räder, Kollisionsbox |

Beim Lauf gefunden und behoben: Putz wirkte blockig (Schachbrett) → weiches Rauschen + Schmutzkante
unten; ein Auto parkte im KIOSK-Kamerapunkt → Kamerapunkte bleiben frei; Metallic-Lack wirkte im
Compatibility-Renderer schwarz → Metallic 0,1. Der Lauf-Test fand zu Recht, dass ein geparktes Auto
den Weg vom Gehweg versperrt; er sucht nun eine freie Stelle und prüft das Blockieren eigens.
**Spielfigur (2026-11-08):** CC0-Mannequin von Quaternius (1,83 m, Metermaß, 43 Animationen).
Zustände Idle / Walk / Jog / Jump nach Geschwindigkeit; die Animationsgeschwindigkeit wird an das
echte Tempo angepasst (natürliche Tempi aus der Root-Motion gemessen: Walk 0,97 m/s, Jog 5,36 m/s),
Gehtempo jetzt 1,35 m/s. `walk_test` prüft Idle → Walk → Idle (14/14).
**Ton (2026-11-08):** Stadt-Atmo überall, Clubbass als 3D-Quelle vor der NACHTFLUG-Tür (wird mit
Abstand leiser), Schritte pro Schrittlänge (0,65 m gehen / 1,25 m rennen) mit leichter Tonhöhen-
Variation. Konfiguration `data/p001/audio_config.json`. Geprüft: Spieler laufen, Schrittzahl passt zur
Strecke (`walk_test` 17/17), Spektrum gemessen. **Nicht geprüft: wie es klingt** (in der Cloud
kann niemand zuhören). Im Browser startet Ton erst nach der ersten Berührung/Taste (Browser-Regel).
Schritt 1 ist damit abgeschlossen bis auf: Kleidung/Gesicht der Figur (das Rig ist für weitere UAL-kompatible
Figuren nutzbar). Die Unreal-Fassung kennt die
Möbel und Shader noch nicht.

**Abweichung vom Template:** gdUnit4 ist (noch) nicht installiert; die Tests sind schlichte
`SceneTree`-Skripte mit PASS/FAIL-Ausgabe und Exit-Code (`tests/run_tests.sh`).

---

## 1. Bestandsaufnahme (Audit, 2026-11-08)

| Frage | Befund |
|---|---|
| Repository / Branch / Commit | `snopebushyfam/Stray`, `main` = `71014bb` „Initial commit“ (nur das Claude-Code-Game-Studios-Template, kein Spiel). Arbeitsbranch `claude/jolly-allen-b3y08s`. |
| Altes Unreal-Projekt (UE 5.8.2) | **Nicht vorhanden.** Kein `.uproject`, `.umap`, `.uasset` im Repo, in `game-studio-template`, `video-skills` oder im Upload-ZIP. Commits `6fd0a5c` / `e5f0b56` und `AStrayStreetBlockout` existieren in keinem erreichbaren Repository. |
| Git-LFS | Vorher keine LFS-Dateien. LFS 3.4.1 installiert; `.gitattributes` jetzt mit LFS-Regeln für `uasset/umap/obj/fbx/blend/glb/gml/png/...`. |
| Eigene Köln-3D-Karte | **Nicht auffindbar** (weder Repo noch ZIP). Nicht verwendet, nicht behauptet. |
| Amtliche Daten | **Erreichbar und verwendet:** Geobasis NRW LoD2 `LoD2_32_355_5645_1_NW.gml` (69,3 MB, Last-Modified 2026-05-26) und DGM1 `dgm1_32_355_5645_1_nw_2022.tif` (1 m Gelände). OSM-API 0.6 erreichbar (Overpass nicht). |
| 3dcityloader-Export (vom Inhaber nachgereicht) | Echt, exakt georeferenziert (siehe `assets/geodata/3dcityloader_friesenplatz_nord/README.md`), liegt aber 90–290 m **nördlich** von P001 — gesichert, noch nicht verwendet. |
| Unreal ausführbar? | **Nein.** Kein `UnrealEditor`, keine Engine-Installation, keine GPU. Blender ebenfalls nicht installiert. **Godot 4.7.2 dagegen ja** (Download von GitHub, Xvfb + Mesa llvmpipe). |
| Ausführbar war | Python 3 (+ numpy, pyproj, mapbox-earcut, matplotlib), git, git-lfs, clang (ohne UE-Header). |

## 2. Architektur (Unreal-Version, archiviert unter `Unreal/`)

```
Stray.uproject                     UE 5.8, Plugins: EnhancedInput, ProceduralMeshComponent, PythonScriptPlugin, EditorScriptingUtilities
Config/Default{Engine,Game,Input}.ini
Source/Stray/
  Public|Private/StrayStreetLayout.*   reine Daten + Mathe (kein UObject): JSON-Parser, Koordinaten, Spawn
  Public|Private/StrayObjMesh.*        minimaler OBJ-Leser, EN(U)-Meter -> Unreal-cm, Normalen
  Public|Private/StrayStreetBuilder.*  AActor: baut die komplette Straße + Licht aus den Daten
  Public|Private/StrayCharacter.*      Third-Person-Figur, Enhanced Input komplett in C++
  Public|Private/StrayGameMode.*       sichert Street-Actor, Spawn aus Layout, -StrayAutoShots
  Private/Tests/StrayP001Tests.cpp     Automation-Tests "Stray.P001.*" (Daten/Mathe)
Content/Stray/Data/                  P001_Layout.json, LoD2_P001_Hohenzollernring.obj/.mtl/.json (LFS)
Content/Python/stray_setup_p001.py   erzeugt beim ersten Editorstart Materialien + Map
tools/geodata/                       Pipeline LoD2 + OSM -> Content/Stray/Data (+ Tests)
docs/prototype-001/*.png             Datenvorschauen (matplotlib, KEIN Unreal-Render)
```

**Warum so:** Ohne laufenden Editor können keine `.uasset`/`.umap` erzeugt werden — und sie
werden nicht als Text vorgetäuscht. Deshalb ist alles, was die Szene ausmacht, **Code + Daten**:

* Die Gebäude werden zur Laufzeit (und im Editor via `OnConstruction`) aus der OBJ-Datei als
  `UProceduralMeshComponent` mit Complex-as-Simple-Kollision erzeugt. Kein manueller Import nötig.
* Input-Actions und Mapping-Context entstehen zur Laufzeit in C++ — keine Input-Assets nötig.
* Die einzigen Editor-Assets (2 Materialien + Map) erzeugt `stray_setup_p001.py` automatisch beim
  ersten Editorstart (`PythonScriptPluginSettings.StartupScripts`). Fehlen sie, fällt der Code auf
  `/Engine/BasicShapes/BasicShapeMaterial` zurück und loggt das; fehlt die Map, spawnt der
  GameMode den Street-Actor in jeder Map selbst.
* `P001_Layout.json` ist die **einzige Quelle** für Maße, Positionen und Lichtwerte (datengetrieben).

## 3. Koordinaten & Georeferenz

| Rahmen | Definition |
|---|---|
| Quelle | EPSG:25832 (ETRS89/UTM 32N), Höhe DHHN2016 |
| Lokal (Daten) | Meter, X = Ost, Y = Nord, Z = oben. Ursprung **E 355260, N 5645100, H 49,25 m** |
| Unreal | cm, `UE.X = Ost·100`, `UE.Y = −Nord·100`, `UE.Z = oben·100` (nicht gespiegelt von oben) |
| Straßenrahmen | `s` entlang der Achse (Peilung 11,075° Ost von Nord, Richtung Friesenplatz), `v` quer (+ = Ostseite) |

Der lokale Ursprung hält Vertexwerte klein (float32-Präzision). Der Ursprung liegt auf dem
Hohenzollernring ca. 120 m südlich der Haltestelle Friesenplatz; die Höhe ist der Median der
Gebäudesockel entlang des Abschnitts (Spannweite −1,04 … +0,10 m → kein Gebäude schwebt über
dem 15-cm-Gehweg). Für spätere Erweiterungen: UE-Georeferencing-Plugin mit diesem Ursprung.

## 4. Prototype 001 „The Street“ — was gebaut wird

| Element | Quelle | Umsetzung |
|---|---|---|
| 155 Gebäude, ~6.000 Dreiecke | **gemessen** (LoD2) | ProceduralMesh, Kollision, Wand/Dach/Boden-Material |
| Gelände 200 × 270 m, 2-m-Raster (27.000 Dreiecke) | **gemessen** (DGM1) | ProceduralMesh mit Kollision; im Straßenkorridor 25 cm unter die Straße abgesenkt |
| Längsprofil (Gefälle ~0,5 m nach Norden), Bordsteinhöhen 10–21 cm, Gehweg-Quergefälle | **gemessen** (DGM1), alle 3 m, 15 m geglättet | Straßenoberfläche als ProceduralMesh: Fahrbahn, Mittelstreifen, Bordsteine, Gehwege, Schürzen |
| Straßenachse, 2×2 Spuren | **gemessen** (OSM `highway=primary` „Hohenzollernring“) | Fahrbahn, Mittelstreifen, Markierungen |
| Fassadenfluchten | **gemessen** (LoD2, Strahltest alle 3 m) | West −16,7 m, Ost +19,2 m (Median) |
| Spurbreiten, Parkstreifen | **angenommen** | 3,4 m / 2,0 m; Bordsteinhöhe auf 10–25 cm begrenzt |
| 12 Straßenlampen (8 m, 1.800 cd, 3.400 K, Schatten) | **angenommen** (OSM kartiert kaum Lampen) | SpotLight, beidseitig versetzt, 25 m |
| 29 Schaufenster, 142 erleuchtete Fenster | **prozedural**, deterministisch (Seed 1408) | RectLight + Emissive-Panel / ISM |
| KIOSK (Ostseite, s = 48 m) | Fassade real; Name **fiktiv** | Lichtkasten, Schaufenster, Tür, Markise, Kühlschrank, 2 Lichter |
| NACHTFLUG (Westseite, s = 64 m) | Fassade real; Club **fiktiv** | Portal, Lichtleisten, Vordach, Schriftzug, Absperrkordel, 2 Lichter |
| Spawn | Westgehweg, s = 22 m, Blick Richtung Friesenplatz | Kapselunterkante 5 cm über der realen Gehweghöhe; Bodenprüfung + Recovery |
| Enden | Baken + unsichtbare Kollisionswand bei s = −45 / +105 m | Spieler bleibt im gebauten Bereich |

## 5. Beleuchtung (Ursache des früheren Problems adressiert)

Frühere Vermutung: Lichter „wirkten nicht“. Typische Ursachen und Gegenmaßnahme hier:

1. **Ungebautes statisches Licht** → `r.AllowStaticLighting=False`, alle Lichter `Movable`.
2. **Auto-Exposure** hellt die Nacht grau auf oder dunkelt alles ab → ungebundenes
   PostProcess mit Histogramm-Belichtung, **EV100 −1,5 … 3,0** (Nacht) bzw. 10 … 15 (Tag),
   `ExtendDefaultLuminanceRange=True`.
3. **Einheitenchaos** → alle lokalen Lichter explizit in **Candela**; Mond 0,25 lx, Sonne 75.000 lx.
4. Lumen GI + Reflexionen, Virtual Shadow Maps, SkyAtmosphere + Echtzeit-SkyLight, Höhennebel.
5. **Taste N** schaltet Tag/Nacht um (Prüfung „Tages-/Nachtbeleuchtung“).

Hinweis: ProceduralMesh erzeugt keine Mesh Distance Fields → die LoD2-Gebäude tragen nicht zu
Lumen-Software-GI bei (direktes Licht + Schatten funktionieren). Nächster Ausbauschritt:
Gebäude im Editor in StaticMeshes konvertieren (Modeling Tools „Convert to Static Mesh“).

## 6. Abnahme auf dem Windows-PC (noch offen)

```bat
:: 1) Klonen inkl. LFS
git clone https://github.com/snopebushyfam/Stray.git && cd Stray
git checkout claude/jolly-allen-b3y08s && git lfs pull
:: 2) Projektdateien + Build (UE 5.8, VS 2022 17.14+ / VS 2026)
"C:\Program Files\Epic Games\UE_5.8\Engine\Build\BatchFiles\Build.bat" StrayEditor Win64 Development -Project="%CD%\Stray.uproject" -WaitMutex
:: 3) Daten-/Mathe-Tests (KEIN Spieltest)
"C:\Program Files\Epic Games\UE_5.8\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" "%CD%\Stray.uproject" -ExecCmds="Automation RunTests Stray.P001;Quit" -unattended -nullrhi -log
:: 4) Editor öffnen: erster Start erzeugt Materialien + /Game/Stray/Maps/L_P001_Street (Log: "STRAY_DIAG setup:")
"C:\Program Files\Epic Games\UE_5.8\Engine\Binaries\Win64\UnrealEditor.exe" "%CD%\Stray.uproject"
:: 5) Reproduzierbare Beweis-Screenshots aus der echten Ziel-Map (Saved\Screenshots\P001\)
"C:\Program Files\Epic Games\UE_5.8\Engine\Binaries\Win64\UnrealEditor.exe" "%CD%\Stray.uproject" /Game/Stray/Maps/L_P001_Street -game -windowed -ResX=1920 -ResY=1080 -StrayAutoShots -log
```

Danach **manuell** im PIE (Play in Editor) prüfen und die Screenshots nach
`production/qa/evidence/` kopieren:

- [ ] Log enthält `STRAY_DIAG build=ok lod2=1 buildings=155 ... lights=…` ohne `Error`
- [ ] `STRAY_DIAG spawn=... ground_hit=1 gap_cm≈5` (kein Spawn unter dem Boden)
- [ ] WASD/Maus/Gamepad bewegen und drehen; Shift rennt; Leertaste springt; Bordstein begehbar
- [ ] Lichtkegel der Straßenlampen sichtbar, Schaufenster/Fenster leuchten, Szene nicht schwarz
- [ ] KIOSK und NACHTFLUG lesbar, aus mehreren Perspektiven; nichts schwebt
- [ ] Kollision mit Gebäuden, Lampenmasten, Absperrpfosten, Endwänden
- [ ] N: Tag ↔ Nacht; `stat fps` / `stat unit` notieren (Ziel ≥ 60 fps)

## 7. Bekannte Risiken / nicht verifiziert

* **Kompiliert nie.** API-Annahmen für 5.8 (u. a. `UInputMappingContext::MapKey`,
  `UExponentialHeightFogComponent::SetFogInscatteringColor`, `FScreenshotRequest`) gegen
  `docs/engine-reference/unreal/` geprüft, soweit dort dokumentiert; Rest aus UE-5-Kenntnis.
* Python-Editor-API (`LevelEditorSubsystem.new_level`, `MaterialEditingLibrary`) ungetestet.
  Substrate ist in 5.8 für neue Projekte aktiv; die Materialien nutzen klassische Pins, die
  Substrate automatisch konvertiert.
* TextRender-Schriftzüge nutzen das Engine-Standardmaterial; deshalb sitzen sie vor
  leuchtenden Lichtkästen (lesbar, egal ob das Textmaterial beleuchtet ist).
* Prozedurale Netze doppelseitig (`bDoubleSidedProceduralMeshes=True`) als Sicherheitsnetz, bis
  die Wicklung im Editor bestätigt ist; danach in `DefaultGame.ini` abschalten (halbiert Dreiecke).
* Straßenoberfläche, Gelände und Gebäude sind ProceduralMesh: keine Distance Fields → kein
  Lumen-Software-GI-Beitrag, keine Nanite. Für die Produktion in StaticMeshes konvertieren.
* Keine Figur-Animation: Platzhalterkörper, bis das Third-Person-Content-Pack hinzugefügt und in
  `Config/DefaultGame.ini` eingetragen ist.

## 8. Nächste Schritte (Reihenfolge)

1. **Abnahme Abschnitt 6 auf Windows** — der einzige Schritt, der „spielbar“ belegen kann.
2. Fehler aus Build/Log beheben, Screenshots einchecken.
3. Gebäude → StaticMesh (Distance Fields, Lumen GI, Nanite), Fassaden-Materialien.
4. Danach erst NPCs/Verkehr (GDD-Reihenfolge).

## 9. Daten neu erzeugen

```bash
pip install numpy pyproj mapbox-earcut matplotlib
python3 tools/geodata/build_p001.py            # lädt Kachel + OSM nach tools/geodata/cache/ (gitignored)
python3 -m unittest discover -s tools/geodata/tests -v   # 12 Tests: Konvertierung + P001-Datenkonsistenz
```

Die Datenkonsistenz-Tests (`test_p001_data.py`) prüfen u. a., dass kein Gebäudesockel über dem
Gehweg schwebt. Dieser Test schlug zuerst fehl (Spalt bis 12 cm, Gehweg ohne Quergefälle) und ist
seit der Quergefälle-Modellierung grün.
