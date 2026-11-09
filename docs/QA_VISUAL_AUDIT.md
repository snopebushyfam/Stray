# STRAY – Visuelle und technische Qualitätsprüfung (2026-11-09)

Geprüfter Stand: Branch `claude/jolly-allen-b3y08s`, Ausgangs-Commit `52ca386`. Den Stand vor der Prüfung
sichert der Branch `backup/pre-qa-audit-2026-11-09` (gepusht, `main` unverändert).
Engine: Godot 4.7.2, Compatibility-Renderer (GL), Web-Export ohne Threads. Unreal-Dateien unter `Unreal/`
unverändert (archiviert, nie kompiliert).

## 1. Wie geprüft wurde

| Prüfung | Umgebung | Ergebnis |
|---|---|---|
| Gerendertes Spiel, 41 Screenshots aus dem laufenden Spiel (Spawn, Laufen, alle Kamerapunkte Tag/Nacht, KIOSK, Türsteher, Handy-Apps, Club, Wohnung, Schicht, Polizei, U-Bahn, Hbf, Prolog, Menüs) | Godot 4.7.2 unter Xvfb + Mesa llvmpipe (OpenGL 3.3), 1280×720 | vorher **und** nachher vollständig angesehen |
| Automatisierte Tests (22 Godot-Suites + Python-Datentests) | Godot headless | **22/22 grün, 370 Prüfungen**, Python OK (`production/qa/evidence/qa_audit_2026-11-09/tests.log`) |
| Fertiges itch.io-ZIP, entpackt, im iframe wie auf itch.io | Chromium (Playwright, SwiftShader-WebGL2) | Startmenü, „Neues Spiel“, Prolog am Hbf, Handy (Tab), Laufen mit W |
| Simulierte Touch-Bedienung | Chromium mit Touch (CDP), 1180×820 | Touch-Knöpfe sichtbar, Start per Fingertipp, Joystick + gleichzeitig Kamera-Finger, Rennen bei voll ausgelenktem Joystick |
| Echtes Tablet | — | **ungetestet** in diesem Durchlauf (die zwei vorherigen Tablet-Meldungen sind behoben, auf dem Gerät aber noch nicht nachgeprüft) |
| Ton | — | **ungetestet** (nie angehört, nur gemessen) |
| Bildrate | — | **ungetestet** (Software-Rendering in der Cloud sagt nichts über echte Geräte) |

Die Screenshots zeigen den aktuellen Build: Die Bilder unter `production/qa/evidence/godot/` wurden nach den
Korrekturen neu erzeugt (Log mit Zeitstempeln: `qa_audit_2026-11-09/autoshots.log`). Die Web-Bilder stammen aus
genau dem ZIP, das hochgeladen werden soll (SHA-256 unten).

## 2. Bestätigter Ist-Zustand (gesehen, nicht nur getestet)

| Bereich | Zustand |
|---|---|
| Startmenü, Pausemenü | funktionieren (Maus, Touch); Untertitel „Ankunft Hauptbahnhof“ |
| Prolog Hbf → U5 → Friesenplatz → KIOSK | spielbar, Ziele + Tipps sichtbar, Speichern mitten im Prolog funktioniert |
| U-Bahn | Eingang am Ring und am Hbf, Automat, Fahrt, Kontrolle, Ausgang |
| Steuerung / Kamera | Third-Person, Kamera weicht Wänden aus; Tastatur, Maus, Gamepad-Belegung, Touch |
| Straße P001 | echte LoD2-Gebäude + DGM1-Gelände, Bürgersteige, Bordsteine, Ampel, Bäume, geparkte Autos; Kollisionen über Tests geprüft (Laufen, Stehen auf Boden, kein Durchfallen) |
| Hbf P002 | echte Gebäude inkl. Dom und Halle, Platz auf echtem Gelände, Laternen |
| Tag/Nacht | beide Lichtstimmungen funktionieren; Laternen nur nachts |
| KIOSK, NACHTFLUG | Menü, Türsteher, Schlange, Club innen (Bar, Tanzfläche, Lea) |
| NPCs, Verkehr | 15 Passant:innen + Schlange, Autos auf 4 Spuren, Streifenwagen (nur am Ring) |
| Handy | Bank, Karte, Nachrichten, Kontakte, Jobs |
| Speichern/Laden | Autosave, Menü, Laden in allen Bereichen (Ring, Club, Wohnung, U-Bahn, Hbf) |

## 3. Gefundene und behobene Fehler

