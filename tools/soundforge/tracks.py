"""The five pieces.

All of it is one score in D — D minor for the menu and the shop, D harmonic
minor once anything is trying to kill you, so the raised C# is what actually
signals a fight. Combat and boss share that centre deliberately: the crossfade
in AudioManager lands on a related chord instead of a key change.

`combat_base` and `combat_percussion` are two halves of one arrangement at the
same tempo and the same length, because AudioManager plays them together and
rides the percussion layer on how dangerous the wave is. Their bar lines have
to agree to the sample or the drums walk away from the strings.
"""
from __future__ import annotations

import numpy as np

from . import drums, dsp, synth
from .core import Loop
from .score import Grid, chord, note


class Mix:
    """A dry canvas plus a reverb send.

    Instruments are played into both at once; :meth:`finish` renders the send
    through one shared reverb, which is what makes a track sound like a room
    rather than like six separate plug-ins.
    """

    def __init__(self, length: float, tail: float = 5.0) -> None:
        self.dry = Loop(length, tail)
        self.send = Loop(length, tail)

    def play(self, mono: np.ndarray, at: float, gain: float = 1.0, pan: float = 0.0,
             wet: float = 0.25) -> None:
        self.dry.add(mono, at, gain, pan)
        if wet > 0.0:
            self.send.add(mono, at, gain * wet, pan)

    def finish(self, size: float = 1.0, damp: float = 0.35, wet_gain: float = 1.0,
               width: float = 0.25) -> np.ndarray:
        send_mono = self.send.buf.mean(axis=1)
        if np.any(send_mono):
            self.dry.buf += dsp.reverb(send_mono, size=size, damp=damp) * wet_gain
        return dsp.widen(self.dry.resolve(), width)


# ---------------------------------------------------------------------------
# Menu — the title screen
# ---------------------------------------------------------------------------

def menu() -> np.ndarray:
    """Empty cathedral. Pedal organ, distant voices, one bell.

    Slow enough (66 BPM) that a player idling on the title screen is not being
    hurried, and voiced low so it never competes with the UI clicks.
    """
    g = Grid(66)
    bars = 8
    mix = Mix(g.length(bars), tail=6.0)

    # i - VI - III - V in D minor. The V is major (harmonic minor), which is
    # what stops the loop sounding like it has simply given up at bar 8.
    progression = [
        ("D2", chord("D3", "F3", "A3"), "D4"),
        ("A#1", chord("A#2", "D3", "F3"), "D4"),
        ("F2", chord("F2", "A2", "C3"), "C4"),
        ("A1", chord("A2", "C#3", "E3"), "C#4"),
    ]

    hold = g.bar * 2.0
    for i, (pedal, voicing, top) in enumerate(progression):
        at = g.at(1 + i * 2)

        # 16' pedal: the floor the whole track stands on.
        mix.play(synth.organ(note(pedal), hold + 0.6, gain=0.5, seed=i), at, wet=0.3)

        for v, freq in enumerate(voicing):
            pan = -0.35 + 0.35 * v
            mix.play(synth.organ(freq, hold + 0.5, gain=0.26, seed=i * 7 + v), at,
                     pan=pan, wet=0.45)

        # Voices sit above the organ and enter late, so each chord arrives as
        # pipes first and people second.
        mix.play(synth.choir(note(top), hold + 0.4, gain=0.3, seed=i * 13, vowel="ooh"),
                 at + g.beat * 0.5, pan=0.1, wet=0.75)
        mix.play(synth.choir(note(top) * 0.5, hold + 0.4, gain=0.18, seed=i * 13 + 3),
                 at + g.beat * 0.5, pan=-0.15, wet=0.75)

    # Two tolls per loop, on the pillars of the form. Long decays that run past
    # the loop point and get folded back over the opening bar.
    mix.play(synth.bell(note("D4"), 6.5, gain=0.42, seed=5), g.at(1), pan=-0.25, wet=0.9)
    mix.play(synth.bell(note("A3"), 6.0, gain=0.3, seed=9), g.at(5), pan=0.3, wet=0.9)

    # A harp answering each chord change, descending. Sparse on purpose: the
    # menu should feel like a held breath.
    harp = [
        (2, 3.0, ["A4", "F4", "D4", "A3"]),
        (4, 3.0, ["F4", "D4", "A#3", "F3"]),
        (6, 3.0, ["C5", "A4", "F4", "C4"]),
        (8, 2.5, ["E5", "C#5", "A4", "E4"]),
    ]
    for bar, beat, run in harp:
        for i, name in enumerate(run):
            mix.play(synth.pluck(note(name), 2.4, gain=0.2, damping=0.55, seed=bar * 31 + i),
                     g.at(bar, beat + i * 0.5), pan=0.4 - i * 0.22, wet=0.6)

    return mix.finish(size=1.75, damp=0.28, wet_gain=1.15, width=0.35)


