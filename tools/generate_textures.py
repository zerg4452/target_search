"""재질 세부 텍스처(§12.2 텍스처 행, D-33)를 만든다. 모두 이음매 없이 반복되는 무늬다.

사용(저장소 루트에서):
  py tools/generate_textures.py

결과: assets/textures/<이름>_a.png(명도 배율, 회색), _n.png(노멀, OpenGL 방식 +Y 위), _r.png(거칠기 배율, 회색),
      assets/textures/textures.manifest.json(텍스처별 명도 배율의 선형 평균). 게임은 이 평균으로 나눠 팔레트 명도를 지킨다.
- 명도 배율은 평균이 1에 가깝게 만든다(팔레트의 명도 차 ΔL* 검사를 흐리지 않게, §6.6).
- 같은 재질 ID는 같은 텍스처를 쓴다. 개체마다 다른 무늬를 쓰지 않는다(§6.8 공정성).
- 무작위 값은 고정 시드에서 나온다. 다시 만들어도 같은 파일이 나온다.
- Godot 가져오기 설정(.import)도 여기서 맞춘다: 밉맵 생성, VRAM 압축, _n은 노멀맵 압축.
  .import가 없으면 설정만 담은 파일을 쓰고, 있으면 [params]만 고친다. 그 뒤 `godot --headless --path . --import`.
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")


# ============================================================== 반복되는 잡음

def rng(seed):
    return np.random.default_rng(seed)


def fbm(n, seed, beta=2.0, lo=1.0, hi=None, aniso=(1.0, 1.0)):
    """주기 n의 1/f^beta 잡음(FFT라 저절로 이음매가 없다). aniso=(x 배율, y 배율): 배율이 큰 축으로 무늬가 길게 늘어난다."""
    w = rng(seed).standard_normal((n, n))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(n)[:, None] * n * aniso[1]
    kx = np.fft.fftfreq(n)[None, :] * n * aniso[0]
    k = np.sqrt(kx * kx + ky * ky)
    k[0, 0] = 1.0
    amp = 1.0 / np.power(k, beta / 2.0)
    amp[k < lo] = 0.0
    if hi is not None:
        amp[k > hi] = 0.0
    out = np.real(np.fft.ifft2(f * amp))
    out -= out.min()
    out /= max(out.max(), 1e-9)
    return out


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float64) / n
    return x, y


def normal_from_height(h, strength):
    """높이(0~1, 픽셀 단위 기울기에 strength를 곱함) → OpenGL 노멀(초록 = 위)."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    drow = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
    nx, ny, nz = -dx, drow, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5
    return rgb


def save_gray(name, a):
    Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "L").save(os.path.join(OUT, name))


def save_rgb(name, a):
    Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name))


STATS = {}


def srgb_to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, np.power((a + 0.055) / 1.055, 2.4))


def write_set(name, height, strength, albedo, rough):
    """albedo·rough는 배율(0~1). 평균을 맞춘 뒤 저장한다."""
    q = np.round(np.clip(albedo, 0, 1) * 255.0) / 255.0
    STATS[name] = {"albedo_linear_mean": round(float(srgb_to_linear(q).mean()), 5)}
    save_rgb(f"{name}_n.png", normal_from_height(height, strength))
    save_gray(f"{name}_a.png", albedo)
    save_gray(f"{name}_r.png", rough)
    print(f"  {name}: albedo 평균 {albedo.mean():.3f}, 거칠기 평균 {rough.mean():.3f}")


def around(base, amount, mean):
    """0~1 무늬를 평균 mean, 진폭 amount인 배율로."""
    v = base - base.mean()
    v = v / max(np.abs(v).max(), 1e-9)
    return np.clip(mean + v * amount, 0.0, 1.0)


# ============================================================== 옷·사람(NPC, 512 px)

