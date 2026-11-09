# R9.2 – Kritische Spielfehler und Performance (2026-11-09)

Ausgangsstand `cba2036`. Grundlage: Rückmeldungen und FPS-Messungen vom echten Tablet.

## 1. Unsichtbare Wand zum KIOSK (Priorität 1) – behoben

**Reproduktion im echten Spiel** (Diagnose-Skript, dann Integrationstest): Spieler läuft mit Eingaben vom
Westgehweg nach Osten. Er blieb an folgenden Stellen hängen (`get_slide_collision()`):

| Collider | Lage | Form | Bewertung |
|---|---|---|---|
| `StreetCollision` (StaticBody3D, Layer 1, Kind von `Street`) | östliche Bordsteinkante s = 49–52, v = +9,33, Kontaktnormale (−0,82; 0,54; −0,16) | ConcavePolygonShape3D der Straßenoberfläche: Bordstein 0,155–0,176 m hoch (DGM1-Profil) | **Ursache** – der Spieler konnte keine Stufe hinauf |
| `StreetCollision` | westliche Bordsteinkante v = −9,33 (Rückweg) | wie oben, 0,19–0,20 m | **Ursache** (gleiche) |
| `StreetCollision` | Mittelinsel v = −0,60, Normale (−0,74; 0,66; −0,15) | Mittelinsel 0,12 m | blockierte beim geraden Rennen |
| `@StaticBody3D@…` (BoxShape 1,8 × 1,45 × 4,4–4,8 m, Mitte v = −8,33) | entlang des Westbordsteins | Kollision der **geparkten Autos** | sichtbar, gewollt; Lücken ≈ 2 m zum Durchgehen bleiben |

**Ursache:** Der `CharacterBody3D` des Spielers hatte keine Stufen-Logik. Bergab vom Gehweg auf die Fahrbahn ging
es, aber auf der anderen Seite nicht wieder hinauf – an jedem Bordstein eine unsichtbare Wand. Damit war der
KIOSK von der Westseite (U-Bahn-Ausgang, Prolog) nicht erreichbar.

**Behebung (nur diese Ursache):** `player.gd: _try_step_up()` – nach `move_and_slide()` prüft der Spieler per
`test_move` (hoch, vor, runter), ob er auf eine Kante bis `max_step_height` = 0,3 m (`player_config.json`) steigen
kann, und landet nur auf begehbarem Boden. Keine Kollisionsform wurde entfernt oder verändert.

**Nachweis:**
- `tests/integration/p001/kiosk_crossing_test.gd` (neu, 16 Prüfungen) – **vor** der Behebung rot (9 Fehler, „stuck
  at v=9.03, StreetCollision“), danach grün: Westgehweg → Mittelinsel → Ostgehweg → KIOSK benutzen → zurück auf die
  Westseite; geparktes Auto und Hausfassade blockieren weiterhin; Prolog vom U-Bahn-Ausgang zu Fuß bis Erol
  abgeschlossen.
- Gerendert (Godot unter Xvfb): `production/qa/evidence/r9_2/R92_cross_*.png` (Westgehweg, Mittelinsel mit Blick
  auf KIOSK, KIOSK-Menü, Prolog fertig mit Erols Nachricht).
- Der Test schaltet den fließenden Verkehr ab (Autos können den Spieler sonst zufällig blockieren – das ist gewollt)
  und läuft neben den Fußgänger-Spuren.

## 2. BAR-Menü draußen (Priorität 2) – behoben

**Reproduziert** (`tests/integration/p001/ui_state_test.gd`, vor der Behebung 2 Fehler):
- Bar-Menü im Club offen → Spielstand laden, der draußen am KIOSK gespeichert wurde → **„BAR – Was trinkst du?“ auf
  der Straße**, Steuerung gesperrt.
- Bar-Menü offen → Spielstand im Club laden → Menü intern weiter offen, Steuerung gesperrt; danach öffnete der KIOSK
  nicht mehr (Klick schloss nur das „unsichtbare“ Menü).

**Ursachen:**
1. `interactions.gd` ließ **jedes** offene Menü stehen, sobald der nächste Interaktionspunkt „kiosk“ war – auch das
   Bar-Menü.
2. Laden (`save_game.gd`) und Ortswechsel (Club, Wohnung, U-Bahn) schlossen offene Menüs nicht.

**Behebung:** Ein Menü bleibt nur an seinem eigenen Tresen offen (KIOSK-Menü am KIOSK, Bar-Menü an der Bar); neues
`close_all_panels()` beim Betreten/Verlassen von Club, Wohnung und U-Bahn sowie zu Beginn jedes Ladens (Polizei-
kontrollen werden nicht weggeklickt). Test danach 9/9.

Hinweis zum Test: Das Betreten des Clubs speichert automatisch und hatte im ersten Testaufbau den Straßen-Spielstand
überschrieben – das war ein Testfehler, kein Spielfehler, und ist im Test berücksichtigt.