# ---------------------------------------------------------------------------
# Shop — between waves
# ---------------------------------------------------------------------------

def shop() -> np.ndarray:
    """The exhale after a wave.

    Same key as everything else, but sevenths instead of triads and a plucked
    lead instead of an organ: recognisably the same soundtrack, with all the
    threat taken out of it.
    """
    g = Grid(84)
    bars = 8
    mix = Mix(g.length(bars), tail=4.0)

    progression = [
        ("D2", chord("D3", "F3", "A3", "C4")),      # Dm7
        ("G1", chord("G2", "A#2", "D3", "F3")),     # Gm7
        ("A#1", chord("A#2", "D3", "F3", "A3")),    # Bbmaj7
        ("A1", chord("A2", "D3", "E3", "G3")),      # A7sus4 — leans home
    ]

    hold = g.bar * 2.0
    for i, (root, voicing) in enumerate(progression):
        at = g.at(1 + i * 2)

        mix.play(synth.pluck(note(root), hold, gain=0.34, damping=0.75, seed=i * 3), at, wet=0.2)
        for v, freq in enumerate(voicing):
            mix.play(synth.strings(freq, hold + 0.3, gain=0.13, bright=1500.0, seed=i * 11 + v),
                     at, pan=-0.3 + 0.2 * v, wet=0.4)

        # Rolling arpeggio, up then down, one note per eighth. This is the
        # track's clock — there are no drums anywhere in the shop.
        pattern = list(range(len(voicing))) + list(range(len(voicing) - 1, 0, -1))
        for step in range(int(hold / (g.beat * 0.5))):
            idx = pattern[step % len(pattern)]
            octave = 2.0 if step % 8 == 5 else 1.0
            mix.play(
                synth.pluck(voicing[idx] * octave, 1.5, gain=0.16 if octave > 1 else 0.2,
                            damping=0.5, seed=i * 97 + step),
                at + step * g.beat * 0.5,
                pan=-0.4 + 0.16 * idx,
                wet=0.35,
            )

    # A four-note motif that answers itself an octave apart — the closest thing
    # the game has to a hummable tune.
    motif = [("A4", 3, 1.0), ("D5", 3, 2.0), ("C5", 3, 3.0), ("A4", 3, 4.0),
             ("F4", 4, 1.0), ("D4", 4, 2.5)]
    for i, (name, bar, beat) in enumerate(motif):
        mix.play(synth.celesta(note(name), 1.6, gain=0.22, seed=200 + i),
                 g.at(bar, beat), pan=0.28, wet=0.55)
        # The same phrase an octave down, four bars later — call and answer.
        mix.play(synth.celesta(note(name) * 0.5, 1.8, gain=0.16, seed=300 + i),
                 g.at(bar + 4, beat), pan=-0.28, wet=0.55)

    return mix.finish(size=0.95, damp=0.4, wet_gain=0.85, width=0.28)


# ---------------------------------------------------------------------------
# Combat — the two layers
# ---------------------------------------------------------------------------

_COMBAT_BPM = 132
_COMBAT_BARS = 16

