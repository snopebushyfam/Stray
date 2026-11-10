# R13 – City Life & Nightlife: Samstagnacht am Hohenzollernring (2026-11-10)

Branch `claude/jolly-allen-b3y08s`, Ausgangsstand `c0735df` (R12.5), Backup-Branch `backup/pre-r13-2026-11-10`.
Godot 4.7.2, Compatibility/WebGL2. Keine neuen Stadtteile, keine neuen Assets, keine neuen Figuren-Typen, keine
Änderung an Anatomie (R12.3) oder Spielerfigur (R12.5).

## 1. Ursprünglicher Zustand (gemessen und beobachtet)

- `pedestrians.gd`: 15 Fußgänger auf 5 Gehspuren (je 3), laufen die Spur entlang und wechseln an den Blockenden auf
  die Gegenspur. Einziges Verhalten außer Gehen: vor dem Spieler stehen bleiben – **und zwar unbegrenzt**: Steht der
  Spieler am Spawn (zwischen den beiden West-Spuren), stauten sich mit der Zeit mehrere Passanten hinter ihm
  (Vorher-Film `film_A_before.png`, ab ~30 s).
- NACHTFLUG: 5 Personen in der Schlange, fest an ihren Plätzen, jede spielt dauerhaft dieselbe Animation
  (Idle oder Idle_Talking). Sonst niemand vor dem Club.
- KIOSK: niemand außer zufällig vorbeigehenden Passanten (Kunden gab es nur in der Spieler-Schicht).
- Verkehr: 12 Autos, feste Wunschgeschwindigkeit je Auto, Bodenhöhe per Raycast **jedes Frame je Auto**,
  keine Bremslichter, keine Tageszeit-Abhängigkeit. Kein Stadtleben abhängig von der Uhr.

Vorher-Material: `production/qa/evidence/r13_city_life/before/` – drei feste Kameras (A Ring-Gehweg am Spawn,
B NACHTFLUG, C KIOSK), Samstag 23:10, eine Sitzung, alle 3 s ein Bild über 60 s.

## 2. Neu: Alltagssituationen

Neues, datengetriebenes Ambient-System `src/p001/ambient_life.gd` (`StrayAmbientLife`, reine Logik ohne Nodes,
fester Seed) – `pedestrians.gd` setzt die Agenten nur noch in Figuren um (Position, Blickrichtung, Animation,
Kollisionskörper). Konfiguration: `data/p001/npc_config.json` → `"ambient"`.

**Zustände:** WALKING, APPROACHING, WAITING, TALKING, IDLE, LEAVING, OFFSTAGE (nur an den Blockenden, nur wenn der
Spieler ≥ 30 m entfernt ist – niemand verschwindet vor der Kamera).

**Pläne** (gewichtet nach Tageszeit-Profil, begrenzt durch `max` je Profil, damit immer Passanten unterwegs sind):

| Plan | Ablauf | Orte (Straßenkoordinaten s/v) |
|---|---|---|
| pass | weitergehen bis zum Blockende oder ein Stück, dann neu entscheiden | Gehspuren |
| linger | an einem Aussichtspunkt stehen, sich umschauen (IDLE, Blick wandert ±45° alle 4–9 s), weitergehen | 6 Plätze an Schaufenstern |
| meet | zwei Passanten derselben Seite verabreden sich: beide gehen zu einem Treffpunkt, der Erste wartet, dann reden beide 20–45 s, gehen in **entgegengesetzte** Richtungen auseinander | 4 Treffpunkt-Paare |
| group | Freundesgruppe vor einem Geschäft: wer allein ist, wartet; sobald jemand dazukommt, wird geredet (Sprecher/Zuhörer wechseln alle 5–12 s); nach 1–3 min geht man | 4 Dreier-Gruppen + Zweier-Gruppe vor dem KIOSK |
| club | dasselbe vor NACHTFLUG: Gäste kommen Richtung Eingang, stehen 80–220 s, gehen wieder | Vorplatz an der Tür (Vorrang) und nördlich der Schlange |
| kiosk | Kunde kommt zum KIOSK; ist das Fenster besetzt, wartet er am Warteplatz; am Fenster „bestellt“ er 6–11 s (Gesprächshaltung zum Fenster), dann geht er weiter. Kein Einfluss auf die Spieler-Wirtschaft | Fenster, Warteplatz |

