"""The instruments.

Every pitched voice is built additively — a sum of sine partials — rather than
from a naive saw or square. At 32 kHz a naive saw at D5 folds a dozen aliased
partials back down into the audible range and turns a string section into a
faint ring modulator. Summing only the partials that fit under Nyquist costs a
little more arithmetic and is simply clean.

Each voice is a function of (frequency, duration) returning a mono array, so
the score in :mod:`soundforge.score` reads as notes rather than as DSP.
"""
from __future__ import annotations

import numpy as np

from . import dsp
from .core import SR, samples


def _t(n: int) -> np.ndarray:
    return np.arange(n) / SR


def adsr(
    n: int,
    attack: float = 0.01,
    decay: float = 0.1,
    sustain: float = 0.7,
    release: float = 0.2,
    curve: float = 1.0,
) -> np.ndarray:
    """Standard four-stage envelope, laid out so attack+decay+release never
    overrun the note: the sustain segment absorbs the difference."""
    a, d, r = samples(attack), samples(decay), samples(release)
    a = min(a, n)
    d = min(d, max(0, n - a))
    r = min(r, max(0, n - a - d))
    s = max(0, n - a - d - r)

    env = np.concatenate([
        np.linspace(0.0, 1.0, a, endpoint=False) ** curve if a else np.empty(0),
        np.linspace(1.0, sustain, d, endpoint=False) if d else np.empty(0),
        np.full(s, sustain),
        np.linspace(sustain, 0.0, r) ** 1.6 if r else np.empty(0),
    ])
    if env.size < n:
        env = np.concatenate([env, np.zeros(n - env.size)])
    return env[:n]


def perc_env(n: int, decay: float, attack: float = 0.002, curve: float = 1.0) -> np.ndarray:
    """Exponential decay for anything struck rather than bowed."""
    t = _t(n)
    env = np.exp(-t / max(decay, 1e-4)) ** curve
    a = max(1, samples(attack))
    env[:a] *= np.linspace(0.0, 1.0, a)
    return env


def partials(
    freq: float,
    n: int,
    weights: np.ndarray | list[float],
    detune: float = 0.0,
    vibrato: float = 0.0,
    vibrato_rate: float = 5.0,
    drift: float = 0.0,
    seed: int = 0,
) -> np.ndarray:
    """Sum of sine partials at `freq`.

    `detune` in cents spreads the partials slightly sharp and flat of exact
    harmonics, which is the difference between an organ (dead still) and a
    string section (never quite in tune with itself).
    """
    rng = np.random.default_rng(seed)
    t = _t(n)

    # Vibrato and drift modulate the phase, so they apply to every partial at
    # once and the note stays coherent.
    mod = np.zeros(n)
    if vibrato > 0.0:
        # Delayed onset: vibrato from the first millisecond sounds synthetic.
        onset = np.clip(t / 0.35, 0.0, 1.0)
        mod += vibrato * onset * np.sin(2.0 * np.pi * vibrato_rate * t + rng.uniform(0, 6.28))
    if drift > 0.0:
        mod += drift * np.sin(2.0 * np.pi * rng.uniform(0.18, 0.5) * t + rng.uniform(0, 6.28))

    out = np.zeros(n)
    for i, weight in enumerate(weights):
        if weight == 0.0:
            continue
        harmonic = i + 1
        cents = rng.uniform(-detune, detune) if detune else 0.0
        f = freq * harmonic * (2.0 ** (cents / 1200.0))
        if f >= SR * 0.47:
            break
        phase = 2.0 * np.pi * f * t + mod * harmonic + rng.uniform(0.0, 6.28)
        out += weight * np.sin(phase)

    peak = float(np.sum(np.abs(np.asarray(weights, dtype=float))))
    return out / max(peak, 1e-9)


def _saw_weights(count: int, tilt: float = 1.0) -> list[float]:
    return [1.0 / (k ** tilt) for k in range(1, count + 1)]


def _square_weights(count: int) -> list[float]:
    return [1.0 / k if k % 2 else 0.0 for k in range(1, count + 1)]


# ---------------------------------------------------------------------------
# Sustained voices
# ---------------------------------------------------------------------------

