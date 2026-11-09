#!/usr/bin/env python3
"""Area P002 "Bahnhofsvorplatz / Domplatte" -- build the Hauptbahnhof data package (Roadmap R5).

Inputs (downloaded into tools/geodata/cache/ when missing; the cache is gitignored):
  * Geobasis NRW LoD2 tile LoD2_32_356_5645_1_NW.gml   (dl-de/zero-2-0)
  * Geobasis NRW DGM1 tile dgm1_32_356_5645_1_nw_2022.tif (dl-de/zero-2-0)
  * OpenStreetMap extract (API 0.6 /map)                 (ODbL, (c) OSM contributors)

Outputs (committed, data/p002/):
  LoD2_P002_Hauptbahnhof.obj/.mtl/.json   real building geometry (Hbf, Dom, Domhotel side ...)
  P002_Area.json                          height grid (DGM1, 1 m), lamps, trees, benches,
                                          U-Bahn + station entrances, spawn, viewpoints

P002 uses the SAME local origin as P001 (UTM 355260 / 5645100, H 49.25), so both areas sit at
their real relative positions in one Godot world (Hbf is ~1.4 km east-north-east of P001).
What is measured and what is assumed is listed under "provenance".
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import citygml_extract as cg  # noqa: E402
from build_p001 import ORIGIN, UA, fetch, load_osm  # noqa: E402,F401
from dgm import Dgm  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path(__file__).parent / "cache"
TILE = "LoD2_32_356_5645_1_NW.gml"
DGM_TILE = "dgm1_32_356_5645_1_nw_2022.tif"
DGM_URL = "https://www.opengeodata.nrw.de/produkte/geobasis/hm/dgm1_tiff/dgm1_tiff/"
OSM_BBOX = (6.9540, 50.9405, 6.9610, 50.9455)  # lon/lat
# Hauptbahnhof (Nominatim 50.9427839 / 6.9590705) in the shared local frame.
HBF = np.array([1358.95, 345.63])
# Walkable area relative to HBF: Bahnhofsvorplatz, Domplatte, Trankgasse, the Dom.
AREA_REL = (-165.0, -190.0, 15.0, -15.0)          # x0, y0, x1, y1 (metres)
LOD2_REL = (-210.0, -235.0, 90.0, 130.0)          # building centroid filter (whole Hbf hall + Dom)
GRID_STEP = 1.0                                   # DGM1 native resolution
LAMP_FILL_SPACING = 22.0                          # procedural lamps where OSM maps none
LAMP_MAX = 30
EXIT_BEYOND_SIGN = 6.0                            # m: the camera (3.8 m behind) stays clear of the stele


def r2(p):
    return [round(float(p[0]), 3), round(float(p[1]), 3)]


def osm_points(path: Path):
    """(tags, local EN) for every tagged OSM node."""
    import xml.etree.ElementTree as ET
    import pyproj
    t = pyproj.Transformer.from_crs(4326, 25832, always_xy=True)
    out = []
    for n in ET.parse(path).getroot().iter("node"):
        tags = {k.get("k"): k.get("v") for k in n.iter("tag")}
        if not tags:
            continue
        x, y = t.transform(float(n.get("lon")), float(n.get("lat")))
        out.append((tags, np.array([x - ORIGIN[0], y - ORIGIN[1]])))
    return out


def point_in_ring(p, ring):
    x, y = p
    inside = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / ((y2 - y1) or 1e-12) + x1:
            inside = not inside
    return inside


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gml", type=Path, default=CACHE / TILE)
    ap.add_argument("--osm", type=Path, default=CACHE / "osm_p002.xml")
    a = ap.parse_args()
    fetch(cg.BASE_URL + TILE, a.gml)
    fetch(DGM_URL + DGM_TILE, CACHE / DGM_TILE)
    fetch("https://api.openstreetmap.org/api/0.6/map?bbox=%s,%s,%s,%s" % OSM_BBOX, a.osm)
    out_dir = ROOT / "data/p002"
    out_dir.mkdir(parents=True, exist_ok=True)

    # --- LoD2 buildings ------------------------------------------------------------------
    lx0, ly0, lx1, ly1 = LOD2_REL
    bx0, by0 = ORIGIN[0] + HBF[0] + lx0, ORIGIN[1] + HBF[1] + ly0
    bx1, by1 = ORIGIN[0] + HBF[0] + lx1, ORIGIN[1] + HBF[1] + ly1
    bl = cg.read_buildings(a.gml, lambda x, y: bx0 <= x <= bx1 and by0 <= y <= by1)
    side = cg.write_outputs(bl, out_dir / "LoD2_P002_Hauptbahnhof", ORIGIN, TILE, [bx0, by0, bx1, by1])
    print(f"LoD2: {side['building_count']} buildings, {side['triangles']}")
    footprints = [r for b in side["buildings"] for r in b["ground_rings_local"]]

    def in_building(p, margin=0.0):
        if margin <= 0.0:
            return any(point_in_ring(p, r) for r in footprints)
        for dx, dy in ((0, 0), (margin, 0), (-margin, 0), (0, margin), (0, -margin)):
            if any(point_in_ring((p[0] + dx, p[1] + dy), r) for r in footprints):
                return True
        return False

    # --- DGM1 height grid ------------------------------------------------------------------
    ax0, ay0, ax1, ay1 = AREA_REL
    gmin = HBF + np.array([ax0, ay0])
    gmax = HBF + np.array([ax1, ay1])
    dgm = Dgm.from_geotiff(CACHE / DGM_TILE)
    xs = np.arange(gmin[0], gmax[0] + 1e-6, GRID_STEP)
    ys = np.arange(gmin[1], gmax[1] + 1e-6, GRID_STEP)
    z = np.array([[dgm.sample(ORIGIN[0] + x, ORIGIN[1] + y) - ORIGIN[2] for x in xs] for y in ys])
    print(f"grid {len(xs)} x {len(ys)}  z {z.min():.2f} .. {z.max():.2f} m")

    def ground(p):
        i = (p[0] - gmin[0]) / GRID_STEP
        j = (p[1] - gmin[1]) / GRID_STEP
        i0, j0 = int(min(max(math.floor(i), 0), len(xs) - 2)), int(min(max(math.floor(j), 0), len(ys) - 2))
        fi, fj = i - i0, j - j0
        return float(z[j0, i0] * (1 - fi) * (1 - fj) + z[j0, i0 + 1] * fi * (1 - fj)
                     + z[j0 + 1, i0] * (1 - fi) * fj + z[j0 + 1, i0 + 1] * fi * fj)

    def inside_area(p, margin=3.0):
        return gmin[0] + margin <= p[0] <= gmax[0] - margin and gmin[1] + margin <= p[1] <= gmax[1] - margin

    # --- OSM features ------------------------------------------------------------------------
    nodes = osm_points(a.osm)
    lamps, trees, benches, bins, ubahn, station = [], [], [], [], [], []
    for tags, p in nodes:
        if not inside_area(p, 1.0):
            continue
        lvl = str(tags.get("level", "0"))
        if tags.get("highway") == "street_lamp" and lvl in ("0", "") and not in_building(p):
            lamps.append({"en": r2(p), "source": "osm"})
        elif tags.get("natural") == "tree" and not in_building(p, 1.5):
            trees.append({"en": r2(p)})
        elif tags.get("amenity") == "bench" and lvl in ("0", "") and not in_building(p):
            benches.append({"en": r2(p)})
        elif tags.get("amenity") == "waste_basket" and lvl in ("0", "") and not in_building(p):
            bins.append({"en": r2(p)})
        elif tags.get("railway") == "subway_entrance" and tags.get("layer", "0") == "0":
            ubahn.append({"en": r2(p), "name": tags.get("name", ""), "level": lvl})
        elif tags.get("railway") == "train_station_entrance" and "name" in tags:
            station.append({"en": r2(p), "name": tags["name"]})
    n_osm = len(lamps)
    # Procedural fill: the plaza and Domplatte have almost no mapped lamps.
    for y in np.arange(gmin[1] + 8, gmax[1] - 6, LAMP_FILL_SPACING):
        for x in np.arange(gmin[0] + 8, gmax[0] - 6, LAMP_FILL_SPACING):
            p = np.array([x, y])
            if len(lamps) >= LAMP_MAX:
                break
            if in_building(p, 3.0) or any(np.hypot(*(p - np.array(l["en"]))) < 15.0 for l in lamps):
                continue
            lamps.append({"en": r2(p), "source": "procedural"})
    print(f"lamps {n_osm} osm + {len(lamps) - n_osm} procedural, trees {len(trees)}, benches {len(benches)}, "
          f"bins {len(bins)}, ubahn {len(ubahn)}, station entrances {len(station)}")

    # Player's U-Bahn entrance: the mapped "Dom/Hbf" entrance on the Bahnhofsvorplatz, nearest to
    # the Hbf main exit "Bahnhofsvorplatz/Domseite".
    main_exit = min((s for s in station if "Domseite" in s["name"]),
                    key=lambda s: np.hypot(*(np.array(s["en"]) - HBF)))
    use = min((u for u in ubahn if u["name"].startswith("Dom/H")),
              key=lambda u: np.hypot(*(np.array(u["en"]) - np.array(main_exit["en"]))))
    ue = np.array(use["en"])
    dom = HBF + np.array([-110.0, -150.0])          # Dom choir/nave, from LoD2 footprint
    to_dom = (dom - ue) / np.linalg.norm(dom - ue)
    # LoD2 and OSM disagree by a few metres at the hall front (the entrance node falls inside the
    # Hbf footprint): walk towards the Dom until clear of every footprint, then 2.5 m further.
    step = 0.0
    while in_building(ue + to_dom * step, 1.5):
        step += 0.5
        assert step < 30.0, "no free spot near the U-Bahn entrance"
    sign_p = ue + to_dom * step
    exit_p = ue + to_dom * (step + EXIT_BEYOND_SIGN)
    print(f"U-Bahn entrance moved {step:.1f} m out of the LoD2 footprint")
    me = np.array(main_exit["en"])
    out_n = (me - HBF) / np.linalg.norm(me - HBF)   # away from the hall
    door_step = 0.0
    while in_building(me + out_n * door_step, 0.5):
        door_step += 0.5
        assert door_step < 30.0, "no free spot in front of the Hbf exit"
    door_p = me + out_n * door_step

    area = {
        "schema": "stray.p002.area/1",
        "name": "Area P002 - Bahnhofsvorplatz / Domplatte (Koeln Hbf)",
        "georef": {"crs": "EPSG:25832", "vertical": "DHHN2016", "local_origin_utm": list(ORIGIN),
                   "axes_local": "X=East, Y=North, Z=Up (metres); same frame as P001"},
        "lod2_mesh": "LoD2_P002_Hauptbahnhof.obj",
        "hbf_en": r2(HBF),
        "height_grid": {"min_en": r2(gmin), "step": GRID_STEP, "nx": len(xs), "ny": len(ys),
                        "z_min": round(float(z.min()), 3), "z_max": round(float(z.max()), 3),
                        "note": "row-major, row j = north index (y = min_en.y + j*step), metres above origin H",
                        "z": [round(float(v), 2) for v in z.ravel()]},
        "bounds_margin": 2.0,
        "lamps": {"height": 7.0, "items": lamps},
        "trees": trees,
        "benches": benches,
        "waste_baskets": bins,
        "ubahn_entrances": ubahn,
        "station_entrances": station,
        "ubahn_player": {"name": use["name"], "osm_en": use["en"], "en": r2(sign_p), "shift_m": step, "exit_en": r2(exit_p), "exit_dir_en": r2(to_dom)},
        "hbf_main_exit": {"name": main_exit["name"], "osm_en": main_exit["en"], "en": r2(door_p),
                          "shift_m": door_step, "normal_en": r2(out_n)},
        "spawn": {"en": r2(exit_p), "yaw_dir_en": r2(to_dom)},
        "viewpoints": [
            {"name": "hbf_vorplatz", "en": r2(ue + to_dom * 22.0 + np.array([6.0, 0.0])), "h": 1.7,
             "look_en": r2(door_p), "look_h": 6.0},
            {"name": "dom_from_vorplatz", "en": r2(door_p + out_n * 8.0), "h": 1.7,
             "look_en": r2(dom), "look_h": 25.0},
            {"name": "hbf_overview", "en": r2(HBF + np.array([-60.0, -40.0])), "h": 70.0,
             "look_en": r2(HBF + np.array([-110.0, -140.0])), "look_h": 0.0},
        ],
        "provenance": {
            "measured": [
                "buildings incl. Hauptbahnhof and Dom: Geobasis NRW LoD2 tile " + TILE,
                "ground heights (1 m grid): Geobasis NRW DGM1 tile " + DGM_TILE,
                "street lamps (level 0), trees, benches, waste baskets, U-Bahn and station entrances: OSM nodes",
                "Hbf reference point: Nominatim (OSM) 50.9427839 N / 6.9590705 E"],
            "assumed": [
                "procedural lamps on a %g m grid where OSM maps none (marked source=procedural)" % LAMP_FILL_SPACING,
                "U-Bahn entrance sign/exit: mapped node moved towards the Dom until clear of the LoD2 Hbf footprint "
                "(shift_m), exit %g m further;" % EXIT_BEYOND_SIGN + " stair direction is not mapped",
                "Dom reference point for viewpoints (from the LoD2 footprint, approximate)",
                "DGM1 is bare ground: the Domplatte plateau and the Trankgasse level are as surveyed, "
                "stairs/ramps between them are not modelled separately"],
            "licences": {"lod2": cg.LICENCE, "dgm1": cg.LICENCE,
                         "osm": "ODbL 1.0 - (c) OpenStreetMap contributors (attribution required on release)"}},
    }
    (out_dir / "P002_Area.json").write_text(json.dumps(area, separators=(",", ":")))
    print("ubahn_player", area["ubahn_player"])
    print("hbf_main_exit", area["hbf_main_exit"])


if __name__ == "__main__":
    random.seed(0)
    main()