def knit(n=512):
    """니트(후드): 세로 줄 코(V자)가 반복. 텍스처 한 장 = 12 cm, 코 24줄."""
    x, y = grid(n)
    cols, rows = 24, 32
    u = (x * cols) % 1.0
    v = (y * rows) % 1.0
    vshape = np.abs(u - 0.5) * 2.0                    # 코 한 줄 안에서 가운데가 낮다
    loop = np.sin(np.pi * ((v + vshape * 0.5) % 1.0))  # V자로 기운 고리
    h = 0.65 * loop * (1.0 - 0.35 * vshape) + 0.35 * fbm(n, 11, 1.2, lo=24)
    alb = around(h + 0.4 * fbm(n, 12, 2.0, lo=2, hi=40), 0.06, 0.97)
    rough = around(fbm(n, 13, 1.5, lo=8), 0.05, 0.96)
    write_set("knit", h, 6.0, alb, rough)


def twill(n=512):
    """능직(청바지·면바지): 사선 골. 텍스처 한 장 = 8 cm. 실 굵기 얼룩(슬럽)은 세로로 길다."""
    x, y = grid(n)
    k = 64
    rib = 0.5 + 0.5 * np.sin(2 * np.pi * k * (x + y))
    slub = fbm(n, 21, 2.0, lo=2, aniso=(1.0, 8.0))
    h = 0.7 * rib + 0.3 * fbm(n, 22, 1.0, lo=40)
    alb = around(0.6 * slub + 0.25 * rib + 0.15 * fbm(n, 23, 1.0, lo=60), 0.09, 0.97)
    rough = around(fbm(n, 24, 1.2, lo=12), 0.05, 0.96)
    write_set("twill", h, 4.0, alb, rough)


def wool(n=512):
    """모직(코트): 보송한 잔털 잡음과 아주 옅은 능직. 텍스처 한 장 = 10 cm."""
    x, y = grid(n)
    fuzz = fbm(n, 31, 1.0, lo=60)
    rib = 0.5 + 0.5 * np.sin(2 * np.pi * 48 * (x - y))
    h = 0.6 * fuzz + 0.25 * rib + 0.15 * fbm(n, 32, 2.0, lo=4)
    alb = around(0.6 * fbm(n, 33, 1.8, lo=3) + 0.4 * fuzz, 0.06, 0.98)
    rough = around(fuzz, 0.04, 0.98)
    write_set("wool", h, 2.5, alb, rough)


def suiting(n=512):
    """정장 원단: 가는 헤링본. 텍스처 한 장 = 6 cm."""
    x, y = grid(n)
    band = np.floor(x * 16) % 2
    dirn = np.where(band > 0, 1.0, -1.0)
    rib = 0.5 + 0.5 * np.sin(2 * np.pi * 96 * (y + dirn * x))
    h = 0.7 * rib + 0.3 * fbm(n, 41, 1.0, lo=60)
    alb = around(0.5 * rib + 0.5 * fbm(n, 42, 1.8, lo=3), 0.05, 0.98)
    rough = around(fbm(n, 43, 1.2, lo=10), 0.04, 0.97)
    write_set("suiting", h, 2.5, alb, rough)


def nylon(n=512):
    """나일론(패딩 조끼·가방): 매끈한 바탕에 잔주름. 텍스처 한 장 = 20 cm."""
    crinkle = fbm(n, 51, 2.6, lo=3, aniso=(1.0, 0.6))
    h = crinkle + 0.08 * fbm(n, 52, 1.0, lo=80)
    alb = around(crinkle, 0.04, 0.98)
    rough = around(1.0 - crinkle, 0.12, 0.92)
    write_set("nylon", h, 7.0, alb, rough)


def cotton(n=512):
    """평직 면(셔츠·양말·끈·모자): 아주 가는 바둑판 결. 텍스처 한 장 = 5 cm."""
    x, y = grid(n)
    weave = (0.5 + 0.5 * np.sin(2 * np.pi * 96 * x)) * (0.5 + 0.5 * np.sin(2 * np.pi * 96 * y))
    h = 0.6 * weave + 0.4 * fbm(n, 61, 1.0, lo=50)
    alb = around(0.5 * fbm(n, 62, 1.8, lo=3) + 0.5 * weave, 0.04, 0.98)
    rough = around(fbm(n, 63, 1.2, lo=10), 0.04, 0.97)
    write_set("cotton", h, 2.0, alb, rough)