# One chord per bar, eight bars round. D harmonic minor: the C# in the A major
# is the note that makes this sound like a fight and not a dirge.
_COMBAT_CHORDS = [
    ("D2", chord("D3", "F3", "A3")),
    ("D2", chord("D3", "F3", "A3")),
    ("A#1", chord("A#2", "D3", "F3")),
    ("C2", chord("C3", "E3", "G3")),
    ("D2", chord("D3", "F3", "A3")),
    ("G1", chord("G2", "A#2", "D3")),
    ("A1", chord("A2", "C#3", "E3")),
    ("A1", chord("A2", "C#3", "E3")),
]

# Eighth-note bass figure, in beats from the bar line. Front-loaded and then
# syncopated across the middle of the bar so it drives without marching.
_BASS_FIGURE = [0.0, 0.5, 1.5, 2.0, 2.5, 3.5]


def combat_base() -> np.ndarray:
    """Strings, bass and voices. No drums — those are the layer above.

    Sixteen bars rather than the four the old bed had. A wave lasts the best
    part of a minute and the loop should not come round four times before the
    first enemy dies.
    """
    g = Grid(_COMBAT_BPM)
    mix = Mix(g.length(_COMBAT_BARS), tail=4.0)

    for bar in range(1, _COMBAT_BARS + 1):
        root_name, voicing = _COMBAT_CHORDS[(bar - 1) % len(_COMBAT_CHORDS)]
        at = g.at(bar)
        second_half = bar > 8

        for i, offset in enumerate(_BASS_FIGURE):
            # Every fourth note of the figure jumps the octave, which is what
            # keeps a one-chord bar from sitting still.
            freq = note(root_name) * (2.0 if i == 4 else 1.0)
            mix.play(synth.bass(freq, g.beat * 0.55, gain=0.5, seed=bar * 17 + i),
                     at + offset * g.beat, wet=0.12)

        # Tremolo section holding the harmony. Re-bowed at sixteenths, and
        # harder in the back half where the arrangement opens up.
        for v, freq in enumerate(voicing):
            mix.play(
                synth.strings(freq, g.bar + 0.2, gain=0.17,
                              tremolo=0.75 if second_half else 0.5,
                              tremolo_rate=_COMBAT_BPM / 60.0 * 4.0,
                              bright=4200.0 if second_half else 3000.0,
                              seed=bar * 23 + v),
                at, pan=-0.45 + 0.35 * v, wet=0.4,
            )

        # Low voices, two bars at a time, under everything.
        if bar % 2 == 1:
            mix.play(synth.choir(note(root_name) * 2.0, g.bar * 2.0, gain=0.16,
                                 seed=bar * 5, vowel="ah"),
                     at, pan=0.12, wet=0.7)

        # Brass answers on the back half of the bar once the loop has been
        # round once — the arrangement's one real gear change.
        if second_half and bar % 2 == 0:
            for freq in voicing[:2]:
                mix.play(synth.brass(freq * 0.5, g.beat * 0.9, gain=0.2, seed=bar * 31),
                         at + g.beat * 2.5, pan=-0.2, wet=0.3)

    # A violin line over bars 9-16, so the second pass through the harmony has
    # something on top rather than just being louder.
    melody = [
        ("D5", 9, 1.0, 1.5), ("C5", 9, 3.0, 1.0), ("A4", 10, 1.0, 2.0),
        ("A#4", 11, 1.0, 1.5), ("A4", 11, 3.0, 1.0), ("F4", 12, 1.0, 2.0),
        ("D5", 13, 1.0, 1.0), ("F5", 13, 2.5, 1.5), ("E5", 14, 1.0, 2.0),
        ("D5", 15, 1.0, 1.5), ("C#5", 15, 3.0, 1.0), ("D5", 16, 1.0, 2.5),
    ]
    for name, bar, beat, beats in melody:
        mix.play(synth.lead(note(name), g.beat * beats, gain=0.3, seed=bar * 41),
                 g.at(bar, beat), pan=0.22, wet=0.5)

    return mix.finish(size=1.1, damp=0.42, wet_gain=0.7, width=0.3)


