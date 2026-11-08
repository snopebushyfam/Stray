#!/usr/bin/env python3
"""Prototype 001 "The Street" -- build the Hohenzollernring data package.

Inputs (downloaded into tools/geodata/cache/ when missing; the cache is gitignored):
  * Geobasis NRW LoD2 tile LoD2_32_355_5645_1_NW.gml   (dl-de/zero-2-0)
  * OpenStreetMap extract of the same area (API 0.6 /map) (ODbL, (c) OSM contributors)

Outputs (committed):
  Content/Stray/Data/LoD2_P001_Hohenzollernring.obj/.mtl/.json  real building geometry
  Content/Stray/Data/P001_Layout.json                           street frame, cross-section,
                                                                 lamps, shopfronts, kiosk,
                                                                 NACHTFLUG, spawn, viewpoints
  docs/prototype-001/*.png                                       data previews (NOT Unreal)

Everything Unreal places is derived here, so the street can be regenerated
reproducibly. What is MEASURED (from data) and what is ASSUMED is written
into P001_Layout.json under "provenance".
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import citygml_extract as cg  # noqa: E402
from dgm import Dgm  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path(__file__).parent / "cache"
TILE = "LoD2_32_355_5645_1_NW.gml"
DGM_TILE = "dgm1_32_355_5645_1_nw_2022.tif"
DGM_URL = "https://www.opengeodata.nrw.de/produkte/geobasis/hm/dgm1_tiff/dgm1_tiff/"
TERRAIN_STEP = 2.0   # metres, terrain mesh resolution
PROFILE_STEP = 3.0   # metres, street profile sampling
# Local origin: a point on the Hohenzollernring, ~120 m south of Friesenplatz.
# Height = median base height of the buildings lining the segment (DHHN2016).
ORIGIN = (355260.0, 5645100.0, 49.25)
OSM_BBOX = (6.9375, 50.9375, 6.9420, 50.9412)  # lon/lat
LOD2_BBOX_LOCAL = (-90.0, -80.0, 90.0, 170.0)    # building centroid filter, local metres
SEGMENT = (-45.0, 105.0)                         # along-street range, 150 m
UA = "STRAY-geodata-pipeline/0.1 (prototype build script)"


def fetch(url: str, dest: Path) -> Path:
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        print(f"download {url}")
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
            f.write(r.read())
    return dest


def to_local(lon, lat):
    import pyproj
    t = pyproj.Transformer.from_crs(4326, 25832, always_xy=True)
    x, y = t.transform(lon, lat)
    return x - ORIGIN[0], y - ORIGIN[1]


def load_osm(path: Path):
    r = ET.parse(path).getroot()
    import pyproj
    t = pyproj.Transformer.from_crs(4326, 25832, always_xy=True)
    nodes = {}
    for n in r.iter("node"):
        x, y = t.transform(float(n.get("lon")), float(n.get("lat")))
        nodes[n.get("id")] = (x - ORIGIN[0], y - ORIGIN[1])
    ways = []
    for w in r.iter("way"):
        tags = {k.get("k"): k.get("v") for k in w.iter("tag")}
        pts = np.array([nodes[n.get("ref")] for n in w.iter("nd") if n.get("ref") in nodes])
        ways.append((w.get("id"), tags, pts))
    return ways


class Frame:
    """Street frame: s = along the street (towards Friesenplatz), v = across (+ = east side)."""

    def __init__(self, origin_en, bearing_deg):
        self.o = np.asarray(origin_en, float)
        b = math.radians(bearing_deg)
        self.bearing = bearing_deg
        self.u = np.array([math.sin(b), math.cos(b)])
        self.v = np.array([self.u[1], -self.u[0]])

    def sv(self, p):
        d = np.asarray(p, float) - self.o
        return d @ self.u, d @ self.v

    def en(self, s, v):
        return self.o + s * self.u + v * self.v


def fit_frame(ways):
    pts = np.vstack([p for _, t, p in ways
                     if t.get("name") == "Hohenzollernring" and t.get("highway") == "primary"
                     and len(p)])
    pts = pts[(pts[:, 1] > -70) & (pts[:, 1] < 125)]
    a, b = np.polyfit(pts[:, 1], pts[:, 0], 1)  # x = a*y + b
    fr = Frame((b, 0.0), math.degrees(math.atan(a)))
    offs = []
    for wid, t, p in ways:
        if t.get("name") == "Hohenzollernring" and t.get("highway") == "primary" and len(p):
            q = p[(p[:, 1] > -70) & (p[:, 1] < 125)]
            if len(q):
                offs.append((wid, t.get("lanes"), float(np.mean([fr.sv(x)[1] for x in q]))))
    return fr, offs


def edges_of(buildings):
    for b in buildings:
        for ring in b["ground_rings_local"]:
            n = len(ring)
            for i in range(n):
                yield b, np.array(ring[i]), np.array(ring[(i + 1) % n])


def facade_hit(fr: Frame, buildings, s, side, vmin=9.5, vmax=40.0):
    """Cast a ray from the street axis at `s` towards `side` (+1 east / -1 west).
    Returns (v, point_en, normal_en_towards_street, building) of the nearest facade."""
    p0 = fr.en(s, 0.0)
    d = fr.v * side
    best = None
    for b, a, c in edges_of(buildings):
        e = c - a
        den = d[0] * (-e[1]) - d[1] * (-e[0])
        if abs(den) < 1e-9:
            continue
        rhs = a - p0
        t = (rhs[0] * (-e[1]) - rhs[1] * (-e[0])) / den
        w = (d[0] * rhs[1] - d[1] * rhs[0]) / den
        if 0 <= w <= 1 and vmin <= t <= vmax and (best is None or t < best[0]):
            n = np.array([e[1], -e[0]]) / np.linalg.norm(e)
            if n @ d > 0:
                n = -n  # face the street
            best = (t, a + w * e, n, b)
    if best is None:
        return None
    t, pt, n, b = best
    return side * t, pt, n, b


def street_profile(dgm: Dgm, fr: Frame, cross: dict, s0: float, s1: float, west_face: float, east_face: float,
                   facade_bases=None):
    """Longitudinal street profile from DGM1, local heights (relative to ORIGIN[2]).
    Per sample: s, road centre, road edge west/east (gutter), sidewalk at the kerb west/east,
    sidewalk at the facade line west/east (cross-fall towards the kerb).
    facade_bases: {side: [(s, building base zmin)]} - the facade height is raised to the
    LoD2 base of the building there, so no wall foot hangs above the pavement.
    Smoothed over 15 m (DGM1 noise, parked cars are not in a DTM but kerbs are only
    partly resolved at 1 m). Kerb height is clamped to a plausible 0.10-0.25 m."""
    k = cross["kerb_half_width"]

    def h(s, v):
        e, n = fr.en(s, v)
        return dgm.sample(ORIGIN[0] + e, ORIGIN[1] + n) - ORIGIN[2]

    def med(s, va, vb):
        return float(np.median([h(s, v) for v in np.arange(min(va, vb), max(va, vb) + 1e-6, 0.5)]))

    ss = np.arange(s0 - PROFILE_STEP, s1 + PROFILE_STEP + 1e-6, PROFILE_STEP)
    def base_at(side, s):
        rows = [z for (sb, z) in (facade_bases or {}).get(side, []) if abs(sb - s) <= 3.0]
        return max(rows) if rows else -1e9

    raw = np.array([[med(s, -1.6, -0.9) * 0.5 + med(s, 0.9, 1.6) * 0.5,
                     med(s, -k + 1.5, -k + 0.3), med(s, k - 1.5, k - 0.3),
                     med(s, -k - 1.0, -k - 2.5), med(s, k + 1.0, k + 2.5),
                     max(med(s, west_face + 0.5, west_face + 1.5), base_at(-1, s)),
                     max(med(s, east_face - 1.5, east_face - 0.5), base_at(+1, s))] for s in ss])
    kern = np.ones(5) / 5
    pad = np.pad(raw, ((2, 2), (0, 0)), mode="edge")
    sm = np.stack([np.convolve(pad[:, i], kern, mode="valid") for i in range(raw.shape[1])], axis=1)
    # Facade heights must not be smoothed below a building base: take the max of the
    # smoothed value and the raw (base-including) value.
    sm[:, 5] = np.maximum(sm[:, 5], raw[:, 5])
    sm[:, 6] = np.maximum(sm[:, 6], raw[:, 6])
    out = []
    for s, (c, ew, ee, ww, we, fw, fe) in zip(ss, sm):
        ew, ee = min(ew, c), min(ee, c)                       # crown: gutters never above the centre
        ww = ew + float(np.clip(ww - ew, 0.10, 0.25))
        we = ee + float(np.clip(we - ee, 0.10, 0.25))
        fw = float(np.clip(fw, ww - 0.05, ww + 0.35))         # cross-fall towards the kerb, bounded
        fe = float(np.clip(fe, we - 0.05, we + 0.35))
        out.append([round(float(s), 2)] + [round(float(x), 3) for x in (c, ew, ee, ww, we, fw, fe)])
    return out


def profile_at(profile, s):
    """Linear interpolation of a profile row at s (clamped)."""
    p = np.asarray(profile)
    return np.array([np.interp(s, p[:, 0], p[:, i]) for i in range(1, p.shape[1])])


def write_terrain(dgm: Dgm, fr: Frame, cross: dict, profile, s0, s1, min_en, max_en, path: Path):
    """DGM1 grid mesh (local frame), carved 0.25 m below the street corridor so the
    street mesh always lies on top. Triangles are CCW seen from above."""
    xs = np.arange(min_en[0], max_en[0] + 1e-6, TERRAIN_STEP)
    ys = np.arange(min_en[1], max_en[1] + 1e-6, TERRAIN_STEP)
    lines = [f"# STRAY DGM1 terrain from {DGM_TILE} (dl-de/zero-2-0), {TERRAIN_STEP:g} m grid",
             f"# Local frame like the LoD2 OBJ: origin EPSG:25832 E={ORIGIN[0]} N={ORIGIN[1]}, DHHN2016 H={ORIGIN[2]}",
             "o Terrain", "usemtl M_Terrain"]
    zmin, zmax, carved = 1e9, -1e9, 0
    for y in ys:
        for x in xs:
            z = dgm.sample(ORIGIN[0] + x, ORIGIN[1] + y) - ORIGIN[2]
            s, v = fr.sv((x, y))
            if s0 - 1.0 <= s <= s1 + 1.0 and cross["sidewalk_west_outer"] - 1.0 <= v <= cross["sidewalk_east_outer"] + 1.0:
                floor_ = float(profile_at(profile, s)[:3].min()) - 0.25
                if z > floor_:
                    z, carved = floor_, carved + 1
            zmin, zmax = min(zmin, z), max(zmax, z)
            lines.append(f"v {x:.3f} {y:.3f} {z:.3f}")
    nx = len(xs)
    for j in range(len(ys) - 1):
        for i in range(nx - 1):
            a, b, c, d = j * nx + i + 1, j * nx + i + 2, (j + 1) * nx + i + 2, (j + 1) * nx + i + 1
            lines.append(f"f {a} {b} {c}")
            lines.append(f"f {a} {c} {d}")
    path.write_text("\n".join(lines) + "\n")
    return {"vertices": nx * len(ys), "triangles": 2 * (nx - 1) * (len(ys) - 1),
            "z_min": round(zmin, 3), "z_max": round(zmax, 3), "carved_vertices": carved}


def r2(x):
    return [round(float(x[0]), 3), round(float(x[1]), 3)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gml", type=Path, default=CACHE / TILE)
    ap.add_argument("--osm", type=Path, default=CACHE / "osm_p001.xml")
    ap.add_argument("--no-preview", action="store_true")
    a = ap.parse_args()

    fetch(cg.BASE_URL + TILE, a.gml)
    fetch(DGM_URL + DGM_TILE, CACHE / DGM_TILE)
    fetch("https://api.openstreetmap.org/api/0.6/map?bbox=%s,%s,%s,%s" % OSM_BBOX, a.osm)

    data_dir = ROOT / "Content/Stray/Data"
    x0, y0, x1, y1 = LOD2_BBOX_LOCAL
    keep = lambda x, y: (ORIGIN[0] + x0 <= x <= ORIGIN[0] + x1) and (ORIGIN[1] + y0 <= y <= ORIGIN[1] + y1)
    bl = cg.read_buildings(a.gml, keep)
    side = cg.write_outputs(bl, data_dir / "LoD2_P001_Hohenzollernring", ORIGIN, TILE,
                            [ORIGIN[0] + x0, ORIGIN[1] + y0, ORIGIN[0] + x1, ORIGIN[1] + y1])
    print(f"LoD2: {side['building_count']} buildings, {side['triangles']}")
    buildings = side["buildings"]

    ways = load_osm(a.osm)
    fr, carriageways = fit_frame(ways)
    print(f"street axis bearing {fr.bearing:.2f} deg, origin E {fr.o[0]:.2f}")

    s0, s1 = SEGMENT
    # --- facades, measured every 3 m on both sides --------------------------------
    facade = {+1: [], -1: []}
    for side_ in (+1, -1):
        for s in np.arange(s0, s1 + 0.1, 3.0):
            h = facade_hit(fr, buildings, s, side_)
            if h:
                facade[side_].append((float(s), h))
    fw = [h[0] for _, h in facade[-1]]
    fe = [h[0] for _, h in facade[+1]]
    west_face, east_face = float(np.median(fw)), float(np.median(fe))
    print(f"facade median west {west_face:.2f}  east {east_face:.2f}")

    # --- cross-section (OSM centrelines measured, widths assumed) ----------------
    cw = sorted(o for _, _, o in carriageways)
    lane_centre = (abs(np.mean([o for o in cw if o < 0])) + np.mean([o for o in cw if o > 0])) / 2
    cross = {
        "median_half_width": 0.6,
        "lane_divider_offset": round(float(lane_centre), 2),   # between the 2 lanes / direction
        "carriageway_half_width": round(float(lane_centre) + 3.4, 2),  # 2 x ~3.4 m lanes
        "kerb_half_width": round(float(lane_centre) + 3.4 + 2.0, 2),   # + parking/loading strip
        "kerb_height": 0.15,
        # p95 of the facade distance + 2 m: slabs run under the buildings, while
        # courtyard entries / gaps (outliers) do not stretch the sidewalk.
        "sidewalk_west_outer": round(-float(np.percentile(np.abs(fw), 95)) - 2.0, 2),
        "sidewalk_east_outer": round(float(np.percentile(fe, 95)) + 2.0, 2),
    }
    kerb = cross["kerb_half_width"]

    # --- real terrain (DGM1): street profile + terrain mesh ------------------------
    dgm = Dgm.from_geotiff(CACHE / DGM_TILE)
    bases = {sd: [(s_, h_[3]["zmin_local"]) for s_, h_ in facade[sd]
                  if abs(h_[0]) <= abs(cross["sidewalk_west_outer" if sd < 0 else "sidewalk_east_outer"])]
             for sd in (-1, +1)}
    profile = street_profile(dgm, fr, cross, s0, s1, west_face, east_face, bases)
    gmin, gmax = [x0 - 10, y0 - 10], [x1 + 10, y1 + 10]
    terrain = write_terrain(dgm, fr, cross, profile, s0, s1, gmin, gmax, data_dir / "DGM1_P001_Terrain.obj")
    pr = np.array(profile)
    print(f"profile: centre {pr[0,1]:+.2f} -> {pr[-1,1]:+.2f} m, kerbs {np.r_[pr[:,4]-pr[:,2], pr[:,5]-pr[:,3]].min():.2f}"
          f"..{np.r_[pr[:,4]-pr[:,2], pr[:,5]-pr[:,3]].max():.2f} m; terrain {terrain}")

    # --- street lamps: both kerbs, staggered ---------------------------------------
    lamps = []
    spacing = 25.0
    for i, s in enumerate(np.arange(s0 + 6.0, s1 - 2.0, spacing)):
        lamps.append({"en": r2(fr.en(s, -(kerb + 0.7))), "arm_dir_en": r2(fr.v), "s": round(float(s), 1)})
        s2 = s + spacing / 2
        if s2 < s1 - 2:
            lamps.append({"en": r2(fr.en(s2, kerb + 0.7)), "arm_dir_en": r2(-fr.v), "s": round(float(s2), 1)})

    # --- feature facades -----------------------------------------------------------
    def feature_at(s, side_, label):
        h = facade_hit(fr, buildings, s, side_)
        assert h, f"no facade found for {label} at s={s}"
        v, pt, n, b = h
        return {"label": label, "s": s, "facade_v": round(float(v), 3), "en": r2(pt), "normal_en": r2(n),
                "building_id": b["id"], "building_height": round(b["zmax_local"] - b["zmin_local"], 2)}

    kiosk = feature_at(48.0, +1, "KIOSK")
    club = feature_at(64.0, -1, "NACHTFLUG")

    rng = random.Random(1408)  # deterministic dressing
    shopfronts, windows = [], []
    for side_ in (+1, -1):
        limit = abs(cross["sidewalk_west_outer"] if side_ < 0 else cross["sidewalk_east_outer"]) - 1.0
        for s, (v, pt, n, b) in facade[side_]:
            if abs(v) > limit:
                continue  # facade set back (gap / courtyard): no dressing floating in the air
            near_feature = any(abs(s - f["s"]) < 6.0 and np.sign(f["facade_v"]) == side_ for f in (kiosk, club))
            height = b["zmax_local"] - b["zmin_local"]
            if int(round(s)) % 9 == 0 and not near_feature and height > 3.5:
                warm = rng.random() < 0.7
                shopfronts.append({"en": r2(pt), "normal_en": r2(n), "s": s, "width": 4.2, "height": 2.8,
                                   "color": [1.0, 0.82, 0.62] if warm else [0.80, 0.90, 1.0]})
            if int(round(s)) % 3 == 0:
                floors = int((height - 4.5) // 3.2)
                for f in range(floors):
                    if rng.random() < 0.28:
                        windows.append({"en": r2(pt), "normal_en": r2(n), "z": round(4.4 + f * 3.2 + 0.9, 2),
                                        "warm": rng.random() < 0.75})

    def view(name, s, v, h, look_s, look_v, look_h):
        p, q = fr.en(s, v), fr.en(look_s, look_v)
        return {"name": name, "en": r2(p), "h": h, "look_en": r2(q), "look_h": look_h}

    layout = {
        "schema": "stray.p001.layout/2",
        "name": "Prototype 001 - The Street (Hohenzollernring, Koeln)",
        "georef": {"crs": "EPSG:25832", "vertical": "DHHN2016",
                   "local_origin_utm": list(ORIGIN),
                   "axes_local": "X=East, Y=North, Z=Up (metres)",
                   "axes_unreal": "UE.X = East*100, UE.Y = -North*100, UE.Z = Up*100 (cm)"},
        "lod2_mesh": "Stray/Data/LoD2_P001_Hohenzollernring.obj",
        "street": {"origin_en": r2(fr.o), "bearing_deg": round(fr.bearing, 3),
                   "s_start": s0, "s_end": s1, **cross,
                   "facade_west_median": round(west_face, 2), "facade_east_median": round(east_face, 2)},
        "terrain_mesh": "Stray/Data/DGM1_P001_Terrain.obj",
        "terrain_stats": terrain,
        "profile": {"columns": ["s", "road_centre", "road_edge_west", "road_edge_east", "sidewalk_west", "sidewalk_east",
                                "facade_west", "facade_east"],
                    "facade_v": [round(west_face, 2), round(east_face, 2)],
                    "note": "heights in metres relative to local_origin_utm[2]; viewpoint/feature heights are above local ground",
                    "samples": profile},
        # Safety plate 1 m below the lowest terrain point (catches any hole; normally invisible).
        "ground_plane": {"min_en": gmin, "max_en": gmax, "z": round(terrain["z_min"] - 1.0, 3)},
        "lamps": {"height": 8.0, "intensity_cd": 1800.0, "temperature_k": 3400.0,
                  "attenuation_radius": 32.0, "outer_cone_deg": 62.0, "cast_shadows": True,
                  "positions": lamps},
        "shopfronts": {"intensity_cd": 220.0, "emissive_nits": 35.0, "items": shopfronts},
        "upper_windows": {"emissive_nits": 6.0, "width": 1.2, "height": 1.5, "items": windows},
        "kiosk": kiosk,
        "club": club,
        "spawn": {"s": 22.0, "v": round(west_face + 4.0, 2), "en": r2(fr.en(22.0, west_face + 4.0)),
                  "yaw_dir_en": r2(fr.u)},
        "viewpoints": [
            view("street_south_overview", s0 + 2, 0.0, 5.0, s0 + 60, 0.0, 3.0),
            view("nachtflug_entrance", club["s"] - 13, club["facade_v"] + 13.0, 1.7, club["s"], club["facade_v"], 2.8),
            view("kiosk_front", kiosk["s"] - 12, kiosk["facade_v"] - 11.0, 1.7, kiosk["s"], kiosk["facade_v"], 2.2),
            view("street_north_to_south", s1 - 4, 2.0, 2.0, s0 + 40, 0.0, 2.0),
            view("high_overview", s0 - 20, 30.0, 40.0, (s0 + s1) / 2, 0.0, 0.0),
        ],
        "lighting": {"night": {"moon_lux": 0.25, "moon_pitch_deg": -28.0, "moon_yaw_deg": 200.0,
                               "skylight_intensity": 1.0, "exposure_min_ev100": -1.5, "exposure_max_ev100": 3.0,
                               "fog_density": 0.012, "fog_inscatter": [0.08, 0.06, 0.05]},
                     "day": {"sun_lux": 75000.0, "sun_pitch_deg": -48.0, "sun_yaw_deg": 155.0,
                             "skylight_intensity": 1.0, "exposure_min_ev100": 10.0, "exposure_max_ev100": 15.0,
                             "fog_density": 0.004, "fog_inscatter": [0.5, 0.6, 0.75]}},
        "provenance": {
            "measured": [
                "building geometry, heights and facade lines: Geobasis NRW LoD2 tile " + TILE,
                "street axis + carriageway centrelines: OpenStreetMap ways named Hohenzollernring (highway=primary)",
                "kiosk facade: ground floor of a real LoD2 building; position chosen near an OSM shop=kiosk node",
                "terrain + street longitudinal profile, crown and kerb heights: Geobasis NRW DGM1 tile " + DGM_TILE],
            "assumed": [
                "lane widths (3.4 m), median (1.2 m), parking strip (2.0 m)",
                "kerb height clamped to 0.10-0.25 m and profile smoothed over 15 m (DGM1 is 1 m resolution)",
                "sidewalk cross-fall: linear from kerb to the median facade line, facade height >= LoD2 base",
                "street lamp positions/spacing/intensity (procedural, NOT from OSM - only few lamps are mapped)",
                "shopfront/window placement and colours (procedural, deterministic seed)",
                "NACHTFLUG and KIOSK signage are fictional; no real business is represented",
                ],
            "osm_carriageway_offsets_m": [[w, l, round(o, 2)] for w, l, o in carriageways],
            "licences": {"lod2": cg.LICENCE, "dgm1": cg.LICENCE,
                         "osm": "ODbL 1.0 - (c) OpenStreetMap contributors (attribution required on release)"}},
    }
    (data_dir / "P001_Layout.json").write_text(json.dumps(layout, indent=1))
    print(f"lamps {len(lamps)}, shopfronts {len(shopfronts)}, windows {len(windows)}")
    print(f"kiosk {kiosk['en']} v={kiosk['facade_v']}  club {club['en']} v={club['facade_v']}  spawn {layout['spawn']}")

    if not a.no_preview:
        import preview_p001
        preview_p001.render(layout, side, ways, ROOT / "docs/prototype-001")


if __name__ == "__main__":
    main()
