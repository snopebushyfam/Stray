# STRAY auf itch.io (Web-Version fürs Tablet)

Stand 2026-11-09 (Roadmap R7). Das Paket baut `tools/release/package_itch.sh` →
`build/stray_web_itch.zip` (≈ 13 MB, `index.html` liegt im ZIP-Hauptordner, wie itch.io es verlangt).
Export: Godot 4.7.2 „Web“ **ohne Threads** – braucht daher kein SharedArrayBuffer.

## Geprüft (in der Cloud)
- ZIP entpackt, in einem `<iframe>` geladen (wie itch.io einbettet), Chromium mit Touch-Eingabe:
  Startmenü erscheint, „Neues Spiel“ per Fingertipp startet den Prolog am Hbf, Touch-Steuerung
  (Joystick, Interagieren, Springen, Handy, Menü) ist eingeblendet.
  Belege: `production/qa/evidence/godot/R7_itch_iframe_touch_*.png`.
- **Nicht geprüft:** echtes Tablet (Safari/Chrome auf iPad/Android), Ton, Leistung, ob der Spielstand
  im Browser nach dem Schließen erhalten bleibt, der Upload auf itch.io selbst.

## Hochladen (geht vom Tablet aus, im Browser)
1. ZIP herunterladen (aus dem Chat oder per `tools/release/package_itch.sh` neu bauen).
2. Auf itch.io anmelden (kostenloses Konto) → oben rechts Pfeil → **„Upload new project“**.
3. **Title:** `STRAY` · **Kind of project:** `HTML` · **Classification:** Games.
4. **Uploads:** „Upload files“ → `stray_web_itch.zip` wählen → Häkchen
   **„This file will be played in the browser“**.
5. **Embed options:**
   - Viewport dimensions: `1280` × `720`
   - ✅ **Mobile friendly**, Orientation: **Landscape**
   - ✅ **Fullscreen button**
   - SharedArrayBuffer support: **aus lassen** (nicht nötig)
   - Frame options: „Click to launch in fullscreen“ ist auf dem Tablet empfehlenswert
6. **Visibility & access:** zuerst **Draft** (nur du siehst es, solange du angemeldet bist) oder
   **Restricted** (Link + Passwort für Tester:innen). Erst später **Public**.
7. **Save & view page** → „Run game“ → Vollbild. Erster Start lädt ≈ 13 MB, danach aus dem Cache.

## Pflicht-Hinweise für die Projektbeschreibung (Lizenzen)
```
Gebäude und Gelände: Geobasis NRW (LoD2, DGM1), Datenlizenz Deutschland – Zero – Version 2.0
Straßenmöbel, Eingänge, Laternen: © OpenStreetMap-Mitwirkende, ODbL 1.0 (openstreetmap.org/copyright)
Figur/Animationen: Quaternius „Universal Animation Library“ (CC0) · Schritte: Kenney (CC0)
KIOSK, NACHTFLUG und alle Personen sind frei erfunden.
Prototyp – Platzhaltergrafik, kein originalgetreues Köln.
```

## Neue Version hochladen
`GODOT=… tools/release/package_itch.sh` → auf der itch.io-Seite „Edit game“ → alte ZIP-Datei löschen
oder ersetzen → neue hochladen → wieder „played in the browser“ anhaken → Save.
(Automatisch per `butler` möglich, braucht aber deinen itch.io-API-Schlüssel – später.)