**Bewegung:** auf den bewährten Richtungs-Gehspuren (kein Gegenverkehr auf einer Spur), seitlicher Schritt erst am
Ziel; Abstand zum Vordermann gestaffelt (0,9 m Stillstand); wer seitlich über Spuren tritt, lässt Gehende vorbei;
wer 1,2 s blockiert ist (Spieler oder andere Person), geht in 1,1 m Abstand außen herum – feste Ausweichseite je
Richtung (nordwärts zur Straße, südwärts zur Fassade), damit sich zwei Umgehende nie frontal treffen; steht der
Spieler auf dem eigenen Zielplatz, wird der Platz nach 3 s aufgegeben. Keine Pfadsuche, keine Physikabfragen.

**Warteschlange NACHTFLUG:** bleibt exakt an ihrer Position (die Einlassmechanik rechnet mit ihr) – aber nicht mehr
eingefroren: jede Person wechselt alle 12–35 s ruhig zwischen Idle und Idle_Talking und dreht sich leicht (±14°).
Ihre Größe folgt dem Profil (tagsüber 0, abends 3, nachts 5) und ändert sich nur, wenn der Spieler ≥ 30 m vom Club
entfernt ist.

**Tageszeit-Profile** (`ambient.schedule` / `profiles`, aus der Spieluhr, alle 2 s geprüft):

| Profil | Zeit | aktive Personen | Schlange | Verkehr | Schwerpunkt |
|---|---|---|---|---|---|
| day | 08–18 | 16 | 0 | 100 % | Passanten, KIOSK, Treffen; kein Club |
| evening | 18–22 | 18 | 3 | 90 % | Gruppen, Treffen |
| night | 22–05 | 20 | 5 | 75 % | Club-Vorplatz, Gruppen, KIOSK |
| early | 05–08 | 8 | 1 | 40 % | wenige Passanten |
| sunday_morning | So 05–12 | 9 | 0 | 50 % | ruhig, kein Nachtleben |

**Verkehr** (`traffic.gd`, Logik erhalten): Wunschgeschwindigkeit je Fahrer schwankt alle 5–15 s um ±12 %;
Bremslichter (eigene kleine Leuchte, ein gemeinsames Mesh/Material) leuchten beim Bremsen und Stehen; ein **Taxi**
(cremefarben, Dachschild) hält in 70 % seiner Durchfahrten 6–11 s an der Ostbordsteinkante in der Lücke zwischen
den geparkten Autos (s 29–35) und fädelt erst wieder ein, wenn hinten 18 m und vorne 14 m frei sind (kein Spieler
auf der Spur); Autos dahinter überholen es in der Spur. Anzahl fahrender Autos folgt dem Profil. Bodenstrahl je
Auto nur noch jedes 4. Frame. **Fehler behoben:** Mit schwankender Geschwindigkeit (bis 14 m/s) reichte die feste
9-m-Erkennung des Spielers nicht mehr – ein Auto hielt nur 0,6 m vor ihm (vom bestehenden Test erkannt). Jetzt
richtet sich die Erkennung nach dem Bremsweg (v²/2a + 3,5 m).

**Figuren:** weiterhin R10-Looks und die drei R12-Menschen (unverändert). Anzahl 15 → **20** (Westseite 11,
Ostseite 9) – erst nachdem gemessen war, dass die Zusatzkosten klein sind (Abschnitt 5); mit 15 wirkte der
Gehweg am Spawn zu leer (Film). Entfernte Figuren (> 40 m) animieren nur jedes 3. Frame (manueller
AnimationPlayer-Takt). Gruppen-Priorität: der Club-Vorplatz an der Tür und die Gruppe am Spawn füllen sich zuerst.

