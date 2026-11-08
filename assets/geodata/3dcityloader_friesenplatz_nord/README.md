# 3dcityloader-Export „Friesenplatz Nord“ (vom Projektinhaber, 2026-11-08)

Quelle: v2.3dcityloader.com, kostenloser Export. Laut Exportseite: Bereich „Hohenzollernring 93“,
BBOX (WGS84) 6.9394118,50.9410805 – 6.9412193,50.9429027, Fläche 0,03 km², EPSG:25832,
DGM1-Gelände (1 m), Kartentextur (0,20 m), LoD2-Gebäude NRW.

| Datei | Inhalt |
|---|---|
| `3dcityloader_a32da23c_friesenplatz_nord.dxf` | 3DFACE-Flächen: Layer `lod-2-buildings-nrw` (2.203), `terrain` (1.917); lokale Meter, X = Ost, Y = Nord |
| `texture.jpg` + `texture.wld` | Kartentextur aus **OSM-Daten** (kein Luftbild), 664 × 996 px, 0,1997 m/px |
| `ATTRIBUTION.txt` | Original-Lizenzhinweise (LoD2/DGM: dl-de/zero-2-0; Textur: ODbL, © OSM-Mitwirkende) |

## Georeferenz (von Claude gemessen, nicht im Export enthalten)

Durch Abgleich der Gebäude-Eckpunkte mit der amtlichen Kachel `LoD2_32_355_5645_1_NW.gml`:

* DXF-Ursprung (0, 0) = **UTM32 E 355232,703 / N 5645294,630** (1.006 Eckpunkte passen danach mit 0,000 m Abstand).
  Die World-Datei der Textur liegt 0,1 m daneben (E 355232,803 / N 5645294,530 unten links).
* Höhe: DXF z = 0 entspricht ca. **45,43 m NHN** (Geländeminimum). Gebäude streuen ±1 m
  gegen die amtlichen Höhen — der Konverter setzt sie vermutlich auf sein Gelände.
* Lage: ca. 90–290 m **nördlich** des P001-Abschnitts (P001-lokal x −27…105, y 195…394), kein Überlapp.
* Geländebeule bis +6 m bei DXF x 92–116 / y 9–33: ungeklärt (DGM-Artefakt oder Baugrube).

## Verwendung

Noch **nicht** im Spiel verwendet. Vorgesehen für die nördliche Erweiterung über den Friesenplatz.
P001 nutzt dieselben amtlichen Quellen direkt (LoD2 + DGM1 über `tools/geodata/build_p001.py`).
