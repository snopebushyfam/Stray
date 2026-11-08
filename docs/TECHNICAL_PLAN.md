# STRAY — Technischer Plan

**Stand:** 2026-11-08 · **Engine:** Unreal Engine 5.8 (C++20), Ziel Windows/DX12 · **Branch:** `claude/jolly-allen-b3y08s`

> **Status Prototype 001: CODE + DATEN FERTIG, IN UNREAL UNVERIFIZIERT.**
> Die Cloud-Umgebung, in der dieser Stand entstand, hat **keinen Unreal Editor, kein
> UnrealBuildTool und keine GPU/GUI** (Linux-Container). Nichts davon wurde kompiliert,
> geladen oder gespielt. Die Abnahme in Abschnitt 6 muss auf dem Windows-PC laufen.

## 1. Bestandsaufnahme (Audit, 2026-11-08)

| Frage | Befund |
|---|---|
| Repository / Branch / Commit | `snopebushyfam/Stray`, `main` = `71014bb` „Initial commit“ (nur das Claude-Code-Game-Studios-Template, kein Spiel). Arbeitsbranch `claude/jolly-allen-b3y08s`. |
| Altes Unreal-Projekt (UE 5.8.2) | **Nicht vorhanden.** Kein `.uproject`, `.umap`, `.uasset` im Repo, in `game-studio-template`, `video-skills` oder im Upload-ZIP. Commits `6fd0a5c` / `e5f0b56` und `AStrayStreetBlockout` existieren in keinem erreichbaren Repository. |
| Git-LFS | Vorher keine LFS-Dateien. LFS 3.4.1 installiert; `.gitattributes` jetzt mit LFS-Regeln für `uasset/umap/obj/fbx/blend/glb/gml/png/...`. |
| Eigene Köln-3D-Karte | **Nicht auffindbar** (weder Repo noch ZIP). Nicht verwendet, nicht behauptet. |
| Amtliche Daten | **Erreichbar und verwendet:** Geobasis NRW LoD2 `LoD2_32_355_5645_1_NW.gml` (69,3 MB, Last-Modified 2026-05-26). OSM-API 0.6 erreichbar (Overpass nicht). |
| Unreal ausführbar? | **Nein.** Kein `UnrealEditor`, keine Engine-Installation, keine GPU. Blender ebenfalls nicht installiert. |
| Ausführbar war | Python 3 (+ numpy, pyproj, mapbox-earcut, matplotlib), git, git-lfs, clang (ohne UE-Header). |

## 2. Architektur

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
| Straßenachse, 2×2 Spuren | **gemessen** (OSM `highway=primary` „Hohenzollernring“) | Fahrbahn, Mittelstreifen, Markierungen |
| Fassadenfluchten | **gemessen** (LoD2, Strahltest alle 3 m) | West −16,7 m, Ost +19,2 m (Median) |
| Spurbreiten, Parkstreifen, Bordstein | **angenommen** | 3,4 m / 2,0 m / 15 cm |
| 12 Straßenlampen (8 m, 1.800 cd, 3.400 K, Schatten) | **angenommen** (OSM kartiert kaum Lampen) | SpotLight, beidseitig versetzt, 25 m |
| 29 Schaufenster, 142 erleuchtete Fenster | **prozedural**, deterministisch (Seed 1408) | RectLight + Emissive-Panel / ISM |
| KIOSK (Ostseite, s = 48 m) | Fassade real; Name **fiktiv** | Lichtkasten, Schaufenster, Tür, Markise, Kühlschrank, 2 Lichter |
| NACHTFLUG (Westseite, s = 64 m) | Fassade real; Club **fiktiv** | Portal, Lichtleisten, Vordach, Schriftzug, Absperrkordel, 2 Lichter |
| Spawn | Westgehweg, s = 22 m, Blick Richtung Friesenplatz | Kapselunterkante 5 cm über Gehweg; Bodenprüfung + Recovery |
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
* Gebäude doppelseitig (`bDoubleSidedBuildings=True`) als Sicherheitsnetz, bis die
  Wicklung im Editor bestätigt ist; danach in `DefaultGame.ini` abschalten (halbiert Dreiecke).
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
python3 -m unittest discover -s tools/geodata/tests -v
```