def organ(freq: float, dur: float, gain: float = 1.0, seed: int = 0) -> np.ndarray:
    """Cathedral pipe organ: drawbar sines at 16', 8', 5 1/3', 4', 2 2/3', 2'.

    Pipes speak with a puff of air before the tone settles, so a short filtered
    noise chiff is mixed under the attack. Without it the organ sounds like a
    sine bank, because that is exactly what it is.
    """
    n = samples(dur)
    weights = [1.0, 0.85, 0.42, 0.55, 0.22, 0.3, 0.0, 0.16, 0.0, 0.09]
    tone = partials(freq, n, weights, detune=3.0, drift=0.004, seed=seed)

    rng = np.random.default_rng(seed + 991)
    chiff = dsp.bandpass(rng.normal(0.0, 1.0, n), freq * 1.5, freq * 5.0) * perc_env(n, 0.035)

    env = adsr(n, attack=0.09, decay=0.25, sustain=0.86, release=0.35)
    return (tone + chiff * 0.22) * env * gain


def choir(freq: float, dur: float, gain: float = 1.0, seed: int = 0, vowel: str = "ah") -> np.ndarray:
    """Wordless voices.

    Three detuned saw stacks pushed through the formant pair that separates
    "ah" from "ooh", plus breath noise. It is a caricature of a choir, but at
    the back of a mix under a reverb it lands.
    """
    n = samples(dur)
    formants = {"ah": (700.0, 1180.0), "ooh": (320.0, 800.0), "eh": (530.0, 1750.0)}
    f1, f2 = formants.get(vowel, formants["ah"])

    stack = np.zeros(n)
    for i, cents in enumerate((-11.0, 0.0, 9.0)):
        f = freq * 2.0 ** (cents / 1200.0)
        stack += partials(f, n, _saw_weights(18), vibrato=0.06, vibrato_rate=4.6 + i * 0.4,
                          drift=0.02, seed=seed + i * 37)
    stack /= 3.0

    voiced = (
        dsp.bandpass(stack, f1 * 0.6, f1 * 1.5) * 1.0
        + dsp.bandpass(stack, f2 * 0.7, f2 * 1.4) * 0.55
        + dsp.lowpass(stack, 220.0) * 0.5
    )

    rng = np.random.default_rng(seed + 17)
    breath = dsp.bandpass(rng.normal(0.0, 1.0, n), 900.0, 3600.0) * 0.05

    env = adsr(n, attack=0.28, decay=0.4, sustain=0.78, release=0.55, curve=1.6)
    return (voiced + breath) * env * gain * 0.8


def strings(
    freq: float,
    dur: float,
    gain: float = 1.0,
    tremolo: float = 0.0,
    tremolo_rate: float = 11.0,
    bright: float = 2400.0,
    seed: int = 0,
) -> np.ndarray:
    """Bowed section. `tremolo` above zero gives the fast re-bowing that does
    most of the work of making combat music feel urgent."""
    n = samples(dur)
    stack = np.zeros(n)
    for i, cents in enumerate((-8.0, 0.0, 7.0, 14.0)):
        f = freq * 2.0 ** (cents / 1200.0)
        stack += partials(f, n, _saw_weights(20, tilt=1.05), vibrato=0.05,
                          vibrato_rate=5.2 + i * 0.3, drift=0.015, seed=seed + i * 53)
    stack /= 4.0

    body = dsp.lowpass(stack, bright) + dsp.bandpass(stack, 200.0, 700.0) * 0.35

    if tremolo > 0.0:
        t = _t(n)
        body *= 1.0 - tremolo * 0.5 * (1.0 - np.cos(2.0 * np.pi * tremolo_rate * t))

    env = adsr(n, attack=0.11, decay=0.3, sustain=0.8, release=0.4, curve=1.4)
    return body * env * gain * 0.9


def brass(freq: float, dur: float, gain: float = 1.0, seed: int = 0) -> np.ndarray:
    """Low brass stab. The bite comes from the filter opening faster than the
    amplitude does, which is what a horn actually does under pressure."""
    n = samples(dur)
    tone = partials(freq, n, _saw_weights(26, tilt=0.85), detune=6.0, vibrato=0.03, seed=seed)
    tone += partials(freq * 0.5, n, _square_weights(9), seed=seed + 5) * 0.3

    t = _t(n)
    cutoff = freq * (2.0 + 9.0 * np.exp(-t / 0.09)) + 180.0
    shaped = dsp.sweep_lowpass(tone, np.clip(cutoff, 120.0, SR * 0.45))

    env = adsr(n, attack=0.02, decay=0.12, sustain=0.72, release=0.18)
    return dsp.soft_clip(shaped * env, drive=1.7) * gain


