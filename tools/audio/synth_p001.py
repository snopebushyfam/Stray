#!/usr/bin/env python3
"""Synthesises the Prototype 001 ambience loops (no third-party audio, no licence strings).

  assets/audio/p001/city_ambience_loop.wav  30 s seamless loop: distant traffic rumble,
                                            passing-car swells, faint high-frequency air
  assets/audio/p001/club_bass_loop.wav      8 bars @ 124 BPM, heard through a wall:
                                            kick + offbeat bass + muffled hats, low-passed
  assets/audio/p001/club_music_loop.wav     same groove inside the club: full range, open hats,
                                            clap, minor chord stabs
Deterministic (fixed seeds). Mono, 44.1 kHz, 16 bit.
Run: python3 tools/audio/synth_p001.py   (also prints loudness / spectrum checks)
"""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "p001"


def one_pole_lowpass(x: np.ndarray, cutoff_hz: float) -> np.ndarray:
    a = np.exp(-2.0 * np.pi * cutoff_hz / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):  # small loops (<= 1.4 M samples) - fine for an offline tool
        acc = (1.0 - a) * v + a * acc
        y[i] = acc
    return y


def lowpass(x: np.ndarray, cutoff_hz: float, passes: int = 2) -> np.ndarray:
    """FFT brick-ish low-pass with a smooth roll-off (fast for long signals)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    spec *= 1.0 / (1.0 + (f / cutoff_hz) ** (2 * passes))
    return np.fft.irfft(spec, len(x))


def highpass(x: np.ndarray, cutoff_hz: float) -> np.ndarray:
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    spec *= 1.0 / (1.0 + (cutoff_hz / np.maximum(f, 1e-3)) ** 4)
    return np.fft.irfft(spec, len(x))


def make_loop(x: np.ndarray, fade_s: float = 1.5) -> np.ndarray:
    """Seamless loop: crossfade the tail into the head (equal power)."""
    n = int(fade_s * SR)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    t = np.linspace(0.0, np.pi / 2, n)
    mixed = tail * np.cos(t) + head * np.sin(t)
    return np.concatenate([mixed, body])


def normalise(x: np.ndarray, peak_db: float) -> np.ndarray:
    return x / np.max(np.abs(x)) * 10 ** (peak_db / 20.0)


def write_wav(path: Path, x: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(x * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def city_ambience(seconds: float = 30.0) -> np.ndarray:
    rng = np.random.default_rng(1408)
    n = int((seconds + 1.5) * SR)
    t = np.arange(n) / SR
    rumble = lowpass(rng.standard_normal(n), 180.0, 3) * 1.0          # distant traffic bed
    mid = lowpass(highpass(rng.standard_normal(n), 250.0), 900.0, 3) * 0.12
    air = lowpass(highpass(rng.standard_normal(n), 3000.0), 8000.0) * 0.003            # city "air"
    cars = np.zeros(n)
    for k in range(9):                                                 # passing cars (swells)
        c = rng.uniform(1.0, seconds)
        width = rng.uniform(1.5, 3.5)
        env = np.exp(-0.5 * ((t - c) / width) ** 2)
        swish = lowpass(highpass(rng.standard_normal(n), 120.0), rng.uniform(700, 1400), 2)
        cars += env * swish * rng.uniform(0.6, 1.2)
    slow = 0.85 + 0.15 * np.sin(2 * np.pi * t / 11.0)                 # density breathing
    x = (rumble * 0.9 + mid + cars * 0.5) * slow + air
    return normalise(make_loop(x), -9.0)


def club_bass(bpm: float = 124.0, bars: int = 8, through_wall: bool = True) -> np.ndarray:
    rng = np.random.default_rng(64)
    beat = 60.0 / bpm
    n = int(round(bars * 4 * beat * SR))
    t = np.arange(n) / SR
    x = np.zeros(n)
    kick_len = int(0.35 * SR)
    kt = np.arange(kick_len) / SR
    freq = 45.0 + 75.0 * np.exp(-kt * 28.0)                            # pitch sweep 120 -> 45 Hz
    kick = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-kt * 9.0)
    for b in range(bars * 4):
        i = int(b * beat * SR)
        seg = kick[: max(0, min(kick_len, n - i))]
        x[i:i + len(seg)] += seg
    # Offbeat bass notes (A1 / C2 / G1 pattern), saw through a low-pass.
    notes = [55.0, 55.0, 65.41, 49.0]
    for b in range(bars * 4):
        i = int((b + 0.5) * beat * SR)
        ln = int(0.22 * SR)
        if i + ln > n:
            break
        f0 = notes[(b // 4) % len(notes)]
        bt = np.arange(ln) / SR
        saw = 2.0 * ((bt * f0) % 1.0) - 1.0
        x[i:i + ln] += 0.45 * saw * np.exp(-bt * 6.0)
    hats = np.zeros(n)
    for b in range(bars * 8):
        i = int(b * beat / 2 * SR)
        ln = int(0.05 * SR)
        if i + ln <= n:
            hats[i:i + ln] += rng.standard_normal(ln) * np.exp(-np.arange(ln) / SR * 80.0)
    x += highpass(hats, 6000.0) * (0.08 if through_wall else 0.06)
    if through_wall:
        # "Through the wall": strong low-pass, a little room smear.
        x = lowpass(x, 220.0, 3)
        smear = np.convolve(x, np.exp(-np.arange(int(0.08 * SR)) / (0.02 * SR)), mode="full")[:n]
        x = 0.7 * x + 0.3 * smear / np.max(np.abs(smear))
        return normalise(x, -3.0)
    # Inside: open hats on the offbeat, a minor-chord stab every 2 beats, clap on 2 and 4.
    for b in range(bars * 4):
        i = int((b + 0.5) * beat * SR)
        ln = int(0.12 * SR)
        if i + ln <= n:
            x[i:i + ln] += highpass(rng.standard_normal(ln), 7000.0) * np.exp(-np.arange(ln) / SR * 25.0) * 0.035
        if b % 2 == 1:
            j = int(b * beat * SR)
            cl = int(0.15 * SR)
            if j + cl <= n:
                x[j:j + cl] += lowpass(highpass(rng.standard_normal(cl), 900.0), 3000.0) * np.exp(-np.arange(cl) / SR * 30.0) * 0.35
    chords = [[220.0, 261.63, 329.63], [196.0, 246.94, 293.66], [174.61, 220.0, 261.63], [196.0, 246.94, 329.63]]
    for b in range(0, bars * 4, 2):
        i = int((b + 0.75) * beat * SR)
        ln = int(0.18 * SR)
        if i + ln > n:
            break
        ct = np.arange(ln) / SR
        stab = sum(np.sign(np.sin(2 * np.pi * f * ct)) for f in chords[(b // 8) % len(chords)])
        x[i:i + ln] += lowpass(stab, 1800.0, 2) * np.exp(-ct * 14.0) * 0.12
    x = lowpass(x, 7000.0, 2)                      # tame the top end (club PA, not a hi-fi)
    fade = int(0.004 * SR)                          # 4 ms fade at the loop seam: no click
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    x[:fade] *= np.linspace(0.0, 1.0, fade)
    return normalise(x, -1.5)


def report(name: str, x: np.ndarray) -> None:
    spec = np.abs(np.fft.rfft(x))
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    centroid = float(np.sum(f * spec) / np.sum(spec))
    rms_db = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
    seam = abs(x[-1] - x[0])
    print(f"{name}: {len(x) / SR:.2f} s, peak {20 * np.log10(np.max(np.abs(x))):.1f} dBFS, "
          f"RMS {rms_db:.1f} dBFS, spectral centroid {centroid:.0f} Hz, loop seam step {seam:.4f}")


def main() -> None:
    city = city_ambience()
    club = club_bass()
    inside = club_bass(through_wall=False)
    write_wav(OUT / "city_ambience_loop.wav", city)
    write_wav(OUT / "club_bass_loop.wav", club)
    write_wav(OUT / "club_music_loop.wav", inside)
    report("city_ambience_loop", city)
    report("club_bass_loop", club)
    report("club_music_loop", inside)


if __name__ == "__main__":
    main()