def combat_percussion() -> np.ndarray:
    """The drums that ride on wave intensity.

    Same grid as `combat_base`, sample for sample. Written to be legible on
    its own at low volume, so a quiet early wave still has a pulse: kick and
    hats carry the beat, and everything ornamental is in the fills.
    """
    g = Grid(_COMBAT_BPM)
    mix = Mix(g.length(_COMBAT_BARS), tail=3.0)

    kicks = [0.0, 1.5, 2.0, 3.5]
    snares = [1.0, 3.0]

    for bar in range(1, _COMBAT_BARS + 1):
        at = g.at(bar)
        second_half = bar > 8
        fill = bar % 8 == 0

        for i, offset in enumerate(kicks):
            mix.play(drums.kick(gain=0.85, seed=bar * 7 + i), at + offset * g.beat, wet=0.06)

        for i, offset in enumerate(snares):
            if fill and offset > 2.0:
                continue
            mix.play(drums.snare(gain=0.4, seed=bar * 11 + i), at + offset * g.beat,
                     pan=0.05, wet=0.28)

        # Eighths, with the down-beat of each pair accented. Panned slightly
        # off centre so they do not fight the snare for the middle.
        for step in range(8):
            if fill and step >= 4:
                continue
            open_hat = step == 6 and not second_half
            mix.play(
                drums.hat(gain=0.15 if step % 2 == 0 else 0.09, open_hat=open_hat,
                          seed=bar * 13 + step),
                at + step * g.beat * 0.5, pan=-0.22, wet=0.2,
            )

        # A taiko on the bar line gives the loop its weight; the back half
        # doubles it on beat three.
        mix.play(drums.taiko(gain=0.7, seed=bar * 3), at, wet=0.25)
        if second_half:
            mix.play(drums.taiko(gain=0.45, tune=1.12, seed=bar * 3 + 1),
                     at + 2.0 * g.beat, pan=0.15, wet=0.25)

        # Tom fill closing each eight-bar half, walking down to the turnaround.
        if fill:
            toms = [(190.0, 0.0), (160.0, 0.5), (130.0, 1.0), (110.0, 1.5), (95.0, 1.75)]
            for i, (freq, offset) in enumerate(toms):
                mix.play(drums.tom(freq, gain=0.55, seed=bar * 19 + i),
                         at + (2.0 + offset) * g.beat, pan=0.35 - i * 0.18, wet=0.3)

    for bar in (1, 9):
        mix.play(drums.crash(gain=0.3, seed=bar), g.at(bar), pan=-0.1, wet=0.5)

    return mix.finish(size=0.7, damp=0.5, wet_gain=0.5, width=0.2)


# ---------------------------------------------------------------------------
# Boss
# ---------------------------------------------------------------------------

