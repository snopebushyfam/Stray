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

**Schritt 2 „Leben auf der Straße“ (2026-11-08, gespielt + getestet):**

| | Umsetzung | Daten |
|---|---|---|
| 15 Fußgänger | `src/p001/pedestrians.gd`: Gehweg-Spuren mit fester Richtung, Spurwechsel an den Enden (kein Gegenverkehr in einer Spur), Abstand halten, vor dem Spieler stehen bleiben; Walk/Idle-Animation mit tempo-gekoppelter Schrittfrequenz; 8 Kleidungsfarben, Größe ±7 % | `data/p001/npc_config.json` |
| NACHTFLUG-Schlange | 5 Wartende an der Absperrung (Idle / Idle_Talking), Kollision | dito |
| 12 Autos, 4 Spuren, Rechtsverkehr | `src/p001/traffic.gd`: Folgefahrt mit Sicherheits-/Haltabstand, halten vor dem Spieler, fahren von s = −80 bis +165 m über das reale DGM1-Gelände (Straßenoberfläche) und erscheinen danach neu; Höhe per Raycast; Front-/Rücklichter; Räder drehen | dito |
| Endabsperrung | nur noch auf den Gehwegen; die Fahrbahn bleibt für den Verkehr offen, der Spieler wird weiter von der unsichtbaren Wand gestoppt | — |

Test `street_life_test` 12/12: Autos bewegen sich und liegen auf der Fahrbahn (max. 1 mm Abweichung),
Abstand in der Spur, Rechtsverkehr, Auto hält 2,9 m vor dem Spieler; Fußgänger bleiben auf dem
Gehweg, überlappen nicht, halten vor dem Spieler. Kollisionsebenen: Welt 1, Autos 2, Fußgänger 4.
Beim Lauf gefunden und behoben: Typfehler in `traffic.gd` (Compile-Fehler), und der Test-Runner wertete
Skriptfehler nicht als Fehlschlag — jetzt zählt jeder `SCRIPT ERROR`, und Godot importiert vorher
neue Klassen. Noch nicht: Motorgeräusche, Ampelphasen (Ampel bleibt für Autos grün), Fußgänger
überqueren die Straße nicht.

**Schritt 3 „Erste Interaktion“ (2026-11-08, gespielt + getestet):**

| | Umsetzung |
|---|---|
| Geld, Inventar, Ruf (Nachtleben / Sozial / Polizei) | `src/p001/life_state.gd` — reine Logik, Start 35,00 € |
| KIOSK | `kiosk_shop.gd` + Menü (`ui.gd`): „[E] Kiosk“ an der Tür, 5 Artikel, Kauf zieht Geld ab, Ablehnung bei zu wenig Geld; Bewegung pausiert im Menü. Kein begehbarer Innenraum (LoD2-Gebäude sind geschlossene Hüllen). |
| NACHTFLUG-Tür | `bouncer_rules.gd` + Türsteher-Figur: Reihenfolge der Prüfungen: tagsüber zu → genervt (erneut gefragt binnen 30 s, −2 Ruf) → Ruf ≤ −3 → nicht angestanden (kein Ruf-Verlust) → zu betrunken (≥ 3 Kölsch, −1) → kein Eintrittsgeld (15 €, −1) → Einlass (+1). Anstehen = 15 s am Ende der Schlange. Club-Innenraum folgt später. |
| Bedienung | `E` / Touch-Button „Interagieren“, Hinweistext, Sprechblase, Anzeige Bargeld + Ruf |
| Daten | `data/p001/economy_config.json` (Preise in Cent, Regeln, alle Texte) |

Tests: `life_rules_test` 20/20, `interaction_test` 16/16 (Kiosk-Kauf, vordrängeln abgewiesen, anstehen,
Einlass mit Eintritt und Ruf, tagsüber zu). **Gefundener Logikfehler:** Wer zum Anstellen geschickt
wurde und nach dem Anstehen zurückkam, galt als „genervt“ (−2 Ruf). Regressionstest erst rot (2 Fehler),
nach der Korrektur grün. Offen: Kiosk-Unterzeile teils von der Markise verdeckt; Ruf hat außer am
Türsteher noch keine Folgen; Getränke haben keine Wirkung außer dem Alkoholzähler.

**Schritt 4 „Smartphone“ (2026-11-08, gespielt + getestet):**