**Erscheinen/Verschwinden:** Personen gehen nur an den Blockenden „von der Bühne“ bzw. kommen dort herein, und
die Schlange ändert ihre Größe nur, wenn die Stelle **nicht im Bild der aktiven Kamera** liegt (oder > 70 m
entfernt ist) und der Spieler ≥ 30 m weg ist. Nach einem Uhrsprung beenden Tätigkeiten, die es zur neuen Zeit
nicht gibt (Club tagsüber), ihren Aufenthalt in 5–20 s und die Leute gehen weg.

## 3. Wer macht was (Momentaufnahme Samstag 23:10, Seed 2207)

Die Verteilung wechselt laufend; typisch gleichzeitig (Integrationstest, 60 s): bis zu ~9 Personen unterwegs
(WALKING/APPROACHING/LEAVING) und bis zu ~8 im Gespräch (TALKING), dazu Wartende und Schauende. Club-Vorplatz an
der Tür: 3 Gäste (wechselnd), 1 weiterer nördlich der Schlange; vor dem Laden am Spawn (s≈27): Gruppe;
KIOSK: Kunden in Abständen von ~10–80 s (Durchschnitt ~25 s); Ostseite: Treffen, Gruppe vor Geschäft s≈84.

## 4. Nachweise (eine Sitzung, gleiche Kameras, gleiche Uhrzeit)

`production/qa/evidence/r13_city_life/`:

| Datei | Inhalt |
|---|---|
| `compare_<Ort>_before_top_after_bottom.jpg` | gleiche Kamera, oben vorher, unten nachher, nach 0/21/39/60 s |
| `before/`, `after/` | Einzelbilder `<Ort>_t00s…t60s.jpg` und `timeline_<Ort>_every3s.jpg` (21 Bilder, alle 3 s) |
| `video/night_<Ort>_40s.mp4` | eine Sitzung, 40 s Spielzeit, 2 Bilder/s, Echtzeit-Wiedergabe |
| `video/day_*_30s.mp4`, `video/sun_*_30s.mp4` | Uhr auf Sa 14:00 bzw. So 09:00 gesprungen, 30 s |
| `timeofday_day14_sunday09_after_jump.jpg` | Club-Gruppe löst sich nach dem Sprung auf den Tag ruhig auf (≤ 30 s), Schlange bleibt, solange sie im Bild ist |
| `traffic/taxi_stop.jpg`, `taxi_pulls_out.jpg`, `brake_lights.jpg` | Taxi am Bordstein mit Bremslicht, Wiedereinfädeln |
| `web_chromium_touch.jpg` | Web-Export in Chromium (Touch-Emulation): 0/20/40 s, dann „Rennen: AN“ getippt + Joystick gezogen → Spieler läuft zur Tür, Türsteher-Hinweis |

Werkzeuge: `tools/perf/r13_city_probe.gd` (`shots`, `film`, `perf`, `cpu`; die Beobachterkameras pausieren das
Spiel während der Aufnahme, damit die Straße nur die Spielerkamera „sieht“), `tools/perf/r13_traffic_shot.gd`.

**Beobachtung (aus den Bildern, nicht geschönt):**
- **A Ring/Spawn:** vorher einzelne Passanten auf zwei Spuren, ab ~30 s ein Stau hinter dem Spieler. Nachher
  Passanten in beide Richtungen, die um den Spieler herumgehen, eine Gruppe vor dem Laden bei s≈27 und ein
  Treffpunkt bei s≈30 im Blick. Im Mittel 3,8 Personen im Bereich s 14–42 (headless gezählt, vorher ~2–3, davon
  ein Teil gestaut).