def boss() -> np.ndarray:
    """Everything at once.

    Faster than combat, a whole tone of extra harmonic trouble (the Bb minor
    and the diminished bar are borrowed from nowhere near D minor), and the
    only track with both a full kit and voices. It has to survive being cut to
    over the top of combat music mid-wave, so it opens on the beat with a
    crash and a tutti chord instead of easing in.
    """
    g = Grid(150)
    bars = 16
    mix = Mix(g.length(bars), tail=5.0)

    # Two bars per chord. The Eb is a Neapolitan and the Ab diminished is a
    # tritone from home — both deliberately wrong, which is the point.
    progression = [
        ("D2", chord("D3", "F3", "A3"), "D4"),
        ("A#1", chord("A#2", "D#3", "F#3"), "D#4"),
        ("D#2", chord("D#3", "G3", "A#3"), "G4"),
        ("A1", chord("A2", "C#3", "G3"), "A#4"),
        ("D2", chord("D3", "F3", "A3"), "D4"),
        ("G1", chord("G2", "A#2", "D3"), "A#4"),
        ("G#1", chord("G#2", "B2", "D3"), "B4"),
        ("A1", chord("A2", "C#3", "G3"), "C#5"),
    ]

    for pair, (root_name, voicing, top) in enumerate(progression):
        bar = 1 + pair * 2
        at = g.at(bar)
        hold = g.bar * 2.0
        root = note(root_name)

        # Sixteenth-note bass engine. Accented on the beat, with the octave
        # thrown in on the last sixteenth of each beat to keep it churning.
        for step in range(32):
            beat_pos = step * 0.25
            accent = step % 4 == 0
            freq = root * (2.0 if step % 4 == 3 else 1.0)
            mix.play(synth.bass(freq, g.beat * 0.24, gain=0.42 if accent else 0.26,
                                punch=1.4, seed=pair * 61 + step),
                     at + beat_pos * g.beat, wet=0.08)

        # Brass on the bar line and pushed into beat three.
        for v, freq in enumerate(voicing):
            mix.play(synth.brass(freq * 0.5, g.beat * 1.6, gain=0.24, seed=pair * 29 + v),
                     at, pan=-0.3 + 0.3 * v, wet=0.35)
            mix.play(synth.brass(freq * 0.5, g.beat * 0.8, gain=0.18, seed=pair * 29 + v + 7),
                     at + g.beat * 2.5, pan=0.3 - 0.3 * v, wet=0.35)

        # High tremolo cluster: the string section screaming rather than playing.
        for v, freq in enumerate(voicing):
            mix.play(synth.strings(freq * 2.0, hold, gain=0.11, tremolo=0.9,
                                   tremolo_rate=12.0, bright=4200.0, seed=pair * 43 + v),
                     at, pan=0.45 - 0.3 * v, wet=0.45)

        mix.play(synth.choir(note(top), hold, gain=0.24, seed=pair * 71, vowel="ah"),
                 at, pan=-0.1, wet=0.8)

        # Kettledrums on one and three of every bar of the pair.
        for b in (0, 1):
            for beat in (1.0, 3.0):
                mix.play(drums.timpani(root * 2.0, 1.2, gain=0.55, seed=pair * 13 + b),
                         at + g.bar * b + (beat - 1.0) * g.beat, pan=-0.15, wet=0.4)

    # Kit under the whole thing, straight and relentless.
    for bar in range(1, bars + 1):
        at = g.at(bar)
        for offset in (0.0, 1.0, 2.0, 3.0):
            mix.play(drums.kick(gain=0.72, tune=0.95, seed=bar * 5 + int(offset)),
                     at + offset * g.beat, wet=0.05)
        for offset in (1.0, 3.0):
            mix.play(drums.snare(gain=0.3, tone_mix=0.3, seed=bar * 9 + int(offset)),
                     at + offset * g.beat, pan=0.08, wet=0.35)
        for step in range(8):
            mix.play(drums.hat(gain=0.12 if step % 2 == 0 else 0.07, seed=bar * 3 + step),
                     at + step * g.beat * 0.5, pan=-0.25, wet=0.18)

    # Tolls at the top of each half, and a roll over the last bar that lands on
    # the loop point — the crash at bar 1 is what it resolves onto.
    for bar in (1, 9):
        mix.play(synth.bell(note("D3"), 5.0, gain=0.3, seed=bar * 3), g.at(bar), pan=0.25, wet=0.8)
        mix.play(drums.crash(gain=0.3, seed=bar * 11), g.at(bar), pan=-0.15, wet=0.55)

    mix.play(drums.roll(g.bar, gain=0.32, seed=77), g.at(16), pan=0.0, wet=0.4)

    return mix.finish(size=1.35, damp=0.32, wet_gain=0.75, width=0.32)


TRACKS = {
    "menu": menu,
    "shop": shop,
    "combat_base": combat_base,
    "combat_percussion": combat_percussion,
    "boss": boss,
}

# Limiter threshold per track. Drums are nearly all transient, so they need a
# harder ceiling than a bed of sustained chords to arrive at the same apparent
# loudness — which matters because AudioManager plays two of these at once.
MASTER_THRESHOLD = {
    "combat_percussion": 0.26,
    "boss": 0.3,
}
