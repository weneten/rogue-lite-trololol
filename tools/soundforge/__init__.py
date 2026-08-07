"""Nightbane's soundtrack, generated from source.

The same idea as tools/pixelforge for the art: no binary inputs, no sample
library, one command rebuilds every music bed byte for byte. Run it with

    python3 tools/build_music.py

Layout:
    core     buffers, bar timing, seamless looping, WAV output
    dsp      filters, reverb, delay, the Karplus-Strong string
    synth    the instruments — organ, choir, strings, brass, bells, plucks
    drums    kick, taiko, timpani, snare, toms, hats, cymbals
    score    note names, chords, bar/beat grid
    tracks   the five compositions themselves
"""
from __future__ import annotations

from . import core, drums, dsp, score, synth, tracks  # noqa: F401

__all__ = ["core", "drums", "dsp", "score", "synth", "tracks"]
