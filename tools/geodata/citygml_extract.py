#!/usr/bin/env python3
"""Extract a cut-out of LoD2 buildings from a Geobasis NRW CityGML 1.0 tile.

Writes
  * an OBJ mesh in a LOCAL frame (metres; X=East, Y=North, Z=Up; origin = --origin),
    one `o` group per building, material slots M_LoD2_wall / _roof / _ground,
    every triangle wound counter-clockwise seen from outside (outward normal),
  * a JSON sidecar with georeference, source, licence and per-building data.

Why a local frame: UTM northings (~5.6e6 m) stored as float32 lose
centimetre precision. The sidecar keeps the exact UTM origin, so the
georeference is never lost.

CLI:
  citygml_extract.py TILE.gml --bbox XMIN YMIN XMAX YMAX --origin X0 Y0 Z0 --out OUT_BASENAME
Coordinates EPSG:25832 (ETRS89 / UTM 32N); heights DHHN2016 (NHN).
The bbox filters by building centroid.
"""
from __future__ import annotations

import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np

NS = {
    "core": "http://www.opengis.net/citygml/1.0",
    "bldg": "http://www.opengis.net/citygml/building/1.0",
    "gml": "http://www.opengis.net/gml",
    "gen": "http://www.opengis.net/citygml/generics/1.0",
}
SURF = {"WallSurface": "wall", "RoofSurface": "roof", "GroundSurface": "ground"}
LICENCE = "Datenlizenz Deutschland - Zero - Version 2.0 (dl-de/zero-2-0)"
BASE_URL = "https://www.opengeodata.nrw.de/produkte/geobasis/3dg/lod2_gml/lod2_gml/"


def _poslist(el) -> list[tuple[float, float, float]]:
    v = [float(t) for t in el.text.split()]
    pts = [tuple(v[i:i + 3]) for i in range(0, len(v), 3)]
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    return pts


def newell_normal(ring) -> np.ndarray:
    """Area-weighted normal of a 3D polygon (right-handed, CCW => +normal)."""
    p = np.asarray(ring, dtype=np.float64)
    q = np.roll(p, -1, axis=0)
    return np.array([
        np.sum((p[:, 1] - q[:, 1]) * (p[:, 2] + q[:, 2])),
        np.sum((p[:, 2] - q[:, 2]) * (p[:, 0] + q[:, 0])),
        np.sum((p[:, 0] - q[:, 0]) * (p[:, 1] + q[:, 1])),
    ])


def triangulate(ring) -> list[tuple[int, int, int]]:
    """Ear-cut a planar 3D ring; every triangle keeps the ring's orientation."""
    import mapbox_earcut as earcut
    p = np.asarray(ring, dtype=np.float64)
    if len(p) < 3:
        return []
    n = newell_normal(p)
    if not np.any(n):
        return []  # degenerate (zero-area) polygon
    if len(p) == 3:
        tris = [(0, 1, 2)]
    else:
        keep = [i for i in range(3) if i != int(np.argmax(np.abs(n)))]
        idx = earcut.triangulate_float64(p[:, keep], np.array([len(p)], dtype=np.uint32))
        tris = [tuple(int(i) for i in idx[k:k + 3]) for k in range(0, len(idx), 3)]
    out = []
    for a, b, c in tris:
        tn = np.cross(p[b] - p[a], p[c] - p[a])
        out.append((a, b, c) if np.dot(tn, n) >= 0 else (a, c, b))
    return out


def read_buildings(gml_path, keep=None) -> list[dict]:
    """Stream-parse the tile. `keep(cx, cy)` filters by footprint centroid (UTM)."""
    buildings = []
    for _, el in ET.iterparse(str(gml_path), events=("end",)):
        if el.tag != f"{{{NS['bldg']}}}Building":
            continue
        surfs = []
        for tag, kind in SURF.items():
            for s in el.iter(f"{{{NS['bldg']}}}{tag}"):
                for poly in s.iter(f"{{{NS['gml']}}}Polygon"):
                    ext = poly.find("gml:exterior//gml:posList", NS)
                    if ext is not None:
                        surfs.append((kind, _poslist(ext)))
        if surfs:
            pts = np.array([q for _, r in surfs for q in r])
            cx, cy = pts[:, 0].mean(), pts[:, 1].mean()
            if keep is None or keep(cx, cy):
                buildings.append({
                    "id": el.get(f"{{{NS['gml']}}}id"),
                    "function": el.findtext("bldg:function", namespaces=NS),
                    "measuredHeight": el.findtext("bldg:measuredHeight", namespaces=NS),
                    "surfaces": surfs,
                })
        el.clear()
    return buildings


