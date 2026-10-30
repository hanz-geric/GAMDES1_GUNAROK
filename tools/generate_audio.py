"""Generates Gunarok's sound effects and music loops (original, team-owned).

Run from the project root:  python tools/generate_audio.py
Needs numpy. Writes 16-bit mono WAV files into assets/audio/.
"""
import math
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SFX = ROOT / "assets" / "audio" / "sfx"
MUSIC = ROOT / "assets" / "audio" / "music"
SR = 22050
rng = np.random.default_rng(7)


def save(path, data, gain=0.9):
    data = np.asarray(data, dtype=np.float64)
    peak = np.max(np.abs(data)) or 1.0
    data = data / peak * gain
    pcm = (data * 32767).astype(np.int16)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote", path.relative_to(ROOT))


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(n, attack=0.005, decay=None, sustain=1.0, release=0.05):
    """Simple attack / exponential-decay envelope of n samples."""
    e = np.ones(n)
    a = max(1, int(attack * SR))
    e[:a] = np.linspace(0, 1, a)
    if decay is not None:
        k = np.arange(n - a) / SR
        e[a:] = sustain + (1 - sustain) * np.exp(-k / decay)
    r = max(1, int(release * SR))
    if r < n:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x, amount):
    """One-pole low-pass. amount near 0 = darker, near 1 = brighter."""
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += amount * (v - acc)
        y[i] = acc
    return y


def noise(seconds):
    return rng.uniform(-1, 1, int(SR * seconds))