| | Umsetzung |
|---|---|
| Spielzeit | `game_clock.gd`: Sa 14.11., Start 23:10, 10 × Echtzeit; Licht folgt der Uhr (Tag 7–20 Uhr); N springt auf 14:00 bzw. 23:30. Club geöffnet 23:00–06:00 (über Mitternacht). |
| Handy (Tab / Touch „Handy“) | `phone_ui.gd`: Statuszeile (Uhrzeit, Akku sinkt pro Spielstunde, ungelesene Nachrichten); Apps **Bank** (Konto, Bargeld, letzte Buchungen), **Karte** (`phone_map.gd`: 214 echte LoD2-Grundrisse, Position + Blickrichtung, KIOSK, NACHTFLUG, Geldautomaten), **Nachrichten**, **Kontakte**, **Jobs** (Anzeige, noch nicht annehmbar). Bewegung pausiert. |
| Konto + Geldautomaten | `life_state.gd`: Konto 120 €, Buchungen für jede Zahlung; 2 Geldautomaten an den **echten OSM-Positionen** (`amenity=atm`), 20 € abheben. |
| Nachrichten | `messages.gd`: ereignisgesteuert (Start: Vermieter mit Mietfälligkeit 450 €, Mama; nach Club-Einlass eine unbekannte Nummer, die als Kontakt erscheint; unter 5 € Bargeld Mama). Jede Nachricht genau einmal. |
| Daten | `data/p001/phone_config.json` (Uhr, Bank, Akku, Kontakte, Nachrichten, Jobs) |

Tests: `phone_logic_test` 19/19 (u. a. Mitternacht, Öffnungszeiten, Abhebung über Kontostand verweigert,
Nachrichten nur einmal), `phone_test` 17/17. Beim Lauf gefunden und behoben: Typfehler in `game_clock.gd`;
das offene Handy verdeckte die Geldanzeige; ein Rechenfehler in einem Test (6 h statt 60 min vorgespult —
die Uhr war richtig). Offen: Miete hat noch keine Fälligkeit/Folge, Jobs nicht annehmbar, Akku ohne Wirkung.

**Club-Innenraum NACHTFLUG (2026-11-08, gespielt + getestet):**

| | Umsetzung |
|---|---|
| Raum | `club_interior.gd`: geschlossener Raum 18 × 14 × 5 m unter der Straße (unsichtbar bis zum Einlass); Wände, Decke, LED-Leisten, Notausgang-Schild |
| Tanzfläche | 6 × 6 leuchtende Felder, Farbwechsel im Takt (124 BPM), 4 drehende Farbstrahler, 12 Tanzende (Dance / Idle_Talking), DJ am Pult |
| Bar | Theke, Flaschenregal, Barkeeper; Clubpreise (Kölsch 3,50 €, Wasser 3,00 €, Longdrink 9,00 €, Mate 4,00 €) über dieselbe Kauflogik wie der Kiosk |
| Lea | „Persistente“ NPC-Anlage: Dialog mit 3 Antworten → sozialer Ruf +1 / 0 / −1, bei freundlicher/neutraler Antwort erscheint die unbekannte Nummer als „Lea“ in den Kontakten |
| Ablauf | Einlass → nach 1,5 s drinnen am Ausgang; „[E] Rausgehen“ → vor der Clubtür; drinnen Clubmusik (`club_music_loop.wav`, voll), draußen gedämpfter Bass + Stadt |
| Daten | `data/p001/club_interior.json` (Raum, Licht, Tänzer, Barkarte, Dialog) |

Test `club_test` 16/16 (Einlass → drinnen und auf dem Boden, Musik-Wechsel, Bar-Preis, Lea-Dialog,
Kontakt, raus auf die Straße). Beim Sichttest gefunden und behoben: Raum zu dunkel, Lea stand halb in
der Theke, Barkeeper fehlte, Clubmusik zu hell (9,4 kHz → 1,7 kHz) mit Klick am Schleifenpunkt.
Offen: Lea hat nur einen Dialogschritt; Tanzen für den Spieler; Getränke ohne Wirkung.

**R1 Spielstand + Menüs (2026-11-09, gespielt + getestet):**