| # | Priorität | Fehler (gesehen auf) | Ursache | Behebung | Nachweis |
|---|---|---|---|---|---|
| 1 | 2 Kamera | Beim Betreten des Bahnsteigs schaute die Figur gegen die Stirnwand, Bild fast nur graue Wand (`before_P002_21_prologue_platform_goal.png`) | Blickrichtung mit falschem Vorzeichen (`-PI/2` statt `+PI/2`) | `metro_interactions.gd`: Blick am Bahnsteig entlang zum Zug | Regressionstest in `metro_test` erst **rot** (Blick +X), dann grün; neues Bild `P002_21_prologue_platform_goal.png` |
| 2 | 3 Grafik | Schaufenster leuchteten nachts als flache, fast weiße Tafeln (`before_P001_02_nachtflug_entrance_night.png`) | unbeleuchtetes Emissionsmaterial mit zu hoher Stärke + Glow | Leuchtstärke 1,15 → 0,75, Farbe abgedunkelt (`godot_render.json`), Fenstersprosse + dunkle Brüstung davor (`street_builder.gd`) | `P001_02_…_night.png`, `P001_03_…_night.png` |
| 3 | 4 UI | Meldungen mit 2–3 Zeilen wurden unten abgeschnitten (z. B. „Danke, gute Fahrt“) | Meldungskasten nur 85 px hoch | Kasten 120 px (4 Zeilen), Interaktionshinweis darüber verschoben (`ui.gd`) | `P001_00_player_spawn_night.png`, `P002_03_…` |
| 4 | 4 UI | Handy-Karte zeigte am Hbf/in der U-Bahn keinen Standort und keinen Hinweis | Karte kennt nur P001 | Hinweis „Du bist nicht auf dieser Karte (Hbf/U-Bahn)“ (`phone_map.gd`) | — (Textänderung, nicht als Bild belegt) |
| 5 | Nachweis | Kamerapunkt „Straße Nord→Süd“ stand auf einer Fahrspur – ein vorbeifahrendes Auto füllte das Bild (`before_P001_04_…`) | Blickpunkt bei v = +2 m | Blickpunkt auf den Mittelstreifen (Layout + `build_p001.py`) | `P001_04_street_north_to_south_*.png` |
| 6 | Nachweis | Übersicht Hbf aus 35 m Höhe steckte zwischen Gebäuden (`before_P002_12_hbf_overview_day.png`) | Blickpunkt zu niedrig/zu nah | 70 m über dem Vorplatz, Blick zum Dom (`build_p002.py`, `P002_Area.json`) | `P002_12_hbf_overview_*.png` |

Aus den vorherigen Tablet-Meldungen (vor diesem Durchlauf, schon im Build): Kamera-Zappeln mit zwei Fingern
(`touch_look_test`), kein Rennen auf Touch (`touch_run_test`). Beide hier im Browser mit simuliertem Touch erneut
bedient (`web_touch_2_moved.png`: rennende Figur, Kamera gedreht).

Geprüft und **kein** Fehler: Laufen mit W im Browser wirkte zunächst wirkungslos – auf dem großen Platz ändert sich
das Bild bei 1,35 m/s nur wenig; Laufanimation und verschwundener Hinweis belegen die Bewegung (`keys_b_holdW.png`).

## 4. Offene Probleme (nach Priorität)

| Prio | Problem | Vorschlag |
|---|---|---|
| 1 | Echtes Tablet nicht nachgeprüft (Kamera, Rennen, Leistung, Speichern im Browser, Ton) | neues ZIP hochladen, 10 Minuten spielen, Video wie zuvor |
| 2 | Keine Bildraten-Messung auf echter Hardware | auf dem Tablet FPS-Anzeige (Debug) einbauen und messen |
| 3 | Hbf-Halle als LoD2-Block mit Fensterraster statt Glasfront; Dom ohne Fassadendetail | eigenes Material/Modell für Wahrzeichen |
| 3 | Platz am Hbf ohne Passant:innen und Verkehr – wirkt leer | NPC-System auf P002 erweitern |
| 3 | Figuren sind neutrale Mannequins, Autos Quader | Charakter-/Fahrzeug-Assets (CC0) |
| 4 | Tastatur-Hinweiszeile wird auch auf Tablets angezeigt | auf Touch ausblenden |
| 4 | Treppen U-Bahn nur Teleport; generischer Bahnsteig | später modellieren |
| 4 | Laternen ohne Schatten (Renderer-Artefakte) | bei Engine-/Renderer-Wechsel neu bewerten |

## 5. 3DcityLoader-Export (`assets/geodata/3dcityloader_friesenplatz_nord/`)

