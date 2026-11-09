# STRAY — Game Design Brief v0.1

## Identität
Arbeitstitel: **STRAY** — ein eigenständiges Third-Person-Open-World-Life-/Nightlife-RPG in einer komprimierten, fiktionalisierten Interpretation von Köln.

## Spielerfantasie
Du kommst neu nach Köln. Niemand kennt dich, du musst Geld verdienen, Kontakte knüpfen, deinen Alltag organisieren und entscheidest, wie dein Leben zwischen Arbeit, Nachtleben, Geld und sozialem Status verläuft.

## Spielsäulen
1. **Nightlife** — Begegnungen, Clubs, Bars, Kioske, Samstagabend in den Ringen.
2. **Life** — Wohnung, Arbeit, Geld, Smartphone, Einkäufe, Mobilität.
3. **Consequences** — soziale Reputation, Polizei-Aufmerksamkeit, finanzielle und zwischenmenschliche Folgen.

## Geografische Prioritäten
- **Friesenplatz / Hohenzollernring / Kölner Ringe**: zentrale Open-World-Startzone.
- **NACHTFLUG und KIOSK**: erkennbare Orte der ersten Straßenprobe.
- **Köln Hauptbahnhof und U-Bahn**: geplante Prolog-Erweiterung.
- Später erweiterbare Innenräume: Wohnung, Club, Bar, Restaurant, Fitnessstudio, Fahrschule, Gebrauchtwagenhändler.

## Spielbeginn (Vision)
Ankunft am Kölner Hauptbahnhof, kurzes Steuerungs-/Interaktions-Tutorial, mit der U-Bahn zum Friesenplatz; erste Kontakte und Erkundung an einem Samstagabend. Die v0.1-Zeitscheibe verläuft bis Sonntagmorgen.

## Vision für Systeme
- Third-Person-Laufen, Kamera, Interaktion
- NPCs: Ambient, Interactive, Persistent
- Smartphone: Messenger, Maps, Bank, Jobs, Kontakte
- Bargeld, Konto, Job, Miete und Käufe
- Reputationen: Social / Nightlife / Police Attention
- ÖPNV, Taxi, Verkehr, später eigene Fahrzeuge/Führerschein
- Entscheidungsketten mit lokalen und längerfristigen Konsequenzen

## Entwicklungsstrategie
Die vollständige Vision ist **nicht** der erste Lieferumfang. Erst eine belegbar spielbare, schöne Straße bei Nacht. Danach NPCs / Verkehr; dann Nachtflug / Kiosk / Innenräume; dann Smartphone / Geld / Life-Simulation; dann Hbf-Prolog.

## Prototype 001: The Street — Abnahmekriterien
- Reale Third-Person-Steuerung im korrekt ausgewählten Unreal-Ziel-Level
- 150 m glaubwürdige Straße, Gehwege und Gebäude im richtigen Maßstab
- Club-Eingang NACHTFLUG, KIOSK, Licht bei Nacht, funktionierende Materialien
- Korrekte Kollision / Spawn-Punkt, keine schwebenden Actors
- Bildliche Sichtprüfung am echten Spiel oder dokumentiertes UNVERIFIZIERT, falls keine GUI/Engine vorhanden

## Stil
Realistische Gegenwartsstadt Köln bei Nacht. Keine Cartoon-Optik. Stimmige Schilder, Licht, Verkehr und Fußgänger; realistische Dichte, aber für die Technik sinnvolle Optimierung.

## Prototype 001 — Umsetzungsstand (2026-11-08)
- Ort: **Hohenzollernring, 150 m** (s = −45 … +105 m) südlich des Friesenplatzes; reale
  Gebäude aus Geobasis-NRW-LoD2, reales Gelände/Gefälle aus DGM1, Straßenachse aus OpenStreetMap.
- KIOSK: Ostseite, s = 48 m. NACHTFLUG: Westseite, s = 64 m, schräg gegenüber.
- Spawn: Westgehweg, s = 22 m, Blick nach Norden; NACHTFLUG liegt voraus links, KIOSK gegenüber.
- Steuerung: WASD/Maus bzw. Gamepad, Shift = rennen, Leertaste = springen, **N = Tag/Nacht**.
- Status: **in Godot 4.7 gespielt und getestet** (Cloud, Desktop + Web). Unreal-Fassung unverifiziert.
- Touch: virtueller Joystick links, Wischen rechts = Kamera, Buttons für Springen und Tag/Nacht.

## Schritt 3 — erste Systeme (2026-11-08)
- **LIFE:** Bargeld (Start 35 €), KIOSK mit 5 Artikeln.
- **NIGHTLIFE / CONSEQUENCES:** Türsteher am NACHTFLUG entscheidet nach Uhrzeit, Anstehen, Alkohol,
  Eintrittsgeld (15 €) und Ruf; Nerven, Abweisung und Einlass verändern den Ruf „Nachtleben“.
- Regeln und Texte: `data/p001/economy_config.json`.

## Schritt 4 — Smartphone (2026-11-08)
- Spielzeit Samstagnacht (10 × Echtzeit), Club 23–6 Uhr; Licht folgt der Uhr.
- Handy-Apps: Bank (Konto 120 € + Bargeld, Buchungen), Karte (echte Grundrisse), Nachrichten
  (ereignisgesteuert), Kontakte, Jobs (Vorschau). Geldautomaten an echten OSM-Standorten.
- Daten: `data/p001/phone_config.json`.

## Club-Innenraum NACHTFLUG (2026-11-08)
- Tanzfläche, Bar mit Clubpreisen, DJ, 12 Tanzende; Lea als erste Person mit Gedächtnis-Anlage
  (Dialog wirkt auf sozialen Ruf, Name landet in den Kontakten).
- Daten: `data/p001/club_interior.json`.

## R2 — Wohnung, Schlafen, Miete (2026-11-09)
- Eigene Wohnung hinter einer echten Haustür (OSM) am Ring; Schlafen bis 10 Uhr = neuer Tag.
- Kalender ab Sa 14.11.; Miete 450 € am 1. per Dauerauftrag; Mahnung, nach 3 Tagen Frist Räumung.

## R3 — Erster Job (2026-11-09)
- Aushilfe im KIOSK: Bewerbung per Handy, Schicht 18–22 Uhr, 8 Kund:innen bedienen, 54 € Lohn + Trinkgeld.
- Unpünktlich/Fehler/Schwänzen → Abmahnung, zweite → Kündigung. Daten: `data/p001/jobs_config.json`.

## R4 — Konsequenzen (2026-11-09)
- Polizei-Aufmerksamkeit aus Verhalten (Fahrbahn, Alkohol, Diebstahl, Türsteher nerven, weglaufen).
- Streifenwagen kontrolliert: Verwarnung → Bußgeld → Platzverweis → Festnahme; Polizeiakte.
- Klauen im Kiosk mit dauerhaftem Hausverbot und Jobverlust; Türsteher reagiert auf Polizei-Ärger.

## R5 — Hauptbahnhof + U-Bahn (2026-11-09)
- Zweites Gebiet am echten Ort: Bahnhofsvorplatz und Domplatte mit Hauptbahnhof und Dom (Geobasis NRW, OSM).
- U-Bahn Linie 5 Friesenplatz ↔ Dom/Hbf: Ticket am Automaten (3,80 €, angenommen) oder schwarzfahren
  (Kontrolle 25 %, 60 € erhöhtes Beförderungsentgelt). Fahrt kostet 7 Minuten Spielzeit.
- Grundlage für den Prolog (R6): Ankunft am Hbf → U-Bahn → Friesenplatz.