def leather(n=512):
    """가죽(신발·가방·벨트): 오돌토돌한 낟알 주름. 텍스처 한 장 = 8 cm."""
    a = fbm(n, 71, 1.6, lo=20)
    grain = 1.0 - np.abs(a * 2.0 - 1.0)   # 능선 잡음
    h = 0.75 * grain + 0.25 * fbm(n, 72, 2.0, lo=3)
    alb = around(0.6 * grain + 0.4 * fbm(n, 73, 2.0, lo=2), 0.07, 0.97)
    rough = around(1.0 - grain, 0.15, 0.9)
    write_set("leather", h, 5.0, alb, rough)


def skin(n=512):
    """피부: 아주 옅은 모공과 얼룩. 텍스처 한 장 = 6 cm."""
    pores = fbm(n, 81, 0.8, lo=90)
    blot = fbm(n, 82, 2.2, lo=2)
    h = 0.5 * pores + 0.5 * blot
    alb = around(blot, 0.03, 0.99)
    rough = around(pores, 0.06, 0.95)
    write_set("skin", h, 1.2, alb, rough)


def hair(n=512):
    """머리카락: 세로로 길게 늘인 가닥. 텍스처 한 장 = 8 cm."""
    strands = fbm(n, 91, 1.3, lo=6, aniso=(1.0, 20.0))
    clump = fbm(n, 92, 2.0, lo=2, aniso=(1.0, 5.0))
    h = 0.7 * strands + 0.3 * clump
    alb = around(0.6 * strands + 0.4 * clump, 0.10, 0.96)
    rough = around(1.0 - strands, 0.10, 0.92)
    write_set("hair", h, 5.0, alb, rough)


def smooth(n=64):
    """무늬 없음(플라스틱·금속 장신구·인쇄물·눈썹). 모든 NPC 재질이 같은 셰이더를 쓰도록 빈 텍스처를 둔다."""
    h = np.zeros((n, n))
    write_set("smooth", h, 0.0, np.ones((n, n)), np.ones((n, n)))


# ============================================================== 아레나(월드 좌표 삼면 투영)

