"""틀린 사람 찾기 — 효과음·배경음 생성기(§11.3). 표준 라이브러리만 쓰는 결정적 합성이며 외부 샘플을 쓰지 않는다.
사용: py -3 tools/generate_audio.py   → assets/audio/*.wav (22.05 kHz, 16비트, 모노)
"""
import array
import math
import random
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "assets" / "audio"
RATE = 22050
rnd = random.Random(20261012)


def write(name, data, peak=0.85):
    ROOT.mkdir(parents=True, exist_ok=True)
    m = max(1e-6, max(abs(x) for x in data))
    g = peak / m if m > peak else 1.0
    buf = array.array("h", (int(max(-1.0, min(1.0, x * g)) * 32000) for x in data))
    with wave.open(str(ROOT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(buf.tobytes())


def sine(t, f):
    return math.sin(2 * math.pi * f * t)


def lowpass(data, cutoff):
    a = math.exp(-2 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for x in data:
        y = (1 - a) * x + a * y
        out.append(y)
    return out


def env(i, n, attack, release):
    t = i / RATE
    d = n / RATE
    return min(1.0, t / max(attack, 1e-4)) * min(1.0, (d - t) / max(release, 1e-4))


def loop_crossfade(data, fade_s):
    """앞뒤를 겹쳐 이음매 없이 반복되게 한다."""
    f = int(fade_s * RATE)
    body = data[: len(data) - f]
    tail = data[len(data) - f:]
    for i in range(f):
        k = i / f
        body[i] = body[i] * k + tail[i] * (1 - k)
    return body


def n(seconds):
    return int(seconds * RATE)


# ---------------- 배경: 빈 몰의 공조음(반복)
def hvac():
    N = n(10.5)
    noise = [rnd.uniform(-1, 1) for _ in range(N)]
    low = lowpass(lowpass(noise, 300), 300)
    data = [low[i] * 1.6 + 0.05 * sine(i / RATE, 58) + 0.03 * sine(i / RATE, 117) for i in range(N)]
    write("hvac_loop", loop_crossfade(data, 0.5), peak=0.35)


# ---------------- 배경: 아주 작은 매장 음악(반복, 32초, 70 BPM)
def mall_music():
    beat = 60.0 / 70.0
    chords = [[60, 64, 67, 71], [57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 67]]
    bars = 9
    N = n(bars * 4 * beat + 1.0)
    data = [0.0] * N

    def note(start, dur, midi, amp, bell=False):
        f = 440.0 * 2 ** ((midi - 69) / 12)
        s0 = n(start)
        for i in range(n(dur)):
            if s0 + i >= N:
                break
            t = i / RATE
            e = min(1.0, t / 0.03) * math.exp(-t * (2.6 if bell else 0.9))
            v = sine(t, f) + 0.35 * sine(t, 2 * f) + (0.2 * sine(t, 3.01 * f) if bell else 0.08 * sine(t, 3 * f))
            data[s0 + i] += v * e * amp
    for b in range(bars):
        ch = chords[b % 4]
        t0 = b * 4 * beat
        for k, m in enumerate(ch):
            note(t0 + k * 0.02, 4 * beat, m - 12, 0.06)
        note(t0, 4 * beat, ch[0] - 24, 0.07)
        mel = [ch[3] + 12, ch[2] + 12, ch[1] + 12, ch[2] + 12]
        for k in range(4):
            if (b + k) % 3 != 1:
                note(t0 + k * beat, beat * 1.6, mel[k], 0.035, bell=True)
    data = lowpass(data, 3200)
    write("mall_music_loop", loop_crossfade(data, 1.0), peak=0.5)


# ---------------- 안내 방송 차임(딩-동)
def chime_announce():
    N = n(2.6)
    data = [0.0] * N
    for start, f in ((0.0, 659.25), (0.55, 523.25)):
        for i in range(n(2.0)):
            j = n(start) + i
            if j >= N:
                break
            t = i / RATE
            e = math.exp(-t * 2.2) * min(1.0, t / 0.005)
            data[j] += (sine(t, f) + 0.5 * sine(t, 2.76 * f) + 0.25 * sine(t, 5.4 * f)) * e * 0.4
    write("chime_announce", data, peak=0.7)


def chime_hint():
    N = n(0.7)
    data = [(sine(i / RATE, 1318.5) * 0.6 + sine(i / RATE, 1975.5) * 0.25) * math.exp(-i / RATE * 7.0) * min(1, i / 60) for i in range(N)]
    write("chime_hint", data, peak=0.5)


# ---------------- 제거음: 가방이 떨어지는 소리 + 낮은 공기음
def elimination():
    N = n(1.6)
    data = [0.0] * N
    noise = lowpass([rnd.uniform(-1, 1) for _ in range(N)], 500)
    for i in range(N):
        t = i / RATE
        thud = (sine(t, 70 - 30 * t) * 0.9 + noise[i] * 0.8) * math.exp(-t * 18) if t < 0.4 else 0.0
        air = noise[i] * 1.4 * math.sin(math.pi * min(1.0, t / 1.6)) ** 2 * 0.6
        data[i] = thud + air
    write("elimination", data, peak=0.8)


def puddle():
    N = n(1.3)
    data = [0.0] * N
    for k, (t0, f0) in enumerate(((0.05, 180), (0.35, 140), (0.62, 210), (0.9, 120))):
        for i in range(n(0.25)):
            j = n(t0) + i
            if j >= N:
                break
            t = i / RATE
            data[j] += sine(t, f0 + 260 * t) * math.exp(-t * 14) * 0.5
    write("puddle", lowpass(data, 1200), peak=0.5)


def counter_tick():
    N = n(0.28)
    data = [(sine(i / RATE, 520 - 300 * i / N) * 0.7) * math.exp(-i / RATE * 16) for i in range(N)]
    write("counter_tick", data, peak=0.5)


def buzzer():
    N = n(0.55)
    raw = [(1.0 if math.sin(2 * math.pi * 110 * i / RATE) > 0 else -1.0) * env(i, N, 0.01, 0.08) for i in range(N)]
    write("buzzer", lowpass(lowpass(raw, 700), 900), peak=0.55)


def correct():
    N = n(1.0)
    data = [0.0] * N
    for k, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        for i in range(n(0.6)):
            j = n(k * 0.09) + i
            if j >= N:
                break
            t = i / RATE
            data[j] += (sine(t, f) + 0.3 * sine(t, 2 * f)) * math.exp(-t * 5) * 0.35
    write("correct", data, peak=0.65)


def call_murmur():
    """짧은 "…?" 웅얼거림. 모든 NPC가 같은 소리를 쓴다(§11.3)."""
    N = n(0.5)
    data = []
    ph = 0.0
    for i in range(N):
        t = i / RATE
        f0 = 140 + (90 * ((t - 0.3) / 0.2) if t > 0.3 else 0)
        ph += 2 * math.pi * f0 / RATE
        v = sum(math.sin(ph * h) / h for h in range(1, 9))
        v *= 0.6 + 0.4 * math.sin(2 * math.pi * 5 * t)
        data.append(v * env(i, N, 0.04, 0.1))
    write("call_murmur", lowpass(lowpass(data, 900), 1400), peak=0.45)


def footsteps():
    for k in range(3):
        N = n(0.13)
        noise = [rnd.uniform(-1, 1) for _ in range(N)]
        f = 95 + 12 * k
        data = [(noise[i] * 0.5 + sine(i / RATE, f) * 0.6) * math.exp(-i / RATE * 45) for i in range(N)]
        write(f"footstep_{k + 1}", lowpass(data, 1600), peak=0.35)


def lights_flicker():
    N = n(0.6)
    data = []
    for i in range(N):
        t = i / RATE
        gate = 1.0 if int(t * 22) % 3 != 0 else 0.15
        data.append((sine(t, 100) * 0.4 + sine(t, 200) * 0.25 + rnd.uniform(-1, 1) * 0.1) * gate * env(i, N, 0.005, 0.1))
    write("lights_flicker", lowpass(data, 2000), peak=0.4)


def ui_click():
    N = n(0.06)
    write("ui_click", [sine(i / RATE, 900) * math.exp(-i / RATE * 60) for i in range(N)], peak=0.3)


for fn in (hvac, mall_music, chime_announce, chime_hint, elimination, puddle, counter_tick, buzzer, correct, call_murmur, footsteps, lights_flicker, ui_click):
    fn()
print("audio written to", ROOT)