def write_outputs(buildings, out_base, origin, source_name, bbox=None) -> dict:
    """Write OBJ + MTL + JSON sidecar in the local frame; return the sidecar dict."""
    ox, oy, oz = origin
    out = Path(out_base)
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"# STRAY LoD2 cut-out from {source_name} ({LICENCE})",
             f"# Local frame: X=East, Y=North, Z=Up, metres. Origin EPSG:25832 E={ox} N={oy}, DHHN2016 H={oz}",
             "# Triangles are CCW seen from outside (outward normals).",
             f"mtllib {out.name}.mtl"]
    vcount = 0
    stats = {"wall": 0, "roof": 0, "ground": 0}
    meta = []
    for b in buildings:
        lines.append(f"o {b['id']}")
        for kind in ("wall", "roof", "ground"):
            rings = [r for k, r in b["surfaces"] if k == kind]
            if not rings:
                continue
            lines.append(f"usemtl M_LoD2_{kind}")
            for ring in rings:
                tris = triangulate(ring)
                if not tris:
                    continue
                for (x, y, z) in ring:
                    lines.append(f"v {x - ox:.3f} {y - oy:.3f} {z - oz:.3f}")
                for t in tris:
                    lines.append("f " + " ".join(str(vcount + 1 + i) for i in t))
                vcount += len(ring)
                stats[kind] += len(tris)
        zs = [q[2] for _, r in b["surfaces"] for q in r]
        ground = [r for k, r in b["surfaces"] if k == "ground"]
        meta.append({
            "id": b["id"], "function": b["function"], "measuredHeight": b["measuredHeight"],
            "zmin_local": round(min(zs) - oz, 3), "zmax_local": round(max(zs) - oz, 3),
            "ground_rings_local": [[(round(x - ox, 3), round(y - oy, 3)) for (x, y, _) in r] for r in ground],
        })
    out.with_suffix(".obj").write_text("\n".join(lines) + "\n")
    out.with_suffix(".mtl").write_text(
        "newmtl M_LoD2_wall\nKd 0.62 0.58 0.53\n\nnewmtl M_LoD2_roof\nKd 0.30 0.27 0.26\n\n"
        "newmtl M_LoD2_ground\nKd 0.30 0.30 0.30\n")
    sidecar = {
        "source": {"file": source_name, "url": BASE_URL + source_name,
                   "provider": "Geobasis NRW, 3D-Gebaeudemodell LoD2 (CityGML 1.0)",
                   "licence": LICENCE},
        "crs": {"horizontal": "EPSG:25832 (ETRS89 / UTM 32N)", "vertical": "DHHN2016 (NHN)"},
        "selection": "building footprint centroid inside bbox_utm",
        "bbox_utm": bbox,
        "local_origin_utm": [ox, oy, oz],
        "axes": "X=East Y=North Z=Up, metres",
        "building_count": len(buildings), "triangles": stats, "vertices": vcount,
        "buildings": meta,
    }
    out.with_suffix(".json").write_text(json.dumps(sidecar, indent=1))
    return sidecar


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("gml")
    ap.add_argument("--bbox", nargs=4, type=float, required=True)
    ap.add_argument("--origin", nargs=3, type=float, required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    xmin, ymin, xmax, ymax = a.bbox
    bl = read_buildings(a.gml, lambda x, y: xmin <= x <= xmax and ymin <= y <= ymax)
    sc = write_outputs(bl, a.out, a.origin, Path(a.gml).name, a.bbox)
    print(f"{sc['building_count']} buildings, {sc['vertices']} vertices, triangles {sc['triangles']}")


if __name__ == "__main__":
    main()