def marble_tile(n=1024):
    """돌 타일 바닥: 텍스처 한 장 = 2 m(바둑판 한 칸). 1 m 타일 4장과 4 mm 줄눈, 옅은 대리석 결."""
    x, y = grid(n)
    warp = fbm(n, 101, 2.2, lo=1)
    vein = np.power(1.0 - np.abs(np.sin(np.pi * (x * 2 + y * 3 + warp * 2.2))), 10)   # 가는 결(0~1, 결 위가 1)
    cloud = fbm(n, 102, 2.4, lo=1)
    # 줄눈: 1 m(= n/2 px)마다. 폭 4 mm = n/500 px.
    gw = max(2, n // 500)
    gx = (np.arange(n) % (n // 2)) < gw
    g = np.logical_or(gx[None, :], gx[:, None])
    # 타일마다 아주 조금 다른 밝기(같은 맵이면 늘 같다)
    tile_id = (np.floor(x * 2) + np.floor(y * 2) * 2).astype(int)
    tile_shift = np.array([0.0, 0.025, -0.02, 0.012])[tile_id]
    h = 0.85 - 0.6 * g + 0.03 * fbm(n, 103, 1.0, lo=100)
    alb = np.clip(0.95 + (cloud - cloud.mean()) * 0.10 - vein * 0.16 + tile_shift, 0, 1)
    alb = np.where(g, 0.55, alb)
    rough = np.clip(0.55 + 0.35 * fbm(n, 104, 2.0, lo=2) + 0.1 * vein, 0, 1)
    rough = np.where(g, 1.0, rough)
    write_set("marble_tile", h, 10.0, alb, rough)


def plaster(n=512):
    """회벽·천장: 넓은 흙손 자국. 텍스처 한 장 = 2 m."""
    h = 0.6 * fbm(n, 111, 2.4, lo=2) + 0.4 * fbm(n, 112, 1.2, lo=40)
    alb = around(fbm(n, 113, 2.4, lo=1), 0.04, 0.98)
    rough = around(fbm(n, 114, 2.0, lo=3), 0.06, 0.95)
    write_set("plaster", h, 2.5, alb, rough)


def ceiling_panel(n=512):
    """천장 흡음판: 0.6 m 격자와 잔구멍. 텍스처 한 장 = 1.2 m(2×2판)."""
    x, y = grid(n)
    gw = max(2, n // 150)
    gx = (np.arange(n) % (n // 2)) < gw
    g = np.logical_or(gx[None, :], gx[:, None])
    dots = fbm(n, 121, 0.6, lo=120)
    h = np.where(g, 0.0, 0.85 + 0.15 * dots)
    alb = np.where(g, 0.72, around(dots, 0.04, 0.98))
    rough = np.ones((n, n))
    write_set("ceiling_panel", h, 6.0, alb, rough)


def brushed_metal(n=512):
    """헤어라인 금속(셔터·난간·에스컬레이터): 가로로 긴 결. 텍스처 한 장 = 0.5 m."""
    lines = fbm(n, 131, 1.2, lo=8, aniso=(30.0, 1.0))
    h = 0.8 * lines + 0.2 * fbm(n, 132, 2.0, lo=2)
    alb = around(lines, 0.05, 0.97)
    rough = around(lines, 0.18, 0.85)
    write_set("brushed_metal", h, 2.0, alb, rough)


def wood(n=512):
    """나무(벤치): 결이 가로로 흐른다. 텍스처 한 장 = 0.8 m."""
    x, y = grid(n)
    warp = fbm(n, 141, 2.4, lo=1, aniso=(4.0, 1.0))
    rings = 0.5 + 0.5 * np.sin(2 * np.pi * (y * 6 + warp * 0.8))
    fiber = fbm(n, 142, 1.0, lo=30, aniso=(25.0, 1.0))
    h = 0.6 * rings + 0.4 * fiber
    alb = around(0.6 * rings + 0.4 * fiber, 0.10, 0.88)
    rough = around(1.0 - rings, 0.12, 0.9)
    write_set("wood", h, 3.0, alb, rough)


def stone(n=512):
    """화강암(분수·기둥 받침): 잔알갱이 얼룩. 텍스처 한 장 = 1 m."""
    speck = fbm(n, 151, 0.4, lo=80)
    cloud = fbm(n, 152, 2.2, lo=2)
    h = 0.5 * speck + 0.5 * cloud
    alb = around(0.6 * speck + 0.4 * cloud, 0.12, 0.96)
    rough = around(speck, 0.12, 0.88)
    write_set("stone", h, 2.0, alb, rough)


def terracotta(n=512):
    """토기 화분: 거친 잡음. 텍스처 한 장 = 0.6 m."""
    h = 0.6 * fbm(n, 161, 1.0, lo=40) + 0.4 * fbm(n, 162, 2.2, lo=2)
    alb = around(fbm(n, 163, 2.0, lo=2), 0.1, 0.96)
    rough = around(h, 0.06, 0.97)
    write_set("terracotta", h, 3.0, alb, rough)


def leaves(n=512):
    """화분 잎 덩어리: 겹친 잎 모양 요철. 텍스처 한 장 = 0.5 m."""
    a = fbm(n, 171, 1.8, lo=10)
    cells = 1.0 - np.abs(a * 2.0 - 1.0)
    h = np.power(cells, 0.6)
    alb = around(0.7 * cells + 0.3 * fbm(n, 172, 2.0, lo=2), 0.22, 0.92)
    rough = around(1.0 - cells, 0.1, 0.9)
    write_set("leaves", h, 8.0, alb, rough)


def painted(n=512):
    """도장한 판(키오스크·광고판 테두리): 오렌지 껍질 같은 잔물결. 텍스처 한 장 = 1 m."""
    h = fbm(n, 181, 1.6, lo=30)
    alb = around(fbm(n, 182, 2.4, lo=1), 0.03, 0.99)
    rough = around(h, 0.08, 0.92)
    write_set("painted", h, 1.5, alb, rough)


def water(n=512):
    """분수 물결 노멀. 텍스처 한 장 = 1.5 m. 표시 코드가 두 방향으로 흘린다."""
    h = 0.6 * fbm(n, 191, 2.8, lo=2) + 0.4 * fbm(n, 192, 2.0, lo=6)
    write_set("water", h, 9.0, np.ones((n, n)), np.ones((n, n)))


# ============================================================== 광고판·안내판 그림(빛나는 화면)

FONT_CANDIDATES = [
    # Blender에 들어 있는 Inter(SIL OFL 1.1). 글꼴 파일은 저장소에 넣지 않고 그린 그림만 남긴다.
    os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "Blender Foundation", "Blender 5.2", "5.2", "datafiles", "fonts", "Inter.woff2"),
]


def _font(size):
    from PIL import ImageFont
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                pass
    return None


def _gradient(w, h, c0, c1, diagonal=True):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    t = (x / w * 0.6 + y / h * 0.4) if diagonal else y / h
    t = np.clip(t, 0, 1)[..., None]
    return np.array(c0)[None, None, :] * (1 - t) + np.array(c1)[None, None, :] * t


def _text(draw, xy, s, size, fill, anchor="la"):
    f = _font(size)
    if f is not None:
        draw.text(xy, s, font=f, fill=fill, anchor=anchor)


def posters():
    """광고판(AD, 3.7 x 1.55 m)과 안내판(S, 2.3 x 1.32 m) 화면. 모든 맵 장식이며 판정과 무관하다."""
    from PIL import ImageDraw
    w, h = 1024, 432
    # 1) 세일 광고: 자홍 → 주황
    a = _gradient(w, h, (0.85, 0.18, 0.45), (0.98, 0.55, 0.20))
    im = Image.fromarray((a * 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(im)
    for i, (cx, cy, r) in enumerate(((820, 90, 150), (930, 330, 110), (700, 380, 70))):
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 235, 200) if i % 2 == 0 else (255, 120, 90))
    _text(d, (60, 70), "ECHO MALL", 44, (255, 240, 225))
    _text(d, (56, 130), "GRAND SALE", 120, (255, 255, 255))
    _text(d, (60, 280), "UP TO 50% OFF", 64, (255, 230, 120))
    _text(d, (60, 370), "ALL FLOORS · THIS WEEKEND", 30, (255, 225, 210))
    im.save(os.path.join(OUT, "poster_sale.png"))
    # 2) 새 시즌 광고: 청록 → 남색, 사선 띠
    a = _gradient(w, h, (0.10, 0.62, 0.70), (0.10, 0.18, 0.45))
    im = Image.fromarray((a * 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(im)
    for k in range(6):
        x0 = 560 + k * 80
        d.polygon([(x0, h), (x0 + 60, h), (x0 + 260, 0), (x0 + 200, 0)], fill=(40 + k * 20, 200 - k * 10, 210))
    _text(d, (60, 80), "NEW SEASON", 110, (255, 255, 255))
    _text(d, (64, 220), "COLLECTION 2026", 54, (200, 245, 250))
    _text(d, (64, 330), "2F  ·  ATRIUM WEST", 34, (180, 220, 235))
    im.save(os.path.join(OUT, "poster_season.png"))
    # 3) 안내판 A: 층별 안내
    w2, h2 = 1024, 588
    a = _gradient(w2, h2, (0.13, 0.15, 0.19), (0.08, 0.09, 0.12), diagonal=False)
    im = Image.fromarray((a * 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(im)
    _text(d, (50, 40), "DIRECTORY", 64, (255, 255, 255))
    d.rectangle((50, 125, 974, 129), fill=(240, 180, 60))
    rows = [("2F", "FASHION  ·  SHOES  ·  OPTICS", (90, 170, 240)), ("1F", "CAFE  ·  BOOKS  ·  DELI  ·  TOYS", (240, 160, 90)),
            ("B1", "FOOD HALL  ·  PARKING", (130, 210, 140))]
    for i, (fl, txt, col) in enumerate(rows):
        y0 = 170 + i * 130
        d.rounded_rectangle((50, y0, 170, y0 + 96), radius=14, fill=col)
        _text(d, (110, y0 + 48), fl, 56, (20, 20, 24), anchor="mm")
        _text(d, (200, y0 + 22), txt, 40, (235, 235, 240))
    im.save(os.path.join(OUT, "poster_directory.png"))
    # 4) 안내판 B: 길 안내
    a = _gradient(w2, h2, (0.95, 0.95, 0.93), (0.82, 0.83, 0.84), diagonal=False)
    im = Image.fromarray((a * 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(im)
    signs = [("WC", "←"), ("LIFT", "→"), ("EXIT", "↓"), ("INFO", "↑")]
    for i, (label, arrow) in enumerate(signs):
        y0 = 50 + i * 132
        d.rounded_rectangle((50, y0, 974, y0 + 110), radius=16, fill=(30, 110, 70) if label == "EXIT" else (40, 60, 110))
        _text(d, (90, y0 + 55), label, 64, (255, 255, 255), anchor="lm")
        _text(d, (930, y0 + 55), arrow, 72, (255, 255, 255), anchor="rm")
    im.save(os.path.join(OUT, "poster_wayfinding.png"))
    # 5) 키오스크 메뉴 띠(2.9 x 0.26 m)
    for name, title, items, c0, c1 in (("menu_coffee", "ECHO COFFEE", "ESPRESSO · LATTE · TEA", (0.30, 0.18, 0.12), (0.55, 0.32, 0.18)),
                                       ("menu_juice", "FRESH JUICE", "ORANGE · BERRY · MANGO", (0.10, 0.45, 0.70), (0.20, 0.70, 0.75)),
                                       ("menu_icecream", "GELATO", "VANILLA · MINT · CHOCO", (0.25, 0.55, 0.35), (0.75, 0.85, 0.55)),
                                       ("menu_phone", "PHONE & CASE", "REPAIR · ACCESSORIES", (0.55, 0.30, 0.10), (0.90, 0.60, 0.20))):
        w3, h3 = 1024, 96
        a3 = _gradient(w3, h3, c0, c1)
        im = Image.fromarray((a3 * 255).astype(np.uint8), "RGB")
        d = ImageDraw.Draw(im)
        _text(d, (24, h3 // 2), title, 54, (255, 255, 255), anchor="lm")
        _text(d, (1000, h3 // 2), items, 30, (255, 245, 230), anchor="rm")
        im.save(os.path.join(OUT, name + ".png"))
    print("  광고판·안내판·메뉴 그림 8장")


IMPORT_PARAMS = {
    "compress/mode": "2",
    "compress/high_quality": "false",
    "mipmaps/generate": "true",
    "detect_3d/compress_to": "0",
}


def write_import(png_name):
    """Godot 가져오기 설정. 세부 텍스처는 작게 반복되므로 밉맵이 없으면 멀리서 지글거린다."""
    path = os.path.join(OUT, png_name + ".import")
    params = dict(IMPORT_PARAMS)
    params["compress/normal_map"] = "1" if png_name.endswith("_n.png") else "2"
    if not os.path.exists(path):
        lines = ["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[deps]", "",
                 f'source_file="res://assets/textures/{png_name}"', "", "[params]", ""]
        lines += [f"{k}={v}" for k, v in params.items()]
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
        return
    with open(path, encoding="utf-8") as fh:
        text = fh.read().split("\n")
    out = []
    for ln in text:
        key = ln.split("=", 1)[0]
        if key in params:
            ln = f"{key}={params.pop(key)}"
        out.append(ln)
    if params:
        i = out.index("[params]") + 2 if "[params]" in out else len(out)
        for k, v in params.items():
            out.insert(i, f"{k}={v}")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out))


def main():
    os.makedirs(OUT, exist_ok=True)
    print("NPC 재질")
    for f in (knit, twill, wool, suiting, nylon, cotton, leather, skin, hair, smooth):
        f()
    print("아레나 재질")
    for f in (marble_tile, plaster, ceiling_panel, brushed_metal, wood, stone, terracotta, leaves, painted, water):
        f()
    posters()
    with open(os.path.join(OUT, "textures.manifest.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"version": 1, "generator": "tools/generate_textures.py", "textures": STATS}, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".png"):
            write_import(f)


if __name__ == "__main__":
    main()