- **B NACHTFLUG:** vorher nur die starre Schlange. Nachher eine Dreiergruppe direkt an der Tür, die sich unterhält
  (wechselnde Sprecher), Gäste kommen an und gehen, Passanten laufen an der Gruppe vorbei; die Schlange wechselt
  ruhig Haltung/Blick.
- **C KIOSK:** vorher leer. Nachher kommen Kunden, stehen am Fenster, gehen weiter; Abstand zwischen Kunden
  ~10–80 s (im 40-s-Film kaufen in der ersten Hälfte zwei, danach Passanten).
- Keine Figur in Gebäuden/Gegenständen, kein Schweben, keine Überlappung gesehen; Gespräche ruhig (Wechsel alle
  5–12 s).

## 5. Performance (Cloud-Messung – keine Geräte-FPS)

Gleiche Orte, gleiche Kameraperspektive (Spielerkamera), Samstag 23:10. Rendering: Xvfb + llvmpipe. CPU:
headless, Cloud-CPU – Größenordnungen, keine Gerätewerte.

| Ort | Draw Calls vorher → nachher | Dreiecke vorher → nachher |
|---|---|---|
| A Ring | 557 → 554 | 165 k → 170 k |
| B NACHTFLUG | 306 → 310 | 125 k → 148 k |
| C KIOSK | 271 → 277 | 114 k → 130 k |

| CPU je Frame (direkt gemessen, 600 Frames, Mittel aus 2–3 Läufen) | vorher | nachher |
|---|---|---|
| Fußgänger-Logik + Platzierung + Animation der Gehenden | 0,34 + 0,22 ms (15 Gehende) | 0,92 ms (20 Gehende, inkl. Animation) |
| Animation der Schlange | (oben enthalten) | 0,05 ms |
| Verkehr (`_physics_process`) | 0,38 ms | 0,26 ms (Raycast nur jedes 4. Frame) |
| **Summe** | **~0,94 ms** | **~1,23 ms (+0,3 ms)** |

Davon die neue Verhaltenslogik (`StrayAmbientLife.update`, 15 Personen) ~0,23 ms. Aktive NPCs: 15 + 5 Schlange →
20 + 5. Speicher (statisch): 118,3 → 119,7 MB (gerendert), 159,1 → 160,5 MB (headless). Keine neuen Materialien
oder Meshes zur Laufzeit (Bremslicht: ein gemeinsames Mesh + Material). Optimiert im selben Durchlauf: Konfig-
Werte gecacht, stehende Figuren ohne Transform-/Körper-Update, Nachbarprüfung nur gleiche Seite und ±3 m,
entfernte Figuren (> 40 m) animieren jedes 3. Frame. Verworfen: Logik-LOD für entfernte Figuren (nur ~0,1 ms
Gewinn, verursachte größere Schritte und Überlappungen). Die Ein/Aus-Differenzmessung („cpu“-Modus) schwankte auf
der Cloud-CPU zu stark (vorher 0,4–3,0 ms) und ist nur als Rohwert im Werkzeug enthalten.

## 6. Tests