| Frage | Ergebnis |
|---|---|
| Herkunft | laut Exportseite **kostenloser Export** von v2.3dcityloader.com („Hohenzollernring 93“); kein Beleg für eine gekaufte Karte |
| Inhalt | DXF mit 2.203 Gebäude-Dreiecken (`lod-2-buildings-nrw`) und 1.917 Gelände-Dreiecken; Kartentextur aus OSM-Daten (kein Luftbild, 0,2 m/px) |
| Lage | DXF-Ursprung = UTM32 E 355 232,703 / N 5 645 294,630; Ausdehnung 128 × 189 m, UTM E 355 237–355 365 / N 5 645 297–5 645 486 (nördlich von P001) |
| Maßstab / Höhe | Meter, 1:1; Höhen relativ (z 0,4–46,3 m; amtlich 45,7–76,4 m NHN, Versatz ≈ 45,4 m) |
| Vergleich mit amtlicher LoD2-Kachel `LoD2_32_355_5645_1_NW` | 276 von 350 Gebäude-Eckpunkten liegen **exakt** (< 1 cm) auf der amtlichen Kachel; 74 weichen um bis zu 5,6 m ab, und zwar **nicht** am Ausschnittrand (also kein Abschneiden). Vermutlich anderer Datenstand oder Aufbereitung beim Konverter. Die frühere Notiz „1.006 Eckpunkte mit 0,000 m“ zählte doppelte Eckpunkte und war zu optimistisch; README korrigiert. |
| Überschneidung mit dem Spiel | 0 der 54 amtlichen Gebäude in diesem Bereich sind schon im Spiel → keine Dubletten, aber auch kein Anschluss an P001 ohne neuen Straßenabschnitt |
| Entscheidung | **Nicht integriert.** Der Export enthält nichts, was die amtliche Kachel nicht schon (sauberer, mit Gebäude-IDs, Dach/Wand-Trennung und echten Höhen) liefert; ein Teil der Eckpunkte weicht ab. |
| Vorgehen für die nördliche Erweiterung | `tools/geodata/build_p001.py` um einen zweiten Abschnitt (Friesenplatz Nord) erweitern: gleiche amtliche Kachel (liegt im Cache), DGM1 + OSM, Straßenrahmen für den Platz; dann ist auch der echte U-Bahn-Eingang „Friesenplatz Süd“ (s ≈ 108,5) erreichbar. Die DXF-Datei bleibt nur als Referenz/Kartenbild. |

## 6. Empfehlung: Godot oder Unreal für eine realistische Kölner Open World

**Kurzfristig Godot behalten, langfristig Unreal Engine 5 für die realistische Fassung.**

- *Godot jetzt:* läuft und wird in der Cloud mit Screenshots geprüft, Web/Tablet-Version funktioniert, du kannst
  ohne PC testen. Das ist für die Phase „Systeme und Spielgefühl finden“ das Richtige.
- *Grenzen von Godot für das Ziel „realistisches Köln“:* Im Browser nur der Compatibility-Renderer (max. 16 Lichter
  pro Objekt, keine Laternenschatten ohne Artefakte, kein globales Licht); keine fertige Lösung für das Streamen
  großer Stadtgebiete und keine Georeferenz-Werkzeuge wie in Unreal (Cesium, World Partition). Für ein großes,
  fotorealistisches Köln wäre viel Eigenbau nötig.
- *Unreal 5:* World Partition (Streaming ganzer Stadtteile), Nanite (riesige Geometrie), Lumen (Nachtlicht mit
  Hunderten Lichtquellen), Large World Coordinates, Georeferencing/Cesium für amtliche Daten. Dafür: Windows-PC mit
  starker Grafikkarte, keine Web/Tablet-Version, in der Cloud nicht testbar.
- *Damit der Wechsel später billig bleibt:* Daten bleiben engine-neutral (JSON + OBJ aus `tools/geodata/`), Regeln
  liegen in reinen Logik-Klassen mit Tests (Geld, Miete, Job, Polizei, U-Bahn, Prolog) und lassen sich 1:1 nach C++
  übertragen. Sinnvoller Zeitpunkt: wenn die Kernschleife auf dem Tablet „rund“ ist und ein PC verfügbar ist.

## 7. Build

- `build/stray_web_itch.zip`, 12 934 882 Byte, SHA-256 `891fda7e88239e350c245d47dde5af805b78169725416745a0ec790b144cbaa2`
  (gebaut mit `tools/release/package_itch.sh`; nicht im Git, da `build/` ignoriert wird).
- Hochladen: siehe `docs/RELEASE_ITCH.md`. Die Spielseite `https://snopebushyfam.itch.io/stray` muss vom
  Konto-Inhaber aktualisiert werden (der Upload ist aus der Cloud ohne itch.io-Zugang nicht möglich).
