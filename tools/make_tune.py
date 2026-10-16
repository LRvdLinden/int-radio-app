#!/usr/bin/env python3
"""Maakt de Tunr-intro-tune (±3,4 s), synchroon met de splash (docs/SPEC.md §3.1):
0–1,4 s   afstemmen: radioruis met zoekende 'fluittonen' (heterodyne) terwijl de naald over de schaal gaat
1,45 s    'klik' + lock: de ruis valt weg, zachte bas-puls (de cirkelgolven)
1,50 s    vier heldere tonen, één per letter T-U-N-R (90 ms uit elkaar)
2,05 s    warm akkoord met sprankel (de glimveeg), uitsterven tot 3,4 s

Schrijft de tune naar alle platforms:
  apple/Shared/Resources/tunr_tune.m4a
  android/app/src/main/res/raw/tunr_tune.m4a
  website/assets/audio/tunr_tune.m4a  (+ .mp3 voor oudere browsers)
"""
import numpy as np, subprocess, pathlib, wave, shutil

SR = 44100
T = 3.4
n = int(SR * T)
t = np.arange(n) / SR
L = np.zeros(n); R = np.zeros(n)
rng = np.random.default_rng(11)


def env(start, attack, decay):
    e = np.zeros(n)
    s = int(start * SR)
    a = max(1, int(attack * SR))
    length = min(n - s, a + int(decay * 7 * SR))
    idx = np.arange(length)
    e[s:s + length] = np.where(idx < a, idx / a, np.exp(-(idx - a) / (decay * SR)))
    return e


def tone(freq, start, attack, decay, amp, harmonics=((1, 1.0), (2, 0.3), (3, 0.1)), detune=0.0):
    e = env(start, attack, decay)
    return amp * e * sum(w * np.sin(2 * np.pi * freq * h * (1 + detune) * t) for h, w in harmonics)


def bandpass(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, len(x))


LOCK = 1.45

# 1. radioruis: band-gefilterd, pulserend (zoals tussen twee zenders), valt weg bij de lock
noise = bandpass(rng.standard_normal(n), 300, 7000)
noise /= np.abs(noise).max()
flutter = 0.65 + 0.35 * np.sin(2 * np.pi * 7 * t) * np.sin(2 * np.pi * 0.9 * t)
gate = np.clip(t / 0.25, 0, 1) * np.where(t < LOCK, 1, np.exp(-(t - LOCK) / 0.03))
static = 0.2 * noise * flutter * gate
L += static * 1.05; R += static * 0.95

# zoekende fluittoon: glijdt omhoog/omlaag met haperingen (de naald), steeds dichter bij 'de zender'
sweep_pts = [(0.0, 2400), (0.35, 900), (0.55, 1500), (0.8, 600), (1.05, 1100), (1.25, 420), (LOCK, 293.66)]
xs, ys = zip(*sweep_pts)
freq = np.interp(t, xs, ys)
ph = 2 * np.pi * np.cumsum(freq) / SR
whistle_env = np.clip((t - 0.05) / 0.2, 0, 1) * np.where(t < LOCK, 1, 0) * (0.5 + 0.5 * np.sin(2 * np.pi * 3.1 * t) ** 2)
whistle = 0.09 * np.sin(ph) * whistle_env
L += whistle * 0.8; R += whistle * 1.2

# korte 'tik'-jes van de afstemknop
for st in (0.35, 0.55, 0.8, 1.05, 1.25):
    click = bandpass(rng.standard_normal(n), 1500, 9000) * env(st, 0.0005, 0.006)
    L += 0.18 * click; R += 0.18 * click

# 2. lock: harde klik + bas-puls die in toonhoogte zakt (de cirkelgolven)
lock_click = bandpass(rng.standard_normal(n), 800, 12000) * env(LOCK, 0.0005, 0.01)
L += 0.5 * lock_click; R += 0.5 * lock_click
bt = np.clip(t - LOCK, 0, None)
boom_f = 60 + 55 * np.exp(-bt / 0.07)
boom = np.sin(2 * np.pi * np.cumsum(boom_f) / SR) * (t >= LOCK) * np.exp(-bt / 0.5) * 0.85
L += boom; R += boom

# 3. vier letters T-U-N-R: D5 F#5 A5 D6 met lichte echo
notes = [587.33, 739.99, 880.0, 1174.66]
for i, f in enumerate(notes):
    st = 1.50 + i * 0.09
    pan = 0.25 + 0.17 * i
    for k, (delay, g) in enumerate(((0, 1.0), (0.18, 0.28))):
        x = tone(f, st + delay, 0.004, 0.17, 0.3 * g, harmonics=((1, 1.0), (2, 0.22), (4, 0.06)))
        p = pan if k == 0 else 1 - pan
        L += x * (1 - p) * 1.4; R += x * p * 1.4

# 4. warm akkoord (Dmaj9, breed door detune) + sprankel tijdens de glimveeg
chord = [146.83, 293.66, 369.99, 440.0, 554.37, 659.25]
for f in chord:
    for d, side in ((-0.0035, 0), (0.0035, 1)):
        x = tone(f, 2.05, 0.04, 0.6, 0.1 if f > 200 else 0.17, harmonics=((1, 1.0), (2, 0.35), (3, 0.12)), detune=d)
        if side == 0: L += x
        else: R += x
for i in range(12):
    st = 2.08 + i * 0.055 + rng.uniform(0, 0.02)
    f = rng.choice([2349.3, 2637.0, 2959.9, 3520.0])
    x = tone(f, st, 0.002, 0.07, 0.045 * (1 - i / 14), harmonics=((1, 1.0),))
    p = rng.uniform(0, 1)
    L += x * (1 - p); R += x * p

# uitfaden en normaliseren
fade = np.clip((T - t) / 0.45, 0, 1)
L *= fade; R *= fade
peak = max(np.abs(L).max(), np.abs(R).max())
L = np.tanh(L / peak * 1.2) * 0.85; R = np.tanh(R / peak * 1.2) * 0.85
pcm = (np.stack([L, R], axis=1) * 32767).astype('<i2')

root = pathlib.Path(__file__).resolve().parent.parent
wav = root / "tools" / "tunr_tune.wav"
with wave.open(str(wav), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())

main = root / "apple/Shared/Resources/tunr_tune.m4a"
main.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "aac", "-b:a", "160k", str(main)], check=True)
for dst in (root / "android/app/src/main/res/raw/tunr_tune.m4a", root / "website/assets/audio/tunr_tune.m4a"):
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(main, dst)
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libmp3lame", "-b:a", "160k",
                str(root / "website/assets/audio/tunr_tune.mp3")], check=True)
wav.unlink()
print("ok", main.stat().st_size)
