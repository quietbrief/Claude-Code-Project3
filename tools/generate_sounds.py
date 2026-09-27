#!/usr/bin/env python3
"""Synthesize the bundled sounds.

The real iOS ringtones and the WeChat ringtone are copyrighted, so the app ships
original, synthesized stand-ins. In CallKit mode the iPhone style uses the
system's own ringtone, and every sound can be replaced in the app by importing
an audio file.

Usage: python3 tools/generate_sounds.py
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "iOS", "Resources", "Sounds")


def note_freq(name):
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3,
             "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def marimba(freq, dur):
    t = np.arange(int(SR * dur)) / SR
    tone = (np.sin(2 * np.pi * freq * t) * np.exp(-t * 5.5)
            + 0.35 * np.sin(2 * np.pi * freq * 3.93 * t) * np.exp(-t * 18)
            + 0.12 * np.sin(2 * np.pi * freq * 9.2 * t) * np.exp(-t * 40))
    attack = np.minimum(1, t / 0.004)
    return tone * attack


def bell(freq, dur):
    t = np.arange(int(SR * dur)) / SR
    tone = (np.sin(2 * np.pi * freq * t)
            + 0.45 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t * 6)
            + 0.2 * np.sin(2 * np.pi * freq * 3.01 * t) * np.exp(-t * 10))
    env = np.minimum(1, t / 0.01) * np.exp(-t * 3.2)
    return tone * env


def sequence(events, total, voice):
    buf = np.zeros(int(SR * total))
    for start, name, dur, gain in events:
        s = voice(note_freq(name), dur) * gain
        i = int(SR * start)
        end = min(len(buf), i + len(s))
        buf[i:end] += s[: end - i]
    return buf


def tone(freq, on, off, repeats, gain=0.5, second=None):
    t = np.arange(int(SR * on)) / SR
    s = np.sin(2 * np.pi * freq * t)
    if second:
        s = 0.5 * (s + np.sin(2 * np.pi * second * t))
    fade = np.minimum(1, np.minimum(t, on - t) / 0.01)
    chunk = np.concatenate([s * fade * gain, np.zeros(int(SR * off))])
    return np.tile(chunk, repeats)


def write(name, data):
    peak = np.max(np.abs(data)) or 1
    data = data / peak * 0.85 if peak > 0.85 else data
    pcm = (data * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote", name, f"{len(data) / SR:.1f}s")


def main():
    os.makedirs(OUT, exist_ok=True)

    # Marimba phrase in the spirit of a smartphone ringtone (original melody).
    step = 0.16
    phrase = ["E5", "B5", "G#5", "E6", "B5", "G#5", "C#6", "B5",
              "E5", "B5", "G#5", "E6", "F#6", "E6", "B5", None]
    events = [(i * step, n, 0.9, 0.55) for i, n in enumerate(phrase) if n]
    one = sequence(events, len(phrase) * step + 0.35, marimba)
    write("ring_iphone.wav", np.tile(one, 3))

    # Bright bell melody in the spirit of a messaging-app ringtone (original melody).
    step = 0.19
    phrase = ["G5", "C6", "E6", "G6", None, "E6", "F6", "D6",
              "B5", "D6", "G5", None, "A5", "C6", "E6", "D6", None, "C6", None, None]
    events = [(i * step, n, 0.7, 0.5) for i, n in enumerate(phrase) if n]
    one = sequence(events, len(phrase) * step + 0.2, bell)
    write("ring_wechat.wav", np.tile(one, 3))

    # China ringback tone (450 Hz, 1 s on, 4 s off), used by the iPhone outgoing screen.
    write("ringback_cn.wav", tone(450, 1.0, 4.0, 2, gain=0.35))

    # Softer waiting melody for the WeChat outgoing screen.
    step = 0.28
    phrase = ["E5", "G5", "C6", None, "D6", "C6", "G5", None, None, None]
    events = [(i * step, n, 1.0, 0.35) for i, n in enumerate(phrase) if n]
    write("wait_wechat.wav", sequence(events, len(phrase) * step + 0.4, bell))

    # Hang-up cues.
    write("hangup_iphone.wav", tone(450, 0.2, 0.15, 3, gain=0.4))
    write("hangup_wechat.wav", tone(620, 0.12, 0.08, 2, gain=0.35, second=930))

    # Silent loop that keeps the app alive in the background while armed.
    write("silence.wav", np.zeros(SR))


if __name__ == "__main__":
    main()
