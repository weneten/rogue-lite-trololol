"""Percussion.

All of it is synthesised from noise and swept sines rather than sampled, for
the same reason the art is generated: the whole soundtrack has to rebuild from
source with one command and no binary inputs.
"""
from __future__ import annotations

import numpy as np

from . import dsp
from .core import SR, samples
from .synth import perc_env


def _noise(n: int, seed: int) -> np.ndarray:
    return np.random.default_rng(seed).normal(0.0, 1.0, n)


def _sweep(n: int, start: float, end: float, bend: float) -> np.ndarray:
    """Sine with an exponential pitch drop — the core of every drum here."""
    t = np.arange(n) / SR
    freq = end + (start - end) * np.exp(-t / bend)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase)


def kick(dur: float = 0.42, gain: float = 1.0, tune: float = 1.0, seed: int = 0) -> np.ndarray:
    n = samples(dur)
    body = _sweep(n, 118.0 * tune, 43.0 * tune, 0.035) * perc_env(n, 0.16, attack=0.001)
    click = dsp.highpass(_noise(n, seed), 1800.0) * perc_env(n, 0.006, attack=0.0002)
    return dsp.soft_clip(body + click * 0.35, drive=1.4) * gain


def taiko(dur: float = 0.7, gain: float = 1.0, tune: float = 1.0, seed: int = 0) -> np.ndarray:
    """Big skin drum. Two membranes a fifth apart plus a wooden slap."""
    n = samples(dur)
    body = _sweep(n, 165.0 * tune, 78.0 * tune, 0.09) * perc_env(n, 0.26, attack=0.001)
    body += _sweep(n, 240.0 * tune, 116.0 * tune, 0.06) * perc_env(n, 0.15) * 0.5
    slap = dsp.bandpass(_noise(n, seed), 400.0, 2600.0) * perc_env(n, 0.03)
    return dsp.soft_clip(body + slap * 0.4, drive=1.25) * gain


def timpani(freq: float = 82.0, dur: float = 1.4, gain: float = 1.0, seed: int = 0) -> np.ndarray:
    """Tuned, and long enough to hold a note under a boss phrase."""
    n = samples(dur)
    t = np.arange(n) / SR
    tone = np.zeros(n)
    # Kettledrum partials: roughly 1 : 1.5 : 2 : 2.4, all decaying at their own rate.
    for ratio, level, decay in ((1.0, 1.0, 0.55), (1.5, 0.45, 0.3), (2.0, 0.3, 0.2), (2.44, 0.18, 0.12)):
        tone += level * np.sin(2.0 * np.pi * freq * ratio * t) * np.exp(-t / (dur * decay))
    strike = dsp.bandpass(_noise(n, seed), 200.0, 1800.0) * perc_env(n, 0.02)
    env = perc_env(n, dur * 0.4, attack=0.003)
    return (tone * 0.5 + strike * 0.5) * env * gain


def snare(dur: float = 0.28, gain: float = 1.0, tone_mix: float = 0.35, seed: int = 0) -> np.ndarray:
    n = samples(dur)
    # Wires are deliberately band-limited rather than full-range hiss: an open
    # noise burst on every backbeat eats the whole top of the mix.
    wires = dsp.bandpass(_noise(n, seed), 1200.0, 6500.0) * perc_env(n, 0.09, attack=0.0005)
    shell = (_sweep(n, 330.0, 185.0, 0.02) + _sweep(n, 470.0, 240.0, 0.02) * 0.6)
    shell *= perc_env(n, 0.055)
    return (wires * (1.0 - tone_mix) + shell * tone_mix) * gain


def roll(dur: float, gain: float = 1.0, rate: float = 28.0, seed: int = 0) -> np.ndarray:
    """Snare roll used to push into a boss phrase. Individual strokes rather
    than modulated noise, so it accelerates and crescendos like a player."""
    n = samples(dur)
    out = np.zeros(n)
    rng = np.random.default_rng(seed)
    t = 0.0
    i = 0
    while t < dur:
        hit = snare(0.09, gain=0.25 + 0.75 * (t / dur) ** 1.7, tone_mix=0.2, seed=seed + i)
        at = samples(t)
        end = min(n, at + hit.size)
        out[at:end] += hit[: end - at]
        # Slight human unevenness, and a roll that tightens as it builds.
        t += (1.0 / (rate * (1.0 + 0.6 * t / dur))) * rng.uniform(0.88, 1.12)
        i += 1
    return out * gain


def tom(freq: float = 150.0, dur: float = 0.36, gain: float = 1.0, seed: int = 0) -> np.ndarray:
    n = samples(dur)
    body = _sweep(n, freq * 1.5, freq, 0.05) * perc_env(n, 0.14, attack=0.001)
    skin = dsp.bandpass(_noise(n, seed), 250.0, 1600.0) * perc_env(n, 0.025)
    return (body + skin * 0.3) * gain


def hat(dur: float = 0.07, gain: float = 1.0, open_hat: bool = False, seed: int = 0) -> np.ndarray:
    """Closed / open hi-hat.

    Band-limited, not just high-passed. A hat that runs all the way to Nyquist
    is the single easiest way to make a loop sound like hissing, and it is
    played on every eighth note — so it gets a ceiling as well as a floor.
    """
    length = 0.34 if open_hat else dur
    n = samples(length)
    metal = dsp.bandpass(_noise(n, seed), 4800.0, 11000.0)
    # A handful of inharmonic partials over the noise: the noise is the sizzle,
    # these are what make it sound like struck metal rather than a tape hiss.
    t = np.arange(n) / SR
    for ratio in (1.0, 1.34, 1.79, 2.37):
        metal += np.sin(2.0 * np.pi * 5400.0 * ratio * t) * 0.12
    metal = dsp.bandpass(metal, 4600.0, 12000.0)
    return metal * perc_env(n, 0.13 if open_hat else 0.018, attack=0.0004) * gain * 0.3


def crash(dur: float = 1.8, gain: float = 1.0, seed: int = 0) -> np.ndarray:
    n = samples(dur)
    metal = dsp.bandpass(_noise(n, seed), 2400.0, 11500.0)
    t = np.arange(n) / SR
    for ratio in (1.0, 1.41, 1.87, 2.62, 3.44, 4.71, 6.02):
        metal += np.sin(2.0 * np.pi * 480.0 * ratio * t) * 0.06
    # Cymbals bloom: the high end arrives a beat after the strike, not with it.
    env = perc_env(n, dur * 0.32, attack=0.006)
    bloom = np.clip(t / 0.06, 0.0, 1.0) * 0.4 + 0.6
    return metal * env * bloom * gain * 0.3
