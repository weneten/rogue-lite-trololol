"""Buffers, timing and WAV output.

Everything downstream works in float32 and only becomes 16-bit integers in
:func:`write_wav`, so a track can be mixed, filtered and re-gained any number
of times without stacking quantisation noise.

The one non-obvious idea here is :class:`Loop`. Game music is played on repeat
forever, so a track that simply stops at the last bar clicks every time it
wraps and throws away its own reverb tail. A Loop renders `length + tail`
seconds and then folds the overhang back onto the start, so the decay of the
final chord is already ringing under the first beat when the loop comes round.
"""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

# 32 kHz, not 44.1. The whole soundtrack ships inside a web build, and at these
# timbres (organ, choir, taiko, strings) the 16 kHz ceiling costs almost
# nothing audible while cutting every file by a third.
SR = 32000

# Stereo throughout: a mono bed under a mono combat layer left no room to place
# anything, and these tracks lean on width to keep six voices legible.
CHANNELS = 2


def seconds(n: int) -> float:
    return n / SR


def samples(t: float) -> int:
    return int(round(t * SR))


def db(x: float) -> float:
    """Decibels to linear gain."""
    return float(10.0 ** (x / 20.0))


def silence(n: int) -> np.ndarray:
    return np.zeros((n, CHANNELS), dtype=np.float64)


def to_stereo(mono: np.ndarray, pan: float = 0.0) -> np.ndarray:
    """Constant-power pan. `pan` is -1 hard left to +1 hard right."""
    angle = (np.clip(pan, -1.0, 1.0) + 1.0) * 0.25 * np.pi
    return np.stack([mono * np.cos(angle), mono * np.sin(angle)], axis=1) * np.sqrt(2.0)


class Loop:
    """A fixed-length stereo canvas that wraps.

    Voices are stamped in at absolute times with :meth:`add`. Anything that
    runs past the end lands in the tail region, and :meth:`resolve` adds that
    tail back over the opening — which is what makes the seam inaudible.
    """

    def __init__(self, length: float, tail: float = 4.0) -> None:
        self.length = samples(length)
        self.tail = samples(tail)
        self.buf = silence(self.length + self.tail)

    def add(self, mono: np.ndarray, at: float, gain: float = 1.0, pan: float = 0.0) -> None:
        if mono.size == 0:
            return

        start = samples(at)
        if start < 0:
            mono = mono[-start:]
            start = 0
        if start >= self.buf.shape[0]:
            return

        chunk = mono[: self.buf.shape[0] - start]
        self.buf[start : start + chunk.size] += to_stereo(chunk, pan) * gain

    def add_stereo(self, stereo: np.ndarray, at: float = 0.0, gain: float = 1.0) -> None:
        start = samples(at)
        if start >= self.buf.shape[0]:
            return

        chunk = stereo[: self.buf.shape[0] - start]
        self.buf[start : start + chunk.shape[0]] += chunk * gain

    def resolve(self) -> np.ndarray:
        """Fold the tail over the head and return exactly `length` samples."""
        out = self.buf[: self.length].copy()
        tail = self.buf[self.length :]
        n = min(tail.shape[0], out.shape[0])
        out[:n] += tail[:n]
        return out


def master(buf: np.ndarray, peak: float = 0.89, threshold: float = 0.4) -> np.ndarray:
    """Final bus: rumble filter, limiter, gentle saturation, fixed headroom.

    The rumble filter matters more than it looks. Layered organ pedals and
    kick drums leave a slow DC wander that costs real headroom and puts a step
    in the waveform at the loop point — a click, once per loop, forever.

    The limiter is what lets the drum layer sit at the same apparent level as
    the string layer it plays under: peak-normalising alone leaves a track full
    of transients far quieter than a track full of sustained chords, and
    AudioManager crossfades between exactly those two things.
    """
    from . import dsp  # local: dsp imports core for SR

    out = np.stack([dsp.highpass(buf[:, ch], 30.0) for ch in range(CHANNELS)], axis=1)
    out = normalize(out, 1.0)
    out = dsp.limit(out, threshold=threshold)
    out = dsp.soft_clip(out, drive=1.2)
    return normalize(out, peak)


def normalize(buf: np.ndarray, peak: float = 0.89) -> np.ndarray:
    """Scale to a fixed headroom.

    Fixed rather than per-track loudness matching: the crossfades in
    AudioManager assume the beds sit at comparable levels, so every track is
    mastered to the same ceiling and the mix decides the rest.
    """
    high = float(np.max(np.abs(buf))) if buf.size else 0.0
    if high < 1e-9:
        return buf
    return buf * (peak / high)


def write_wav(path: Path, buf: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.clip(buf, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")

    with wave.open(str(path), "wb") as w:
        w.setnchannels(CHANNELS)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