| | Umsetzung |
|---|---|
| Speicherstand | `save_game.gd`: eine JSON-Datei `user://stray_save_1.json` (Version 1); enthält Geld, Konto, Buchungen, Inventar, Ruf, Alkoholzähler, Flags, Uhrzeit, Nachrichten (gelesen/ungelesen, bereits zugestellt), Kontakte (inkl. „Lea“), Lea-Gespräch, Akku, Position, Blickrichtung, im Club ja/nein. Fehlende Felder → Standardwerte, kaputte Datei → wird abgelehnt. |
| Automatisch speichern | alle 90 s, beim Betreten/Verlassen des Clubs, beim Hauptmenü, beim Beenden/Fenster schließen |
| Startmenü | Weiterspielen (nur mit Spielstand) · Neues Spiel · Beenden (nicht im Browser); Straße läuft im Hintergrund, Spiel pausiert |
| Pausenmenü | Esc / P / Touch „Menü“: Fortsetzen · Speichern · Laden · Hauptmenü |
| Daten | `data/p001/game_config.json` (Speicherpfad, Intervall, Menütexte) |

Tests: `save_roundtrip_test` 12/12, `save_load_test` 20/20 (spielen → speichern → neue Spielinstanz →
laden → alles gleich; auch im Club; kaputter Spielstand). Belege: `P001_40_start_menu.png`,
`P001_41_pause_menu.png`. Behoben beim Sichttest: Startnachricht erschien schon hinter dem Startmenü;
Menükasten zu hoch. **Nicht geprüft:** Speichern im Browser über einen Neustart hinweg (Godot legt
`user://` im Web in IndexedDB ab; Persistenz dort nicht getestet).

**R2 Wohnung, Schlafen, Tageswechsel, Miete (2026-11-09, gespielt + getestet):**

| | Umsetzung |
|---|---|
| Wohnung | `home.gd`: kleines Zimmer (Bett, Schreibtisch + Lampe, Schrank, Fenster mit Nachtblick, Teppich), unsichtbar bis betreten. Haustür = echter OSM-Eingang (`entrance=staircase`, Ostseite, s ≈ 23 m), „Zuhause“-Markierung auf der Handy-Karte. |
| Schlafen | „[E] Schlafen“ → bis 10:00 des nächsten Tages: Tageslicht, Alkohol abgebaut, Akku 100 %, Autosave, „Guten Morgen“ |
| Kalender | `game_clock.gd`: echter Kalender ab Sa 14.11.2026 (Monats-/Jahreswechsel über Godot `Time`), Datum in HUD und Handy |
| Miete | `rent.gd`: 450 € Dauerauftrag am 1. vom Konto; Erinnerung 3 Tage vorher; geplatzt → Mahnung, tägliche Wiederholung; am 4. Verzugstag Räumung (Schloss getauscht). Bank-App zeigt Fälligkeit. |
| Nachrichten | Vermieter (Erinnerung, Eingang, Mahnung, Räumung); Morgennachrichten ab 08:00 bzw. beim Aufwachen |
| Speichern | Mietstand + „in der Wohnung“; Laden verarbeitet Tage nicht doppelt (Reihenfolge Nachrichten → Miete → Uhr) |
| Daten | `data/p001/home_config.json`, Nachrichten in `phone_config.json` |

Tests: `day_rent_test` 15/15, `home_test` 24/24. **Beim Lauf gefundene Fehler:** (1) Nach dem
Verlassen von Wohnung/Club stand die Kamera in der Hauswand → schwarzes Bild; jetzt Blick entlang der
Straße + Kugel-Kollision der Kamera + kürzerer Abstand innen; Test prüft die Kameraposition. (2) Mamas
„Guten Morgen“ kam um Mitternacht (vom älteren Speichertest aufgedeckt) → jetzt ab 08:00. (3) Zwei
Testfehler meinerseits (Räumungstag falsch gezählt, Endlosschleife beim Vorspulen).
Offen: In der kleinen Wohnung steht die Figur am Bildrand.

**R3 Erster Job: Aushilfe KIOSK (2026-11-09, gespielt + getestet):**

| | Umsetzung |
|---|---|
| Bewerbung | Handy → Jobs → „Bewerben“; Kiosk-Chef Erol (fiktiv) schreibt und wird Kontakt |
| Schicht | täglich 18–22 Uhr; am Kiosk „[E] Schicht beginnen“: bis 18:15 pünktlich, bis 19:00 mit 25 % Lohnabzug, danach zu spät = verpasst |
| Arbeit | 8 Kund:innen pro Schicht (Figur am Kiosk, Bestellsatz), richtiges Produkt wählen; richtig = 0,50 € Trinkgeld bar; Bestellungen pro Tag reproduzierbar |
| Lohn | 4 h × 13,50 € = 54 € aufs Konto („Lohn Kiosk“), Uhr springt auf Schichtende, Autosave |
| Konsequenzen | > 2 Fehler oder verpasste Schicht = Abmahnung (Nachricht); 2 Abmahnungen = Kündigung, keine Neubewerbung |
| Daten | `data/p001/jobs_config.json`; Logik `src/p001/kiosk_job.gd` |

