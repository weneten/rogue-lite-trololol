"""Filters, space and glue.

Two deliberate choices run through this file.

Filters are FIR (windowed sinc), not the biquads a DAW would use. Without
scipy, an IIR filter is a per-sample Python loop over a million samples;
`np.convolve` does the same job in one call. Sweeps are done by filtering
overlapping blocks at different cutoffs and crossfading, which is how a filter
envelope stays cheap.

Delay-based effects (comb, allpass, Karplus-Strong) *are* recursive, but their
feedback is a pure delay of L samples, so a whole block of L samples only ever
depends on the block before it. Each one is therefore computed L samples at a
time — exact, and N/L iterations instead of N.
"""
from __future__ import annotations

import numpy as np

from .core import SR


def _sinc_kernel(cutoff_hz: float, taps: int, high: bool = False) -> np.ndarray:
    fc = np.clip(cutoff_hz / SR, 1e-4, 0.499)
    n = np.arange(taps) - (taps - 1) / 2.0
    k = 2.0 * fc * np.sinc(2.0 * fc * n)
    k *= np.blackman(taps)
    k /= np.sum(k)

    if high:
        # Spectral inversion: all-pass minus the low band.
        k = -k
        k[(taps - 1) // 2] += 1.0
    return k


def _fit_taps(x: np.ndarray, taps: int) -> int:
    """np.convolve(mode="same") returns max(len(x), taps) samples, so a kernel
    longer than the signal silently changes its length. Short notes are common
    here — clamp instead."""
    taps = min(taps, x.size if x.size % 2 else x.size - 1)
    return max(3, taps)


def lowpass(x: np.ndarray, cutoff_hz: float, taps: int = 129) -> np.ndarray:
    if cutoff_hz >= SR * 0.49 or x.size < 4:
        return x
    return np.convolve(x, _sinc_kernel(cutoff_hz, _fit_taps(x, taps)), mode="same")


def highpass(x: np.ndarray, cutoff_hz: float, taps: int = 129) -> np.ndarray:
    if cutoff_hz <= 20.0 or x.size < 4:
        return x
    return np.convolve(x, _sinc_kernel(cutoff_hz, _fit_taps(x, taps), high=True), mode="same")


def bandpass(x: np.ndarray, low_hz: float, high_hz: float, taps: int = 129) -> np.ndarray:
    return highpass(lowpass(x, high_hz, taps), low_hz, taps)


def sweep_lowpass(x: np.ndarray, cutoff: np.ndarray, block: int = 384) -> np.ndarray:
    """Time-varying lowpass. `cutoff` is a per-sample cutoff curve in Hz.

    Each block is filtered at its own average cutoff and crossfaded into its
    neighbour, so a filter envelope glides instead of stepping.
    """
    n = x.size
    if n < 8:
        return x

    out = np.zeros(n)
    weight = np.zeros(n)

    pos = 0
    while pos < n:
        end = min(n, pos + block * 2)
        seg = x[pos:end]
        w = np.hanning(seg.size + 2)[1:-1]
        fc = float(np.mean(cutoff[pos:end]))
        out[pos:end] += lowpass(seg, fc, taps=65) * w
        weight[pos:end] += w
        pos += block

    # Overlapping Hann windows sum to 1 in the middle but taper at both ends;
    # dividing by the actual weight keeps the first and last block at level.
    return out / np.maximum(weight, 1e-6)


def _feedback_comb(x: np.ndarray, delay: int, gain: float, damp: float = 0.0) -> np.ndarray:
    """y[n] = x[n] + g * lp(y[n - delay]), a block at a time."""
    n = x.size
    pad = int(np.ceil(n / delay)) * delay
    y = np.zeros(pad)
    src = np.zeros(pad)
    src[:n] = x

    carry = np.zeros(delay)
    for start in range(0, pad, delay):
        block = src[start : start + delay] + gain * carry
        y[start : start + delay] = block
        if damp > 0.0:
            # One-pole damping across the block boundary makes each repeat
            # duller than the last, which is what a stone room does.
            carry = block * (1.0 - damp) + np.concatenate(([carry[-1]], block[:-1])) * damp
        else:
            carry = block
    return y[:n]


def _allpass(x: np.ndarray, delay: int, gain: float) -> np.ndarray:
    n = x.size
    pad = int(np.ceil(n / delay)) * delay
    src = np.zeros(pad)
    src[:n] = x

    y = np.zeros(pad)
    prev_in = np.zeros(delay)
    prev_out = np.zeros(delay)
    for start in range(0, pad, delay):
        block = src[start : start + delay]
        out = -gain * block + prev_in + gain * prev_out
        y[start : start + delay] = out
        prev_in, prev_out = block, out
    return y[:n]


# Schroeder comb delays, in samples at 32 kHz. Mutually prime so the repeats
# never line up into a ringing pitch.
_COMBS = (1279, 1543, 1789, 2003, 2287, 2531)
_ALLPASS = (307, 127, 53)


def reverb(
    mono: np.ndarray,
    size: float = 1.0,
    damp: float = 0.35,
    width: float = 0.85,
    pre_delay: float = 0.02,
) -> np.ndarray:
    """Stereo plate/hall. Returns the wet signal only — callers set the blend.

    `size` scales the comb lengths: 1.0 is a chapel, 1.6 is the nave of a
    cathedral, 0.4 is a shop back room.
    """
    pre = int(pre_delay * SR)
    src = np.concatenate([np.zeros(pre), mono]) if pre else mono
    src = src[: mono.size] if pre else src

    out = np.zeros((mono.size, 2))
    for channel in (0, 1):
        # A few samples of offset between the ears decorrelates the two tails
        # without any of the phasing a simple delay would cause.
        skew = 1.0 + (0.013 * width if channel else -0.011 * width)
        acc = np.zeros(mono.size)
        for length in _COMBS:
            d = max(32, int(length * size * skew))
            acc += _feedback_comb(src, d, gain=0.805, damp=damp)
        acc /= len(_COMBS)

        for length in _ALLPASS:
            acc = _allpass(acc, max(16, int(length * size * skew)), 0.62)
        out[:, channel] = acc

    return out * 0.42


def echo(mono: np.ndarray, time: float, feedback: float = 0.35, taps: int = 4) -> np.ndarray:
    """Simple tempo-synced repeats, summed into the dry signal by the caller."""
    out = np.zeros(mono.size)
    gain = 1.0
    for i in range(1, taps + 1):
        gain *= feedback
        shift = int(time * SR * i)
        if shift >= mono.size:
            break
        out[shift:] += mono[: mono.size - shift] * gain
    return out


def karplus(freq: float, n: int, damping: float = 0.5, seed: int = 0) -> np.ndarray:
    """Plucked string. Excite a delay line with noise and let it lose its
    high end each time round — the whole reason harps and lutes sound alive."""
    rng = np.random.default_rng(seed)
    delay = max(4, int(SR / freq))
    burst = rng.uniform(-1.0, 1.0, delay)
    # A pluck is a strike, not a burst of hiss: shaping the excitation stops
    # the first 30 ms sounding like a snare hit.
    burst *= np.linspace(1.0, 0.15, delay) ** 1.5

    total = int(np.ceil((n + delay) / delay)) * delay
    y = np.zeros(total + delay)
    y[:delay] = burst

    feedback = 0.5 * (1.0 - 0.5 * damping) + 0.49
    prev = burst
    for start in range(delay, total, delay):
        # Average with the neighbouring sample: the classic one-zero loop
        # filter, which is what makes the decay progressively duller.
        smoothed = 0.5 * (prev + np.concatenate(([prev[-1]], prev[:-1])))
        block = smoothed * feedback
        y[start : start + delay] = block
        prev = block
    return y[:n]


def soft_clip(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    """Tanh saturation. Used on brass and taiko, where the point is the grit."""
    return np.tanh(x * drive) / np.tanh(drive) if drive > 0 else x


def limit(stereo: np.ndarray, threshold: float = 0.45, window: float = 0.012) -> np.ndarray:
    """Look-ahead peak limiter.

    Without one, a track is only as loud as its loudest transient: a crash and
    a kick landing on the same sample were pulling the whole percussion bed
    7 dB below the string bed it has to be heard against. Smoothing the gain
    curve with a centred window both softens the grab and gives it look-ahead,
    so the limiter is already ducking before the hit arrives.
    """
    peak = np.max(np.abs(stereo), axis=1)
    span = max(3, int(window * SR) | 1)

    # Sliding max via dilation: the gain has to respond to the peak anywhere in
    # the window, not to its average.
    padded = np.pad(peak, span // 2, mode="edge")
    envelope = np.max(np.lib.stride_tricks.sliding_window_view(padded, span), axis=1)

    gain = np.minimum(1.0, threshold / np.maximum(envelope, 1e-9))
    smooth = np.hanning(span)
    smooth /= smooth.sum()
    gain = np.convolve(np.pad(gain, span, mode="edge"), smooth, mode="same")[span:-span]

    return stereo * gain[:, None]


def widen(stereo: np.ndarray, amount: float = 0.3) -> np.ndarray:
    """Mid/side widening. Kept modest — a wide mix collapses badly on the
    laptop speakers most people will play this on."""
    mid = (stereo[:, 0] + stereo[:, 1]) * 0.5
    side = (stereo[:, 0] - stereo[:, 1]) * 0.5 * (1.0 + amount)
    return np.stack([mid + side, mid - side], axis=1)
