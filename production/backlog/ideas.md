# STRAY — Ideen- und Detail-Backlog

Gesammelt während der Prototyp-Arbeit. **Regel:** Erst steht das grobe Spiel (siehe
„Rohbau-Roadmap“ unten), dann werden diese Punkte abgearbeitet. Neue Ideen werden hier
angehängt, nicht sofort umgesetzt.

## Rohbau-Roadmap (vor den Details)

| # | Baustein | Warum zuerst |
|---|---|---|
| R1 ✅ | Spielstand speichern/laden + Startmenü (erledigt 2026-11-09) | Ohne Speichern ist nichts von Leben/Konsequenzen dauerhaft |
| R2 ✅ | Wohnung + Schlafen + Tageswechsel + Miete fällig (erledigt 2026-11-09) | Schließt den Tageskreislauf (Säule LIFE) |
| R3 ✅ | Erster Job (Geld verdienen) (erledigt 2026-11-09) | Einnahmen gegen Miete/Ausgaben: der Kern-Loop |
| R4 ✅ | Konsequenzen-Grundgerüst: Polizei-Aufmerksamkeit, Ruf wirkt auf NPCs/Preise/Einlass (erledigt 2026-11-09) | Säule CONSEQUENCES über den Türsteher hinaus |
| R5 ✅ | Zweites Gebiet + Verbindung: Hbf + U-Bahn (Prolog-Ort) (erledigt 2026-11-09) | Open World statt eine Straße |
| R6 ✅ | Prolog / Einstieg: Ankunft Hbf → Tutorial → U-Bahn → Friesenplatz (erledigt 2026-11-09) | Spielbarer Anfang |
| R7 🟡 | Tablet/Web-Version auf itch.io: Paket + Anleitung fertig (`docs/RELEASE_ITCH.md`, 2026-11-09); Upload + Test auf dem echten Tablet durch dich offen | Testen auf echter Hardware |

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
- Kiosk-Job: Spieler hinter der Theke, Kasse/Wechselgeld als Minispiel, Stammkunden, Diebstahl-Situationen
- Weitere Jobs (Barback NACHTFLUG, Lieferfahrer) mit eigenen Minispielen
- Trinkgeld als Buchung sichtbar machen
- Wohnung einrichten/kaufen, Ersatzwohnung bzw. Obdachlosigkeit nach Räumung, Kaution
- Kamera in kleinen Räumen (Figur steht am Bildrand) – evtl. Ich-Perspektive innen
- Schlafen zu anderen Zeiten (Nickerchen), Müdigkeit als Bedürfnis
- Jobs aus der Handy-App annehmbar machen (Kiosk-Nachtschicht, Barback, Lieferfahrer)
- Miete: Fälligkeit, Mahnung, Folgen
- Akku leer → Handy aus (Wirkung des Akkus), Laden in der Wohnung
- Weitere Läden: Restaurant, Fitnessstudio, Fahrschule, Gebrauchtwagenhändler (GDD)

### Konsequenzen & Polizei
- Polizist:innen als Figuren (aussteigen, Fußstreife), Kamera auf den Streifenwagen bei der Kontrolle
- Ruf wirkt auf Preise (Stammkunden-Rabatt) und Reaktionen der Passant:innen
- Polizeiakte im Handy einsehbar; Bußgeldbescheid per Post/Nachricht
- Weitere Delikte/Situationen (Schlägerei vermeiden, Zeug:in sein)

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

### Hbf & U-Bahn (aus R5)
- Hbf-Halle mit Glasfront/Dachbögen statt Fensterraster; Dom-Fassade detaillierter (Strebewerk, Portal)
- Passant:innen, Taxis, Trankgasse-Verkehr, Reisende mit Koffern am Hbf
- Treppen/Rolltreppen als echte Geometrie statt Teleport; Zug fährt ein/aus, Fahrt mit Innenansicht
- Mehr Stationen/Linien (Appellhofplatz, Neumarkt …), Liniennetzplan im Handy, Monats-/Deutschlandticket
- Phone-Karte für mehrere Gebiete; Ticketpreis vor Release mit VRS-Tarif abgleichen
- Offene Beförderungsentgelte: Mahnung per Post → Inkasso → Konsequenzen
- Echten Friesenplatz-Eingang (s ≈ 108,5) nutzen, sobald der Straßenabschnitt nach Norden verlängert ist

### Prolog (aus R6)
- Ankunft im Zug/auf dem Gleis statt vor der Halle; Bahnhofshalle begehbar
- Zwischensequenz/Kamerafahrt zum Dom beim Start; Prolog überspringen (Menüpunkt)
- Erol als Figur im KIOSK, erstes Gespräch statt nur Nachricht; Schlüssel beim Nachbarn abholen
- Wegweiser-Pfeil / Markierung auf der Handy-Karte für das aktuelle Ziel

### Release (aus R7)
- Upload automatisieren (butler + itch.io-API-Schlüssel, z. B. per GitHub Action)
- Ladebildschirm/Icon im STRAY-Stil statt Godot-Standard; Versionsnummer im Menü
- Touch: Tastatur-Hinweiszeile auf Tablets ausblenden; Knöpfe größer; Kamera-Empfindlichkeit einstellbar

### Speichern
- Mehrere Spielstand-Slots; Speichern im Browser über Neustart hinweg testen
- „Neues Spiel“ fragt nach, bevor ein vorhandener Spielstand überschrieben wird

### Ton
- Clubmusik/Atmo anhören und abmischen (bisher nur gemessen, nie gehört)
- Echte CC0-Aufnahmen statt Synthese, falls Quelle erreichbar