Tests: `kiosk_job_test` 21/21, `job_test` 14/14. Rechnung für den Kern-Loop: 17 Tage bis zur Miete,
max. 17 Schichten × (54 € + 4 €) ≈ 986 € gegen 450 € Miete — ohne Job nicht zu schaffen, mit Job gut.
Beim Sichttest behoben: alte Meldung lag hinter dem Bestellfenster. Offen: Spieler steht vor statt hinter
der Theke; Schichten dauern keine Spielzeit-Echtzeit (Sprung auf 22:00).

**R4 Konsequenzen-Grundgerüst (2026-11-09, gespielt + getestet):**

| | Umsetzung |
|---|---|
| Polizei-Aufmerksamkeit | `consequences.gd`: 0–100, sinkt 6/Spielstunde; Quellen mit Abklingzeit: auf der Fahrbahn stehen (+6), betrunken ab 3 Drinks (+12), Ladendiebstahl erwischt (+45), Türsteher bedrängen (+5), weglaufen (+35). Vorfälle werden protokolliert. HUD: „Polizei ●●●○○“. |
| Streifenwagen | ein Polizeiauto (silber, blauer Streifen, Blaulicht blinkt beim Halt) im Verkehr; ab Aufmerksamkeit 30 und ≤ 22 m Abstand hält er an → Kontrolle |
| Kontrolle | Ausweis zeigen oder weglaufen. Ergebnis nach Lage: < 50 Verwarnung; 50–79 Bußgeld 60 € (erst bar, dann Konto); ≥ 80 oder ≥ 5 Drinks Platzverweis bis 06:00; Weglaufen +35, ab 100 Festnahme (200 €, Entlassung 08:00). Polizeiakte; Mama meldet sich. |
| Klauen | Kiosk-Menü „Klauen (riskant)“: 55 % erwischt (80 % nach einem Erfolg). Erwischt = dauerhaftes Hausverbot, +45 Aufmerksamkeit, Erol kündigt. |
| Ruf wirkt | Türsteher: Platzverweis oder Aufmerksamkeit ≥ 50 → kein Einlass |
| Daten | `data/p001/consequences_config.json` |

Tests: `consequences_test` 24/24, `consequences_it_test` 16/16 (Fahrbahn, Streifenwagen hält, Bußgeld,
Mama, Platzverweis an der Clubtür, Diebstahl → Hausverbot + Kündigung, Speichern). Zwei Testfehler meinerseits
(Rundung bei laufendem Abbau, Bremsweg) korrigiert. Offen: Polizist:in als Figur, Kamera auf den Streifenwagen.

**R5 Zweites Gebiet Hbf + U-Bahn (2026-11-09, gespielt + getestet):**

| | Umsetzung |
|---|---|
| Gebiet P002 | Bahnhofsvorplatz/Domplatte am echten Ort (≈ 1,4 km ostnordöstlich von P001, **gleicher lokaler Ursprung**). `tools/geodata/build_p002.py` → `data/p002/`: 71 LoD2-Gebäude (Hbf-Halle, Dom, Umgebung; Kachel `LoD2_32_356_5645_1_NW`), DGM1-Höhenraster 1 m (181 × 176), 7 OSM-Laternen + 19 prozedurale (markiert), OSM-Mülleimer, U-Bahn- und Bahnhofseingänge. |
| Godot | `src/p002/area_layout.gd` (Daten + Höhe bilinear), `area_builder.gd` (Boden in 20-m-Kacheln mit Plattenshader, Kollision als `HeightMapShape3D`, Gebäude je Mesh, Dom in dunklem Sandstein statt Fensterraster, Laternen, U-Schild, Schriftzug „Köln Hauptbahnhof“, unsichtbare Gebietsgrenzen). |
| U-Bahn | `transit.gd` (reine Logik): Linie 5 Friesenplatz ↔ Dom/Hbf, 3 Min. warten + 4 Min. Fahrt, EinzelTicket 3,80 € (bar, **Preis angenommen**), Kontrolle 25 % (Seed, Zustand gespeichert), ohne Ticket 60 € erhöhtes Beförderungsentgelt (bar → Konto → offen). `metro_station.gd`: ein generischer Bahnsteig (kein Nachbau der echten Stationen) mit Automat, Zug, Treppe; Schilder wechseln den Namen. `metro_interactions.gd` hängt sich als Erweiterung an `interactions.gd`. |
| Regionen | `main.set_region()`: nur das Gebiet, in dem man ist, wird gezeigt (P001 + NPCs/Verkehr, P002 oder Bahnsteig) – hält den Compatibility-Renderer unter dem Lichtlimit. HUD zeigt den Ort. Spielstand speichert Station, Ticket, Region. |
| Eingänge | Friesenplatz: U-Stele am Westbürgersteig bei s = 100,5 (der echte Eingang „Friesenplatz Süd“ liegt bei s ≈ 108,5 knapp hinter dem gebauten Abschnitt, daher **8 m verschoben**). Dom/Hbf: OSM-Eingang „Dom/Hauptbahnhof“, 8 m Richtung Dom versetzt, weil der OSM-Punkt im LoD2-Grundriss der Halle liegt. |