def bass(freq: float, dur: float, gain: float = 1.0, punch: float = 1.0, seed: int = 0) -> np.ndarray:
    """Sub sine plus a filtered saw, so it reads on both a subwoofer and a
    phone speaker. The saw carries the pitch when the sub is inaudible."""
    n = samples(dur)
    sub = np.sin(2.0 * np.pi * freq * _t(n))
    body = partials(freq, n, _saw_weights(14), detune=2.0, seed=seed)

    t = _t(n)
    cutoff = freq * (4.0 + 8.0 * punch * np.exp(-t / 0.05)) + 90.0
    body = dsp.sweep_lowpass(body, np.clip(cutoff, 80.0, SR * 0.45))

    env = adsr(n, attack=0.004, decay=0.08, sustain=0.72, release=0.09)
    return (sub * 0.7 + body * 0.55) * env * gain


def lead(freq: float, dur: float, gain: float = 1.0, seed: int = 0) -> np.ndarray:
    """Solo violin. One instrument, so it gets real vibrato and no detune
    stack — the thing that makes it read as a person and not a section."""
    n = samples(dur)
    tone = partials(freq, n, _saw_weights(22, tilt=1.15), vibrato=0.09, vibrato_rate=5.8,
                    drift=0.01, seed=seed)
    body = dsp.lowpass(tone, 5200.0) + dsp.bandpass(tone, 900.0, 2400.0) * 0.4

    env = adsr(n, attack=0.07, decay=0.22, sustain=0.82, release=0.3, curve=1.3)
    return body * env * gain * 0.85


# ---------------------------------------------------------------------------
# Struck and plucked
# ---------------------------------------------------------------------------

def bell(freq: float, dur: float, gain: float = 1.0, seed: int = 0) -> np.ndarray:
    """Church bell by FM.

    A bell's partials are inharmonic — that is the whole sound. The modulator
    sits at a non-integer ratio and decays faster than the carrier, so the
    clang fades into a pure hum the way a real bell does.
    """
    n = samples(dur)
    t = _t(n)
    mod_env = np.exp(-t / (dur * 0.11))
    carrier_env = perc_env(n, dur * 0.34, attack=0.001)

    mod = np.sin(2.0 * np.pi * freq * 1.41 * t) * mod_env * 5.5
    tone = np.sin(2.0 * np.pi * freq * t + mod)
    # The hum note an octave down, and the strike partial a fifth above.
    tone += np.sin(2.0 * np.pi * freq * 0.5 * t) * 0.45 * np.exp(-t / (dur * 0.55))
    tone += np.sin(2.0 * np.pi * freq * 2.97 * t) * 0.2 * np.exp(-t / (dur * 0.08))

    return tone * carrier_env * gain * 0.55


def pluck(freq: float, dur: float, gain: float = 1.0, damping: float = 0.5, seed: int = 0) -> np.ndarray:
    """Harp / lute. Karplus-Strong, then rolled off so it sits behind the
    sustained voices instead of on top of them."""
    n = samples(dur)
    string = dsp.karplus(freq, n, damping=damping, seed=seed)
    # Bright enough to keep the string in the top of the mix: a harp with its
    # air filtered off is indistinguishable from a muted piano.
    string = dsp.lowpass(string, min(SR * 0.45, freq * 20.0 + 2600.0))
    return string * perc_env(n, dur * 0.5, attack=0.001) * gain


def celesta(freq: float, dur: float, gain: float = 1.0, seed: int = 0) -> np.ndarray:
    """Glassy struck metal — the shop's little melodic sparkle."""
    n = samples(dur)
    tone = partials(freq, n, [1.0, 0.0, 0.35, 0.0, 0.18, 0.0, 0.08, 0.0, 0.05, 0.0, 0.03], seed=seed)
    tone += np.sin(2.0 * np.pi * freq * 4.13 * _t(n)) * 0.12 * perc_env(n, 0.05)
    return tone * perc_env(n, dur * 0.3, attack=0.002) * gain