## 3. Performance (Priorität 3)

### Analyse (gemessen, nicht geschätzt)
`tools/perf/render_probe.gd` liest Godots Render-Monitore (Objekte, Draw Calls, Dreiecke pro Bild) an den Orten der
Tablet-Messung. Die Zahl der Draw Calls korreliert mit den Tablet-FPS:

| Ort | Draw Calls vorher | Tablet-FPS (gemeldet) |
|---|---|---|
| Ring (Spawn) | 2761 | 44,7 |
| NACHTFLUG | 1603 | 39,5 |
| KIOSK | 1438 | – |
| Club innen | 477 | – |
| Hbf | 465 | ca. 60 |
| U-Bahn | 145 | 58,7–59,8 |

Aufschlüsselung der Szene (1723 Mesh-Instanzen): **≈ 965 davon Autos** (geparkt 650, Verkehr 315 – das R9-Automodell
bestand aus 27 Einzelteilen). Zusätzlich rendert die **Mond-Lichtquelle nachts eine volle Schattenkarte** (alle Objekte
ein zweites Mal), obwohl der Mondschatten bei Energie 0,06 nicht sichtbar ist.

### Optimierungen (nur diese beiden Engpässe)
1. **Automodell zusammengefasst** (`car_model.gd`): ein Mesh pro Auto mit 2 Flächen (Karosserie über Vertexfarben,
   Lichter), gecacht und von gleichen Autos geteilt; fahrende Autos behalten 4 drehende Räder. Aussehen unverändert.
2. **Mondschatten nachts aus** (`godot_render.json: night.key_shadows=false`); Sonnenschatten am Tag bleiben.

### Ergebnis (Render-Last, gleiche Messpunkte)

| Ort | Draw Calls vorher | nach 1. | nach 1.+2. | Dreiecke vorher → nachher |
|---|---|---|---|---|
| Ring (Spawn) | 2761 | 1304 | **539** (−80 %) | 430 k → 187 k |
| NACHTFLUG | 1603 | 783 | **300** (−81 %) | 369 k → 149 k |
| KIOSK | 1438 | 751 | **326** (−77 %) | 327 k → 148 k |
| Club innen | 477 | 412 | **105** | 344 k → 122 k |
| Hbf | 465 | 465 | **149** | 193 k → 49 k |
| U-Bahn | 145 | 145 | **63** | 18 k → 9 k |

Software-Bildrate (Cloud, ohne Grafikkarte – **keine Tablet-Werte**): Godot/llvmpipe Spawn 1,7 → 3,4 FPS;
Chromium/SwiftShader Hbf (rAF-Zählung, je 2 Läufe) R9.1 0,90/0,89 → R9.2 1,07/1,11 FPS.

**Erwartung, nicht belegt:** Da der Ring jetzt weniger Draw Calls hat als vorher der Hbf (465, ≈ 60 FPS auf dem
Tablet), sollten 40 FPS am Ring und an NACHTFLUG erreichbar sein. **Das muss auf dem Tablet gemessen werden**
(FPS-Knopf, siehe `docs/R9_1_FPS_DISPLAY.md`).

Zur Messung „Straße mit BAR-Menü: 29,1 FPS“: Das war der Fehler aus Abschnitt 2 (Menü hängt, Spieler steht fest);
eine eigene Leistungsursache durch das Menü wurde nicht gefunden – das Menü ist ein kleines UI-Panel.

### Sichtvergleich
`production/qa/evidence/r9_2/R92_visual_parity_vs_R9.png`: gleiche Kameras R9 ↔ R9.2 – kein sichtbarer Unterschied
außer dem fehlenden, kaum wahrnehmbaren Mondschatten der Figur bei Nacht.

## 4. Tests

| Prüfung | Ergebnis |
|---|---|
| Alle Regressionstests | **26 Suites, 408 Prüfungen, grün**, Python OK (`production/qa/evidence/r9_2/tests.log`) |
| Neu: `kiosk_crossing_test` | 16/16 (vorher 9 Fehler) |
| Neu: `ui_state_test` | 9/9 (vorher 2 Fehler) |
| Kompletter Screenshot-Durchlauf | 39 Bilder, geprüft (Ring, Club, Polizei, U-Bahn, Hbf, Prolog) |
| Web-Build Chromium | lädt, Prolog startet, FPS-Anzeige per Touch an/aus |

## 5. Offen
- Tablet-Messung der neuen Werte (Ring, NACHTFLUG, KIOSK, Club).
- Der Verkehr kann den Spieler beim Überqueren weiterhin anfahren/blockieren (gewollt); es gibt keine Ampelphasen.
- Laufen über die Fahrbahn erhöht die Polizei-Aufmerksamkeit (bestehende Regel) – auch im Prolog.

## 6. Build
`build/stray_web_itch.zip`, SHA-256 `783992947f076bbaebbb8a1616d725f9cc4756a1631669ca824c92e8e13db821`.