Tests: `transit_area_test` 26/26 (Mutationen „Ticket wird nicht verbraucht“ und „Strafe trotz Ticket“
fallen durch), `metro_test` 30/30 (Ring → Bahnsteig → Ticket → Fahrt → Hbf auf echtem Boden → laufen →
Speichern/Laden am Hbf → schwarzfahren mit Kontrolle → zurück auf den Ring). Web-Export lädt P002
(Chromium/SwiftShader). Sichtprüfung: `production/qa/evidence/godot/P002_*.png`. Offen: Hbf-Halle hat
Fensterraster statt Glasfront, keine Passant:innen/Verkehr am Hbf, Phone-Karte zeigt nur P001, Treppe
ist Deko (Teleport).

**R6 Prolog (2026-11-09, gespielt + getestet):**

| | Umsetzung |
|---|---|
| Ablauf | „Neues Spiel“ → 22:40 vor dem Hbf-Ausgang „Bahnhofsvorplatz/Domseite“, Intro-Text, Nachricht von Erol (Kontakt wird bekannt). Ziele oben links: U-Bahn Dom/Hbf → Fahrkarte (oder schwarzfahren, überspringt den Schritt) → Linie 5 → Treppe hoch → Erols KIOSK (≤ 4 m). Zu jedem Schritt ein Tipp zur Steuerung. Am Ziel: Erols Begrüßung, Verweis auf die Jobs-App (R3), automatisches Speichern. |
| Code | `src/p002/prologue.gd` (reine Logik, Schritte enden durch Spielereignisse), Anbindung in `main.gd` (`start_prologue`, Ereignisse aus `metro_interactions.gd`, Nähe zum KIOSK), `ui.set_objective()`. Spielstand speichert den Schritt; ältere Spielstände gelten als „Prolog erledigt“. Tests/Autoshots starten weiter auf dem Ring (Prolog nur über „Neues Spiel“). |
| Daten | `data/p002/prologue_config.json` (Startzeit, Texte, Schritte), Nachrichten `erol_welcome`/`erol_arrived` in `phone_config.json` |

Tests: `prologue_test` 11/11, `prologue_it_test` 17/17. Gefundener Fehler: das Autosave beim Hochkommen lief
vor dem Prolog-Schritt (Laden → falscher Schritt). Regressionstest zuerst rot gesehen, dann behoben
(Speichern verzögert). Beim Sichttest korrigiert: Kamera hinter der Friesenplatz-Stele (Ausstieg 6 m südlich).

**R7 Web-Version für itch.io (2026-11-09, Paket geprüft, Upload offen):** `tools/release/package_itch.sh`
baut den Web-Export (ohne Threads) und `build/stray_web_itch.zip`; `build/.gdignore` verhindert, dass Godot
den Export als Projekt-Assets importiert. Das ZIP lief entpackt im iframe mit Touch-Eingabe (Prolog per
Fingertipp gestartet). Beim Sichttest behoben: die Zielzeile lag auf Tablets unter den Touch-Knöpfen.
Anleitung: `docs/RELEASE_ITCH.md`.

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
python3 tools/geodata/build_p002.py            # R5: Hbf/Domplatte (Kachel 356_5645, DGM1, OSM) -> data/p002/
python3 -m unittest discover -s tools/geodata/tests -v   # 12 Tests: Konvertierung + P001-Datenkonsistenz
```

Die Datenkonsistenz-Tests (`test_p001_data.py`) prüfen u. a., dass kein Gebäudesockel über dem
Gehweg schwebt. Dieser Test schlug zuerst fehl (Spalt bis 12 cm, Gehweg ohne Quergefälle) und ist
seit der Quergefälle-Modellierung grün.
