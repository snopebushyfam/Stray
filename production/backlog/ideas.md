# STRAY — Ideen- und Detail-Backlog

Gesammelt während der Prototyp-Arbeit. **Regel:** Erst steht das grobe Spiel (siehe
„Rohbau-Roadmap“ unten), dann werden diese Punkte abgearbeitet. Neue Ideen werden hier
angehängt, nicht sofort umgesetzt.

## Rohbau-Roadmap (vor den Details)

| # | Baustein | Warum zuerst |
|---|---|---|
| R1 | Spielstand speichern/laden + Startmenü | Ohne Speichern ist nichts von Leben/Konsequenzen dauerhaft |
| R2 | Wohnung + Schlafen + Tageswechsel + Miete fällig | Schließt den Tageskreislauf (Säule LIFE) |
| R3 | Erster Job (Geld verdienen) | Einnahmen gegen Miete/Ausgaben: der Kern-Loop |
| R4 | Konsequenzen-Grundgerüst: Polizei-Aufmerksamkeit, Ruf wirkt auf NPCs/Preise/Einlass | Säule CONSEQUENCES über den Türsteher hinaus |
| R5 | Zweites Gebiet + Verbindung: Hbf + U-Bahn (Prolog-Ort) | Open World statt eine Straße |
| R6 | Prolog / Einstieg: Ankunft Hbf → Tutorial → U-Bahn → Friesenplatz | Spielbarer Anfang |
| R7 | Tablet/Web-Version veröffentlichen (itch.io oder GitHub Pages) | Testen auf echter Hardware |

## Detail-Ideen (nach dem Rohbau)

### Menschen & Beziehungen
- Lea weiterführen: Nachrichten nach dem Club, Treffen am nächsten Tag, mehrere Dialogschritte
- Persistente NPCs merken sich Begegnungen (Türsteher, Kiosk-Verkäufer, Lea)
- Fußgänger überqueren die Straße (an der Ampel)
- Echte Menschen-Figuren statt Gliederpuppe (Kleidung, Gesicht) – gleiches Rig weiterverwenden
- Spielerfigur: Outfit wählbar (Türsteher bewertet Outfit)

### Nachtleben
- Selbst tanzen (Dance-Animation vorhanden)
- Getränke-Wirkung: ab 3. Kölsch schwankende Kamera, Koffein = schneller, Wasser = nüchterner
- Club: mehr Räume (Toiletten, Raucherbereich, Garderobe), Gästeliste, VIP
- Weitere Bars/Clubs an den Ringen

### Leben & Geld
- Jobs aus der Handy-App annehmbar machen (Kiosk-Nachtschicht, Barback, Lieferfahrer)
- Miete: Fälligkeit, Mahnung, Folgen
- Akku leer → Handy aus (Wirkung des Akkus), Laden in der Wohnung
- Weitere Läden: Restaurant, Fitnessstudio, Fahrschule, Gebrauchtwagenhändler (GDD)

### Verkehr & Straße
- Motorgeräusche der Autos
- Ampelphasen (Autos halten, Fußgänger grün)
- U-Bahn, Taxi, später eigene Fahrzeuge + Führerschein (GDD)
- Nördliche Erweiterung über den Friesenplatz (3dcityloader-Export liegt in `assets/geodata/`)

### Optik & Technik
- KIOSK-Unterzeile wird teils von der Markise verdeckt
- Gebäude/Straße als StaticMesh statt ProceduralMesh (Unreal) / Fassaden-Varianten
- Straßenlampen-Schatten ohne Artefakte (Compatibility-Renderer)
- Phone-Karte: Spielerposition im Club-Innenraum sinnvoll anzeigen
- Unreal-Fassung auf den Godot-Stand bringen (falls Engine-Wechsel zurück)
- gdUnit4 statt eigener Test-Runner (Template-Standard)

### Ton
- Clubmusik/Atmo anhören und abmischen (bisher nur gemessen, nie gehört)
- Echte CC0-Aufnahmen statt Synthese, falls Quelle erreichbar
