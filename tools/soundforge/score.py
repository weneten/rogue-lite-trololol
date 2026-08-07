"""Notes, chords and bar/beat timing.

Thin layer, but it is what lets the five compositions in
:mod:`soundforge.tracks` read as music instead of as sample offsets.
"""
from __future__ import annotations

from dataclasses import dataclass

_SEMITONE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note(name: str) -> float:
    """"D3", "A#2", "Bb4" -> frequency in Hz (A4 = 440)."""
    letter = name[0].upper()
    idx = 1
    semi = _SEMITONE[letter]
    while idx < len(name) and name[idx] in "#b":
        semi += 1 if name[idx] == "#" else -1
        idx += 1

    octave = int(name[idx:])
    midi = (octave + 1) * 12 + semi
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def chord(*names: str) -> list[float]:
    return [note(n) for n in names]


@dataclass
class Grid:
    """Bar/beat timing for one track. Bars and beats are 1-based, the way a
    musician counts them, so `g.at(3, 2)` is the second beat of bar three."""

    bpm: float
    beats_per_bar: int = 4

    @property
    def beat(self) -> float:
        return 60.0 / self.bpm

    @property
    def bar(self) -> float:
        return self.beat * self.beats_per_bar

    def at(self, bar: int, beat: float = 1.0) -> float:
        return (bar - 1) * self.bar + (beat - 1.0) * self.beat

    def length(self, bars: int) -> float:
        return bars * self.bar