def sweep(f0, f1, seconds, shape="sine"):
    t = t_axis(seconds)
    f = np.geomspace(f0, f1, len(t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    if shape == "square":
        return np.sign(np.sin(phase))
    if shape == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    return np.sin(phase)


def tone(freq, seconds, shape="sine"):
    return sweep(freq, freq * 1.0001, seconds, shape)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def pad(x, seconds):
    out = np.zeros(int(SR * seconds))
    out[: len(x)] = x[: len(out)]
    return out


# --------------------------------------------------------------------------
# Sound effects
# --------------------------------------------------------------------------
def make_sfx():
    n = noise(0.14)
    save(SFX / "whoosh_punch.wav", lowpass(n, 0.35) * env(len(n), 0.03, 0.04), 0.6)
    n = noise(0.2)
    save(SFX / "whoosh_kick.wav", lowpass(n, 0.18) * env(len(n), 0.05, 0.06), 0.65)
    n = noise(0.4)
    save(SFX / "whoosh_special.wav", mix(lowpass(n, 0.25) * env(len(n), 0.1, 0.12), 0.4 * sweep(200, 900, 0.4, "saw") * env(int(0.4 * SR), 0.05, 0.1)), 0.75)

    def thump(freq, length, click):
        body = sweep(freq * 1.8, freq, length) * env(int(length * SR), 0.002, length / 4)
        crack = lowpass(noise(0.05), 0.7) * env(int(0.05 * SR), 0.001, 0.012)
        return mix(body, click * crack)

    save(SFX / "hit_light.wav", thump(150, 0.16, 0.8))
    save(SFX / "hit_heavy.wav", thump(95, 0.24, 1.0))
    save(SFX / "hit_special.wav", mix(thump(70, 0.45, 1.2), 0.5 * lowpass(noise(0.45), 0.2) * env(int(0.45 * SR), 0.002, 0.12)))

    t = t_axis(0.3)
    clang = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((880, 1.0), (1335, 0.6), (2110, 0.4), (3170, 0.2)))
    save(SFX / "block.wav", mix(clang * np.exp(-t / 0.06), 0.4 * lowpass(noise(0.03), 0.8)), 0.6)
    save(SFX / "jump.wav", sweep(260, 620, 0.12, "square") * env(int(0.12 * SR), 0.003, 0.05) * 0.5, 0.35)
    save(SFX / "knockdown.wav", mix(sweep(120, 45, 0.35) * env(int(0.35 * SR), 0.002, 0.1), 0.6 * lowpass(noise(0.3), 0.15) * env(int(0.3 * SR), 0.002, 0.08)))

    t = t_axis(1.0)
    thunder = lowpass(noise(1.0), 0.12) * np.exp(-t / 0.35)
    crackle = lowpass(noise(1.0), 0.9) * np.exp(-t / 0.05)
    save(SFX / "thunder.wav", mix(thunder, 0.7 * crackle, 0.6 * sweep(90, 40, 1.0) * np.exp(-t / 0.3)))
    t = t_axis(0.6)
    crack = lowpass(noise(0.6), 0.95) * np.exp(-t / 0.012)
    echo = np.zeros_like(crack)
    for k, delay in enumerate((0.09, 0.19, 0.31)):
        i = int(delay * SR)
        echo[i:] += crack[: len(crack) - i] * (0.4 / (k + 1))
    save(SFX / "rifle.wav", mix(crack, echo, 0.4 * sweep(160, 60, 0.6) * np.exp(-t / 0.08)))

    def notes(seq, length, shape="square", gap=0.0, decay=0.12):
        parts = []
        for f in seq:
            x = tone(f, length, shape) * env(int(length * SR), 0.004, decay)
            parts.append(pad(x, length + gap))
        return np.concatenate(parts)

    save(SFX / "round.wav", mix(notes([392, 392], 0.28, "saw", 0.02, 0.2), 0.5 * notes([196, 196], 0.28, "sine", 0.02, 0.25)), 0.7)
    save(SFX / "fight.wav", mix(notes([523], 0.5, "saw", 0, 0.25), notes([659], 0.5, "saw", 0, 0.25), notes([784], 0.5, "saw", 0, 0.25), 0.6 * lowpass(noise(0.12), 0.5) * env(int(0.12 * SR), 0.001, 0.03)), 0.75)
    save(SFX / "ko.wav", mix(sweep(300, 50, 0.9, "saw") * env(int(0.9 * SR), 0.002, 0.3) * 0.6, lowpass(noise(0.9), 0.1) * env(int(0.9 * SR), 0.002, 0.25)))
    save(SFX / "time_up.wav", notes([220, 165], 0.3, "square", 0.02, 0.4), 0.6)
    save(SFX / "timer_tick.wav", notes([1320], 0.05, "square", 0, 0.02), 0.35)
    save(SFX / "special_ready.wav", notes([659, 880, 1175, 1568], 0.07, "sine", 0, 0.05), 0.5)
    save(SFX / "ui_move.wav", notes([880], 0.04, "square", 0, 0.015), 0.3)
    save(SFX / "ui_confirm.wav", notes([660, 990], 0.07, "square", 0, 0.04), 0.4)
    save(SFX / "ui_back.wav", notes([660, 440], 0.06, "square", 0, 0.04), 0.35)
    save(SFX / "intro.wav", mix(pad(whoosh_like(0.3), 0.6), pad(np.zeros(int(0.25 * SR)), 0.6) + pad(np.concatenate([np.zeros(int(0.25 * SR)), thump(110, 0.3, 1.0)]), 0.6)), 0.7)
    save(SFX / "win.wav", notes([523, 659, 784, 1047, 784, 1047], 0.14, "square", 0.01, 0.12), 0.5)
    save(SFX / "lose.wav", notes([392, 370, 349, 262], 0.24, "saw", 0.02, 0.2), 0.5)


def whoosh_like(seconds):
    n = noise(seconds)
    return lowpass(n, 0.2) * env(len(n), seconds * 0.6, seconds / 4)


# --------------------------------------------------------------------------
# Music: short loops built from drums, bass, a lead and chord pads
# --------------------------------------------------------------------------
def midi(note):
    return 440.0 * 2 ** ((note - 69) / 12)


class Track:
    def __init__(self, bpm, bars):
        self.beat = 60.0 / bpm
        self.length = int(bars * 4 * self.beat * SR)
        self.buf = np.zeros(self.length + SR)

    def add(self, start_beats, x, gain=1.0):
        i = int(start_beats * self.beat * SR)
        end = min(len(self.buf), i + len(x))
        self.buf[i:end] += x[: end - i] * gain

    def note(self, start, beats, pitch, shape="square", gain=0.3, decay=0.25, attack=0.005):
        secs = beats * self.beat
        x = tone(midi(pitch), secs, shape) * env(int(secs * SR), attack, decay, 0.0, 0.03)
        if shape in ("square", "saw"):
            x = lowpass(x, 0.25)
        self.add(start, x, gain)

    def kick(self, start, gain=0.9):
        x = sweep(150, 45, 0.25) * env(int(0.25 * SR), 0.001, 0.07)
        self.add(start, x, gain)

    def snare(self, start, gain=0.4):
        x = mix(lowpass(noise(0.18), 0.6) * env(int(0.18 * SR), 0.001, 0.05), 0.4 * tone(190, 0.1) * env(int(0.1 * SR), 0.001, 0.03))
        self.add(start, x, gain)

    def hat(self, start, gain=0.12):
        n = noise(0.05)
        x = (n - lowpass(n, 0.3)) * env(len(n), 0.001, 0.012)
        self.add(start, x, gain)

    def taiko(self, start, gain=0.8):
        x = mix(sweep(110, 60, 0.4) * env(int(0.4 * SR), 0.002, 0.12), 0.3 * lowpass(noise(0.1), 0.3) * env(int(0.1 * SR), 0.001, 0.02))
        self.add(start, x, gain)

    def render(self, path, gain=0.8):
        out = self.buf[: self.length].copy()
        tail = self.buf[self.length: self.length + SR]
        out[: len(tail)] += tail  # wrap the tail so the loop is seamless
        save(path, out, gain)


def menu_theme():
    tr = Track(100, 16)
    chords = [(57, 60, 64), (53, 57, 60), (55, 59, 62), (52, 56, 59)]  # Am F G E
    lead = [69, 72, 71, 69, 67, 69, 64, 0, 65, 69, 67, 65, 64, 62, 64, 0]
    for bar in range(16):
        c = chords[bar % 4]
        b = bar * 4
        for p in c:
            tr.note(b, 4, p, "saw", 0.06, 1.2, 0.2)
        tr.note(b, 1.5, c[0] - 12, "square", 0.22, 0.4)
        tr.note(b + 2, 1.5, c[0] - 12, "square", 0.2, 0.4)
        tr.kick(b)
        tr.kick(b + 2.5)
        tr.snare(b + 1)
        tr.snare(b + 3)
        for h in range(8):
            tr.hat(b + h * 0.5)
        if bar >= 4:
            for k in range(4):
                p = lead[(bar * 4 + k) % len(lead)]
                if p:
                    tr.note(b + k, 0.9, p, "square", 0.16, 0.3)
    tr.render(MUSIC / "menu_theme.wav")


def ancient_arena_theme():
    tr = Track(110, 16)
    scale = [62, 63, 66, 67, 69, 70, 72, 74]  # D phrygian dominant flavour
    pattern = [0, 2, 3, 4, 3, 2, 1, 0, 4, 5, 6, 5, 4, 3, 2, 1]
    for bar in range(16):
        b = bar * 4
        tr.note(b, 4, 50, "saw", 0.1, 1.5, 0.3)
        tr.taiko(b)
        tr.taiko(b + 1.5, 0.5)
        tr.taiko(b + 2, 0.7)
        tr.snare(b + 3, 0.25)
        for h in range(8):
            tr.hat(b + h * 0.5, 0.08)
        for k in range(8):
            p = scale[pattern[(bar * 8 + k) % len(pattern)]]
            tr.note(b + k * 0.5, 0.45, p, "sine", 0.22, 0.12)
            if bar % 4 >= 2:
                tr.note(b + k * 0.5, 0.45, p + 12, "square", 0.05, 0.08)
    tr.render(MUSIC / "ancient_arena.wav")


def battlefield_theme():
    tr = Track(132, 16)
    bass = [45, 45, 48, 45, 43, 43, 47, 43]
    for bar in range(16):
        b = bar * 4
        for k in range(8):
            tr.note(b + k * 0.5, 0.45, bass[(bar % 2) * 4 + k // 2], "square", 0.25, 0.1)
        tr.taiko(b)
        tr.taiko(b + 0.75, 0.6)
        tr.taiko(b + 2)
        tr.taiko(b + 2.75, 0.6)
        tr.snare(b + 1, 0.45)
        tr.snare(b + 3, 0.45)
        for h in range(16):
            tr.hat(b + h * 0.25, 0.07)
        if bar % 4 in (2, 3):
            for k, p in enumerate((69, 72, 74, 76)):
                tr.note(b + k, 0.95, p, "saw", 0.12, 0.35)
    tr.render(MUSIC / "battlefield.wav")


def mythic_summit_theme():
    tr = Track(120, 16)
    chords = [(50, 57, 62, 65), (46, 53, 58, 62), (48, 55, 60, 64), (45, 52, 57, 61)]  # Dm Bb C A
    for bar in range(16):
        b = bar * 4
        c = chords[bar % 4]
        for p in c:
            tr.note(b, 4, p, "saw", 0.07, 2.0, 0.4)
            tr.note(b, 4, p + 12, "sine", 0.05, 2.0, 0.4)
        tr.taiko(b, 1.0)
        tr.taiko(b + 1, 0.6)
        tr.taiko(b + 2, 0.9)
        tr.taiko(b + 3, 0.6)
        tr.taiko(b + 3.5, 0.5)
        tr.snare(b + 2, 0.3)
        if bar >= 4:
            melody = [c[3] + 12, c[2] + 12, c[3] + 12, c[1] + 12 + 7]
            for k, p in enumerate(melody):
                tr.note(b + k, 0.95, p, "square", 0.13, 0.4)
    tr.render(MUSIC / "mythic_summit.wav")


if __name__ == "__main__":
    make_sfx()
    menu_theme()
    ancient_arena_theme()
    battlefield_theme()
    mythic_summit_theme()
