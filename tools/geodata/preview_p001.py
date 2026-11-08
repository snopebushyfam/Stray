"""Data previews for Prototype 001 -- matplotlib, NOT an Unreal render.

They prove that the geodata conversion and the derived layout line up (scale,
orientation, facades, feature placement). They prove nothing about lighting,
materials, spawning or input in Unreal.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.collections import PolyCollection  # noqa: E402

STAMP = "DATA PREVIEW (matplotlib) - NOT an Unreal render"


def _street_polys(L):
    st = L["street"]
    b = math.radians(st["bearing_deg"])
    u = np.array([math.sin(b), math.cos(b)])
    v = np.array([u[1], -u[0]])
    o = np.array(st["origin_en"])

    def quad(s0, s1, v0, v1):
        return [o + s0 * u + v0 * v, o + s1 * u + v0 * v, o + s1 * u + v1 * v, o + s0 * u + v1 * v]

    s0, s1 = st["s_start"], st["s_end"]
    k = st["kerb_half_width"]
    return {
        "road": quad(s0, s1, -k, k),
        "sw_w": quad(s0, s1, st["sidewalk_west_outer"], -k),
        "sw_e": quad(s0, s1, k, st["sidewalk_east_outer"]),
        "median": quad(s0, s1, -st["median_half_width"], st["median_half_width"]),
    }, u, v, o


def plan(L, sc, ways, out: Path):
    fig, ax = plt.subplots(figsize=(10, 12))
    polys, u, v, o = _street_polys(L)
    for k, c in (("sw_w", "#c9c4bb"), ("sw_e", "#c9c4bb"), ("road", "#55575c"), ("median", "#7a7d82")):
        ax.add_patch(plt.Polygon(polys[k], fc=c, ec="none", zorder=1))
    for b in sc["buildings"]:
        for r in b["ground_rings_local"]:
            if len(r) > 2:
                ax.add_patch(plt.Polygon(r, fc="#e8d9b5", ec="#6b5a3a", lw=.4, alpha=.9, zorder=2))
    for _, t, p in ways:
        if t.get("highway") == "primary" and len(p) > 1:
            ax.plot(p[:, 0], p[:, 1], c="#d33", lw=.8, zorder=3)
    lp = np.array([l["en"] for l in L["lamps"]["positions"]])
    ax.scatter(lp[:, 0], lp[:, 1], s=30, c="#ffb300", ec="k", zorder=5, label="Strassenlampe (prozedural)")
    sf = np.array([s["en"] for s in L["shopfronts"]["items"]])
    ax.scatter(sf[:, 0], sf[:, 1], s=18, marker="s", c="#7fd3ff", ec="k", zorder=5, label="Schaufenster (prozedural)")
    for f, c in ((L["kiosk"], "#00b050"), (L["club"], "#d000d0")):
        p, n = np.array(f["en"]), np.array(f["normal_en"])
        ax.scatter(*p, s=160, marker="*", c=c, ec="k", zorder=6)
        ax.annotate(f["label"], p + n * 4, color=c, fontsize=11, weight="bold", zorder=7)
    sp = np.array(L["spawn"]["en"])
    ax.scatter(*sp, s=120, marker="^", c="#ff2020", ec="k", zorder=6, label="Spawn")
    ax.arrow(*sp, *(np.array(L["spawn"]["yaw_dir_en"]) * 8), width=.4, color="#ff2020", zorder=6)
    for vp in L["viewpoints"]:
        p, q = np.array(vp["en"]), np.array(vp["look_en"])
        ax.annotate("", q, p, arrowprops=dict(arrowstyle="->", color="#444", lw=.8), zorder=4)
        ax.text(*p, vp["name"], fontsize=6, color="#444", zorder=4)
    ax.set_aspect("equal")
    ax.set_xlim(-95, 95)
    ax.set_ylim(-85, 175)
    ax.grid(True, lw=.3)
    ax.set_xlabel("Ost [m] (lokal; Ursprung UTM32 E 355260)")
    ax.set_ylabel("Nord [m] (lokal; Ursprung UTM32 N 5645100)")
    ax.set_title("P001 Hohenzollernring - LoD2-Gebaeude (Geobasis NRW) + OSM-Achse + abgeleitetes Layout\n" + STAMP,
                 fontsize=9)
    ax.legend(loc="lower left", fontsize=7)
    fig.savefig(out, dpi=110, bbox_inches="tight")
    plt.close(fig)


def _load_obj(path: Path):
    V, F = [], []
    mat = None
    for line in path.read_text().splitlines():
        if line.startswith("v "):
            V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("usemtl"):
            mat = line.split()[1]
        elif line.startswith("f "):
            F.append(([int(x) - 1 for x in line.split()[1:4]], mat))
    return np.array(V), F


def perspective(L, obj_path: Path, out: Path, eye_en, eye_h, look_en, look_h, title, fov=70.0):
    V, F = _load_obj(obj_path)
    polys, u, v, o = _street_polys(L)
    tris = []  # (3x3 world pts, rgb)
    sun = np.array([0.4, -0.5, 0.75]); sun /= np.linalg.norm(sun)
    base = {"M_LoD2_wall": np.array([.78, .72, .62]), "M_LoD2_roof": np.array([.55, .38, .32]),
            "M_LoD2_ground": np.array([.3, .3, .3])}
    for idx, m in F:
        p = V[idx]
        n = np.cross(p[1] - p[0], p[2] - p[0])
        ln = np.linalg.norm(n)
        if ln < 1e-9:
            continue
        n /= ln
        tris.append((p, base.get(m, np.ones(3)) * (0.45 + 0.55 * max(0.0, n @ sun))))
    st = L["street"]
    k_ = st["kerb_half_width"]
    strips = (((-k_, k_), 0.0, [.33, .34, .36]), ((st["sidewalk_west_outer"], -k_), 0.15, [.66, .64, .6]),
              ((k_, st["sidewalk_east_outer"]), 0.15, [.66, .64, .6]),
              ((-st["median_half_width"], st["median_half_width"]), 0.12, [.45, .46, .48]))
    for (v0, v1), z, c in strips:  # 3 m pieces so the painter's sort and near clipping behave
        for s_ in np.arange(st["s_start"], st["s_end"], 3.0):
            q = [o + s_ * u + v0 * v, o + (s_ + 3) * u + v0 * v, o + (s_ + 3) * u + v1 * v, o + s_ * u + v1 * v]
            q3 = np.c_[np.array(q), np.full(4, z)]
            tris.append((q3[[0, 1, 2]], np.array(c)))
            tris.append((q3[[0, 2, 3]], np.array(c)))
    for l in L["lamps"]["positions"]:
        p = np.array(l["en"])
        tris.append((np.array([[*p, 0], [*(p + 0.15 * u), 0], [*p, 8.0]]), np.array([.15, .15, .15])))
    eye = np.array([*eye_en, eye_h]); tgt = np.array([*look_en, look_h])
    fwd = tgt - eye; fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 0, 1]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = 1 / math.tan(math.radians(fov) / 2)
    polys2, cols, depth = [], [], []
    for p, c in tris:
        d = p - eye
        z = d @ fwd
        if np.any(z < 0.3):
            continue
        x = (d @ right) / z * f
        y = (d @ up) / z * f
        if np.all(np.abs(x) > 2) or np.all(np.abs(y) > 2):
            continue
        polys2.append(np.c_[x, y]); cols.append(np.clip(c, 0, 1)); depth.append(z.mean())
    order = np.argsort(depth)[::-1]
    fig, ax = plt.subplots(figsize=(12, 6.75))
    ax.set_facecolor("#9db8d3")
    ax.add_collection(PolyCollection([polys2[i] for i in order], facecolors=[cols[i] for i in order],
                                     edgecolors=[cols[i] * .85 for i in order], linewidths=.2))
    for f_ in (L["kiosk"], L["club"]):
        p = np.array([*f_["en"], 3.2]); d = p - eye; z = d @ fwd
        if z > 0.3:
            ax.text((d @ right) / z * f, (d @ up) / z * f, f_["label"], color="w", fontsize=10, weight="bold",
                    ha="center", bbox=dict(fc="#000a", ec="none"))
    ax.set_xlim(-1, 1); ax.set_ylim(-0.5625, 0.5625); ax.set_aspect("equal"); ax.axis("off")
    ax.set_title(title + "\n" + STAMP + " - Tageslicht-Massenmodell, keine Nachtbeleuchtung", fontsize=9)
    fig.savefig(out, dpi=110, bbox_inches="tight")
    plt.close(fig)


def render(L, sc, ways, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    plan(L, sc, ways, out_dir / "p001_plan_preview.png")
    obj = Path(__file__).resolve().parents[2] / "Content" / L["lod2_mesh"]
    for vp in L["viewpoints"]:
        perspective(L, obj, out_dir / f"p001_view_{vp['name']}_preview.png", vp["en"], vp["h"],
                    vp["look_en"], vp["look_h"], f"Viewpoint '{vp['name']}'")
    print(f"previews written to {out_dir}")