| Test | Inhalt | Ergebnis |
|---|---|---|
| `tests/unit/p001/ambient_life_test.gd` (neu, 32) | alle Zustände werden durchlaufen, Treffen mit gleichzeitigem Gespräch, KIOSK-Bestellung, nie zwei Personen auf einem Platz, keine Stehplätze auf Gehspuren, Gehweg-Grenzen, Profile je Uhrzeit (Sa 14:00/20:30/23:10/06:30, So 02:00/09:00), weniger Leute früh morgens, kein Club-Plan tagsüber, Verschwinden nur fern vom Spieler, Spieler auf der Spur wird umgangen, gleiche Seeds → gleiche Straße, 8 Seeds × 10 min ohne Überlappung/Blockade, Club leert sich nach Nacht→Tag | grün |
| `tests/integration/p001/city_life_test.gd` (neu, 24) | 36 Stehplätze: auf dem Gehweg, frei von Geometrie (Physik-Abfrage), ≥ 1,5 m von KIOSK, Clubtür, Schlangenende, Geldautomaten, Spawn, ≥ 0,9 m von Schlange/Türsteher; eine Minute Samstagnacht: gleichzeitig Gehen und Reden, ≥ 5 Zustände, ein KIOSK-Kunde, nie jemand auf KIOSK-Fenster/Clubtür/Schlangenende, keine Überlappung, Füße am Boden, Schlange unverändert; Spieler läuft frei; KIOSK-Menü öffnet; Anstehen → Türsteher lässt ein; Schlange im Bild verschwindet nicht; Tagprofil ohne Schlange, Verkehr 100 %; Sonntagmorgen ruhiger; Speichern/Laden übernimmt das Profil; Regionswechsel pausiert/setzt fort | grün |
| `street_life_test` | „approaching car stays clear“ schlug mit schwankender Geschwindigkeit fehl (0,6 m) → Bremsweg-Erkennung | grün |
| `kiosk_crossing_test` (Prolog-Weg U-Bahn → Überquerung → KIOSK, Prolog-Ende) | schlug fehl, weil Treffpunkte im Gehkorridor standen → West-Plätze an die Schaufenster verlegt | grün |
| gesamte Suite `tests/run_tests.sh` | 31 Suites, 495 Prüfungen + Python-Datentests | `ALL_TESTS_EXIT=0` |

Regressionstests vor der Korrektur gesehen fehlschlagen: Umgehen des Spielers (588 s Wartezeit ohne Korrektur),
Club leert sich nach Nacht→Tag (4 bleiben), Schlange im Bild (0 sichtbar ohne Kamera-Prüfung).
Browser: Web-Export (`tools/release/package_itch.sh`) in Chromium mit Touch-Emulation, siehe Abschnitt 4.

## 7. Offene Probleme und Grenzen

| Prio | Problem |
|---|---|
| 1 | **FPS auf iPhone/Tablet ungemessen.** Mehr Personen im Bild (NACHTFLUG +23 k Dreiecke) und +0,3 ms CPU je Frame (Cloud) – bitte mit F3 / FPS-Knopf am NACHTFLUG und am Spawn messen. Notfalls `lanes[].count` und `profiles.*.active` in `npc_config.json` senken (zurück auf 15 kostet nichts außer Dichte). |
| 2 | Keine Handy-Animation: „Handy-Ruhehaltung“ ist ein Stehen mit Umschauen (keine passende CC0-Animation vorhanden, bewusst nichts Unglaubwürdiges gebaut). |
| 2 | KIOSK-Kunden kommen unregelmäßig (Pausen bis ~80 s möglich). |
| 2 | Im Browser (SwiftShader, ~1 Bild/s) vergeht kaum Spielzeit – die zeitliche Abfolge ist im Godot-Lauf belegt, im Browser nur Start, Gruppe, Touch und Interaktion. |
| 3 | Figuren gehen auf Spuren; Umgehen ist ein einfacher Seitenschritt, kein Ausweichen in Gruppen. Bei sehr dichtem Spielerverkehr (Spieler läuft mitten durch eine Gruppe) schieben Kollisionskörper. |
| 3 | Gespräche sind Haltungswechsel Idle/Idle_Talking – keine Blickkontakt-/Kopfdrehung zum Partner. |
| 3 | Verkehr: kein Ampel-/Kreuzungssystem (bewusst nicht in R13), Taxi hält nur an einer Stelle; keine Fahrgäste steigen ein. |
| 3 | Nach einem Uhrsprung startet die Straße aus dem Nachtzustand und braucht bis ~30 s, um sich anzupassen (ruhig, ohne Verschwinden im Bild). |

## 8. Build

`build/stray_web_itch.zip` (`tools/release/package_itch.sh`), SHA-256 `fd69c7c96903b68ae5c0bd8fff8e026c164e00bf2ffc6c3d637342c32ef26014`.
Upload auf itch.io durch den Konto-Inhaber.
