"""Consistency checks on the COMMITTED Prototype 001 data (layout + LoD2 + DGM1 terrain).
These are data checks, not an Unreal play test."""
import json
import math
import sys
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "Content" / "Stray" / "Data"
sys.path.insert(0, str(ROOT / "tools" / "geodata"))
from build_p001 import Frame, profile_at  # noqa: E402


def _is_lfs_pointer(p: Path) -> bool:
    return p.read_bytes()[:40].startswith(b"version https://git-lfs")


class P001DataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.L = json.loads((DATA / "P001_Layout.json").read_text())
        cls.lod2 = json.loads((DATA / "LoD2_P001_Hohenzollernring.json").read_text())
        st = cls.L["street"]
        cls.fr = Frame(st["origin_en"], st["bearing_deg"])
        cls.st = st
        cls.profile = cls.L["profile"]["samples"]

    def ground(self, en):
        s, v = self.fr.sv(en)
        c, ew, ee, ww, we, fw, fe = profile_at(self.profile, s)
        k = self.st["kerb_half_width"]
        kw = k + 0.18  # kerb stone width
        vw, ve = self.L["profile"]["facade_v"]
        if v <= -k:
            t = min(max((-v - kw) / max(-vw - kw, 1e-6), 0.0), 1.0)
            return ww + (fw - ww) * t
        if v >= k:
            t = min(max((v - kw) / max(ve - kw, 1e-6), 0.0), 1.0)
            return we + (fe - we) * t
        t = min(abs(v) / k, 1.0)
        return c + ((ew if v < 0 else ee) - c) * t

    def test_frontage_buildings_do_not_float_above_sidewalk(self):
        k = self.st["kerb_half_width"]
        checked = 0
        for b in self.lod2["buildings"]:
            for ring in b["ground_rings_local"]:
                for x, y in ring:
                    s, v = self.fr.sv((x, y))
                    if self.st["s_start"] <= s <= self.st["s_end"] and k < abs(v) < 22:
                        checked += 1
                        self.assertLessEqual(b["zmin_local"], self.ground((x, y)) + 0.05,
                                             f"{b['id']} base {b['zmin_local']} above sidewalk at s={s:.1f}")
        self.assertGreater(checked, 50)

    def test_terrain_is_below_street_inside_corridor(self):
        obj = DATA / "DGM1_P001_Terrain.obj"
        if _is_lfs_pointer(obj):
            self.skipTest("terrain OBJ is an LFS pointer (git lfs pull)")
        n = 0
        for line in obj.read_text().splitlines():
            if line.startswith("v "):
                x, y, z = map(float, line.split()[1:4])
                s, v = self.fr.sv((x, y))
                if self.st["s_start"] <= s <= self.st["s_end"] and \
                        self.st["sidewalk_west_outer"] <= v <= self.st["sidewalk_east_outer"]:
                    n += 1
                    self.assertLessEqual(z, min(profile_at(self.profile, s)[:3]) - 0.2 + 1e-6)
        self.assertGreater(n, 500)

    def test_spawn_is_on_west_sidewalk_inside_segment(self):
        s, v = self.fr.sv(self.L["spawn"]["en"])
        self.assertTrue(self.st["s_start"] < s < self.st["s_end"])
        self.assertTrue(self.st["sidewalk_west_outer"] < v < -self.st["kerb_half_width"])

    def test_profile_kerbs_and_slope_are_plausible(self):
        p = np.array(self.profile)
        kerbs = np.r_[p[:, 4] - p[:, 2], p[:, 5] - p[:, 3]]
        fall = np.r_[p[:, 6] - p[:, 4], p[:, 7] - p[:, 5]]
        self.assertTrue(np.all((fall >= -0.05 - 1e-9) & (fall <= 0.35 + 1e-9)), "sidewalk cross-fall bounded")
        self.assertTrue(np.all((kerbs >= 0.1 - 1e-9) & (kerbs <= 0.25 + 1e-9)))
        fall = p[0, 1] - p[-1, 1]
        self.assertTrue(0.2 < fall < 2.0, fall)
        self.assertLess(np.max(np.abs(np.diff(p[:, 1]))), 0.15, "no steps > 15 cm between 3 m rows")


if __name__ == "__main__":
    unittest.main()
