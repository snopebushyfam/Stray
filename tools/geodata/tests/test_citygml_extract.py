"""Unit tests for the LoD2 extractor (run: python3 -m unittest discover tools/geodata/tests)."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent))
import citygml_extract as cg  # noqa: E402

FIXTURE = HERE / "fixtures" / "cube_building.gml"
ORIGIN = (1000.0, 2000.0, 50.0)


def load_obj(path):
    verts, faces = [], []
    mat = None
    for line in Path(path).read_text().splitlines():
        if line.startswith("v "):
            verts.append([float(x) for x in line.split()[1:]])
        elif line.startswith("usemtl"):
            mat = line.split()[1]
        elif line.startswith("f "):
            faces.append(([int(i) - 1 for i in line.split()[1:]], mat))
    return np.array(verts), faces


class ExtractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        keep = lambda x, y: 990 <= x <= 1020 and 1990 <= y <= 2020
        self.buildings = cg.read_buildings(FIXTURE, keep)
        self.side = cg.write_outputs(self.buildings, Path(self.tmp.name) / "box", ORIGIN, FIXTURE.name)
        self.V, self.F = load_obj(Path(self.tmp.name) / "box.obj")

    def tearDown(self):
        self.tmp.cleanup()

    def test_bbox_filter_keeps_only_buildings_inside(self):
        self.assertEqual([b["id"] for b in self.buildings], ["TEST_BOX"])

    def test_local_origin_shifts_coordinates_to_near_zero(self):
        self.assertAlmostEqual(self.V[:, 0].min(), 0.0)
        self.assertAlmostEqual(self.V[:, 0].max(), 10.0)
        self.assertAlmostEqual(self.V[:, 2].min(), 0.0)
        self.assertAlmostEqual(self.V[:, 2].max(), 12.0)

    def test_box_triangulates_to_twelve_triangles(self):
        self.assertEqual(len(self.F), 12)
        self.assertEqual(self.side["triangles"], {"wall": 8, "roof": 2, "ground": 2})

    def test_all_triangle_normals_point_outward(self):
        centre = np.array([5.0, 5.0, 6.0])
        for idx, _ in self.F:
            a, b, c = self.V[idx]
            n = np.cross(b - a, c - a)
            self.assertGreater(n @ ((a + b + c) / 3 - centre), 0, f"inward face {idx}")

    def test_sidecar_records_georeference_and_licence(self):
        sc = json.loads((Path(self.tmp.name) / "box.json").read_text())
        self.assertEqual(sc["local_origin_utm"], list(ORIGIN))
        self.assertIn("dl-de/zero-2-0", sc["source"]["licence"])
        self.assertEqual(sc["buildings"][0]["zmax_local"], 12.0)


class TriangulateTests(unittest.TestCase):
    def test_concave_l_shape_keeps_orientation_and_area(self):
        ring = [(0, 0, 0), (4, 0, 0), (4, 1, 0), (1, 1, 0), (1, 3, 0), (0, 3, 0)]  # CCW, area 6
        tris = cg.triangulate(ring)
        p = np.array(ring, float)
        area = 0.0
        for a, b, c in tris:
            n = np.cross(p[b] - p[a], p[c] - p[a])
            self.assertGreater(n[2], 0)
            area += n[2] / 2
        self.assertAlmostEqual(area, 6.0)

    def test_degenerate_ring_yields_no_triangles(self):
        self.assertEqual(cg.triangulate([(0, 0, 0), (1, 1, 1), (2, 2, 2)]), [])


class UnrealMappingTests(unittest.TestCase):
    """Mirrors StrayObjMesh.cpp: UE = (E, -N, U) * 100 keeps index order; normal = (nx, -ny, nz).
    Checks Unreal's front-face rule normal == (C-A) x (B-A) for the mapped triangle."""

    def test_mapped_triangle_front_face_matches_mapped_normal(self):
        a, b, c = np.array([0, 0, 0.]), np.array([1, 0, 0.]), np.array([0, 1, 0.])  # CCW, +Z
        n = np.cross(b - a, c - a)
        m = lambda v: np.array([v[0], -v[1], v[2]]) * 100
        A, B, C = m(a), m(b), m(c)
        ue_front = np.cross(C - A, B - A)
        n_ue = np.array([n[0], -n[1], n[2]])
        self.assertGreater(ue_front @ n_ue, 0)


if __name__ == "__main__":
    unittest.main()
