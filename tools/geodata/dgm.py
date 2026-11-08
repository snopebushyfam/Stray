"""Geobasis NRW DGM1 (1 m digital terrain model, GeoTIFF) reader + bilinear sampler.

Tiles: https://www.opengeodata.nrw.de/produkte/geobasis/hm/dgm1_tiff/dgm1_tiff/
Licence: dl-de/zero-2-0. CRS EPSG:25832, heights DHHN2016 (NHN).
The NRW tiles are PixelIsArea: the tie point is the upper-left CORNER of pixel (0, 0),
so pixel (row, col) has its centre at (E0 + col + 0.5, N0 - row - 0.5).
"""
from __future__ import annotations

import math

import numpy as np


class Dgm:
    def __init__(self, heights: np.ndarray, east0: float, north0: float, pixel: float = 1.0, nodata: float = -9999.0):
        self.h = np.asarray(heights, dtype=np.float64)
        self.e0, self.n0, self.px = east0, north0, pixel
        self.nodata = nodata

    @classmethod
    def from_geotiff(cls, path) -> "Dgm":
        import tifffile
        with tifffile.TiffFile(str(path)) as t:
            page = t.pages[0]
            tags = {tag.name: tag.value for tag in page.tags.values()}
            arr = page.asarray()
        tie = tags["ModelTiepointTag"]
        scale = tags["ModelPixelScaleTag"]
        if tie[0] != 0 or tie[1] != 0 or abs(scale[0] - scale[1]) > 1e-9:
            raise ValueError("unsupported GeoTIFF layout (expect tie point at pixel 0,0 and square pixels)")
        nodata = float(tags.get("GDAL_NODATA", "-9999"))
        return cls(arr, tie[3], tie[4], scale[0], nodata)

    def sample(self, east: float, north: float) -> float:
        """Bilinear height (NHN metres) at a UTM position."""
        c = (east - self.e0) / self.px - 0.5
        r = (self.n0 - north) / self.px - 0.5
        c0, r0 = int(math.floor(c)), int(math.floor(r))
        if c0 < 0 or r0 < 0 or c0 + 1 >= self.h.shape[1] or r0 + 1 >= self.h.shape[0]:
            raise ValueError(f"position {east:.1f},{north:.1f} outside the DGM tile")
        fc, fr = c - c0, r - r0
        q = self.h[r0:r0 + 2, c0:c0 + 2]
        if np.any(q == self.nodata):
            raise ValueError(f"no-data at {east:.1f},{north:.1f}")
        return float(q[0, 0] * (1 - fc) * (1 - fr) + q[0, 1] * fc * (1 - fr)
                     + q[1, 0] * (1 - fc) * fr + q[1, 1] * fc * fr)
