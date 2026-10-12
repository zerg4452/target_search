"""에코 몰 아트리움(§9) 아트를 data/maps/atrium.json의 배치 그대로 만든다.

사용(저장소 루트에서):
  blender --background --factory-startup --python tools/blender/build_arena_atrium.py

좌표: Godot (x, y, z) = Blender (x, z, -y). 배치 JSON의 center [x, z]는 Godot 바닥 좌표다.
차폐물(높이 2 m 이상)은 반드시 불투명한 OCC_<id> 노드로 만들고, 시뮬레이션의 차폐 부피를 빈틈없이 덮는다(I-03).
그래서 화면에서 가려 보이는 범위가 판정에서 가려졌다고 보는 범위보다 넓거나 같다.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import npc_common as nc  # noqa: E402

CEILING = 9.0
GALLERY_Z = 5.0
SEG = 24

PALETTE = {
    "floor_light": {"color": [0.80, 0.77, 0.71], "roughness": 0.35},
    "floor_dark": {"color": [0.69, 0.67, 0.63], "roughness": 0.35},
    "floor_inlay": {"color": [0.36, 0.33, 0.30], "roughness": 0.3},
    "wall_plaster": {"color": [0.86, 0.83, 0.77], "roughness": 0.9},
    "pilaster": {"color": [0.74, 0.71, 0.66], "roughness": 0.6},
    "shutter": {"color": [0.55, 0.57, 0.60], "roughness": 0.45, "metallic": 0.6},
    "shutter_dark": {"color": [0.32, 0.33, 0.36], "roughness": 0.5, "metallic": 0.5},
    "sign_band": {"color": [0.20, 0.21, 0.23], "roughness": 0.6},
    "sign_a": {"color": [0.95, 0.55, 0.35], "roughness": 0.5, "emission": 1.2},
    "sign_b": {"color": [0.45, 0.75, 0.95], "roughness": 0.5, "emission": 1.2},
    "sign_c": {"color": [0.95, 0.88, 0.55], "roughness": 0.5, "emission": 1.2},
    "sign_d": {"color": [0.70, 0.95, 0.70], "roughness": 0.5, "emission": 1.2},
    "pillar": {"color": [0.88, 0.86, 0.82], "roughness": 0.5},
    "pillar_trim": {"color": [0.50, 0.46, 0.40], "roughness": 0.4, "metallic": 0.4},
    "kiosk_red": {"color": [0.78, 0.30, 0.24], "roughness": 0.55},
    "kiosk_blue": {"color": [0.24, 0.44, 0.78], "roughness": 0.55},
    "kiosk_green": {"color": [0.30, 0.60, 0.36], "roughness": 0.55},
    "kiosk_orange": {"color": [0.90, 0.62, 0.20], "roughness": 0.55},
    "kiosk_top": {"color": [0.95, 0.94, 0.90], "roughness": 0.5, "emission": 0.6},
    "counter": {"color": [0.90, 0.88, 0.84], "roughness": 0.4},
    "board_frame": {"color": [0.25, 0.26, 0.28], "roughness": 0.4, "metallic": 0.5},
    "escalator": {"color": [0.42, 0.44, 0.48], "roughness": 0.4, "metallic": 0.6},
    "escalator_panel": {"color": [0.70, 0.72, 0.75], "roughness": 0.3, "metallic": 0.3},
    "barrier": {"color": [0.85, 0.20, 0.15], "roughness": 0.5},
    "fountain_stone": {"color": [0.70, 0.69, 0.67], "roughness": 0.5},
    "water": {"color": [0.12, 0.28, 0.40], "roughness": 0.05},
    "bench_wood": {"color": [0.52, 0.36, 0.22], "roughness": 0.7},
    "metal_dark": {"color": [0.15, 0.15, 0.16], "roughness": 0.4, "metallic": 0.7},
    "planter": {"color": [0.60, 0.40, 0.30], "roughness": 0.8},
    "foliage": {"color": [0.24, 0.45, 0.25], "roughness": 0.85},
    "ceiling": {"color": [0.90, 0.89, 0.86], "roughness": 0.9},
    "skylight": {"color": [0.80, 0.88, 0.95], "roughness": 0.2, "emission": 1.6},
    "gallery": {"color": [0.80, 0.78, 0.74], "roughness": 0.7},
    "rail": {"color": [0.30, 0.31, 0.33], "roughness": 0.3, "metallic": 0.7},
    "alcove_wall": {"color": [0.72, 0.66, 0.58], "roughness": 0.8},
    "alcove_sign": {"color": [0.95, 0.95, 0.95], "roughness": 0.5, "emission": 0.8},
    "emergency": {"color": [0.85, 0.12, 0.08], "roughness": 0.5},
    "sign_text": {"color": [1.0, 0.98, 0.94], "roughness": 0.4, "emission": 2.4},
    "lamp_shade": {"color": [0.18, 0.18, 0.19], "roughness": 0.35, "metallic": 0.8},
    "lamp_glow": {"color": [1.0, 0.94, 0.84], "roughness": 0.3, "emission": 6.0},
    "screen_sale": {"color": [0.9, 0.4, 0.4], "roughness": 0.3, "emission": 1.0},
    "screen_season": {"color": [0.2, 0.5, 0.7], "roughness": 0.3, "emission": 1.0},
    "screen_directory": {"color": [0.15, 0.16, 0.2], "roughness": 0.3, "emission": 1.0},
    "screen_wayfinding": {"color": [0.85, 0.85, 0.85], "roughness": 0.3, "emission": 1.0},
    "menu_coffee": {"color": [0.3, 0.2, 0.15], "roughness": 0.3, "emission": 1.0},
    "menu_juice": {"color": [0.2, 0.4, 0.6], "roughness": 0.3, "emission": 1.0},
    "menu_icecream": {"color": [0.3, 0.5, 0.3], "roughness": 0.3, "emission": 1.0},
    "menu_phone": {"color": [0.5, 0.35, 0.15], "roughness": 0.3, "emission": 1.0},
    "glass": {"color": [0.72, 0.82, 0.86], "roughness": 0.05},
    "shop_floor": {"color": [0.62, 0.48, 0.34], "roughness": 0.5},
    "shop_wall": {"color": [0.90, 0.88, 0.84], "roughness": 0.8},
    "shop_shelf": {"color": [0.24, 0.22, 0.21], "roughness": 0.5, "metallic": 0.3},
    "shop_light": {"color": [1.0, 0.96, 0.88], "roughness": 0.3, "emission": 3.0},
    "prod_1": {"color": [0.85, 0.30, 0.25], "roughness": 0.5},
    "prod_2": {"color": [0.95, 0.80, 0.30], "roughness": 0.5},
    "prod_3": {"color": [0.25, 0.50, 0.80], "roughness": 0.5},
    "prod_4": {"color": [0.30, 0.65, 0.45], "roughness": 0.5},
    "prod_5": {"color": [0.92, 0.90, 0.86], "roughness": 0.5},
    "prod_6": {"color": [0.20, 0.20, 0.22], "roughness": 0.5},
    "beam": {"color": [0.88, 0.87, 0.84], "roughness": 0.85},
    "ceiling_glow": {"color": [1.0, 0.97, 0.92], "roughness": 0.3, "emission": 1.6},
    "water_jet": {"color": [0.85, 0.93, 1.0], "roughness": 0.05},
}
KIOSK_MENU = {"K1": "menu_coffee", "K2": "menu_juice", "K3": "menu_icecream", "K4": "menu_phone"}
SHOP_NAMES = ["ECHO CAFE", "BOOKS", "SHOES", "OPTICS", "DELI", "TOYS", "ATELIER", "PHONES", "FLORIST", "BAKERY", "SPORTS", "MUSIC"]
KIOSK_MAT = {"K1": "kiosk_red", "K2": "kiosk_blue", "K3": "kiosk_green", "K4": "kiosk_orange"}


def B(x, z, h=0.0):
    """Godot 바닥 좌표 (x, z)와 높이 h를 Blender 좌표로."""
    return Vector((x, -z, h))


def make_materials():
    out = {}
    for mid, d in PALETTE.items():
        m = bpy.data.materials.new(mid)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        lin = [nc.srgb_to_linear(v) for v in d["color"]]
        bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
        bsdf.inputs["Roughness"].default_value = d.get("roughness", 0.8)
        bsdf.inputs["Metallic"].default_value = d.get("metallic", 0.0)
        if d.get("emission", 0.0) > 0.0:
            bsdf.inputs["Emission Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
            bsdf.inputs["Emission Strength"].default_value = d["emission"]
        out[mid] = m
    return out


def screen_quad(part, center, normal, width, height, surface):
    """normal 쪽을 보는 화면 한 장(UV 0~1, 앞에서 볼 때 왼쪽 위가 그림의 왼쪽 위). 게임이 그림 텍스처를 입힌다."""
    n = Vector(normal).normalized()
    right = (-n).cross(Vector((0, 0, 1))).normalized()   # 앞에서 보는 사람의 오른쪽
    up = Vector((0, 0, 1))
    c = Vector(center)
    b = bmesh.new()
    uv = b.loops.layers.uv.new("UVMap")
    corners = [(c - right * width / 2 - up * height / 2, (0, 0)), (c + right * width / 2 - up * height / 2, (1, 0)),
               (c + right * width / 2 + up * height / 2, (1, 1)), (c - right * width / 2 + up * height / 2, (0, 1))]
    vs = [b.verts.new(p) for p, _ in corners]
    f = b.faces.new(vs)
    f.normal_update()
    if f.normal.dot(n) < 0:
        f.normal_flip()
    for loop in f.loops:
        for (p, t), v in zip(corners, vs):
            if loop.vert is v:
                loop[uv].uv = t
    part.add_bm(b, Matrix.Identity(4), "_static", surface, False)


def wall_with_openings(part, x_lo, x_hi, wall_z, inward, th, height, openings, surface):
    """두께 th의 벽(아레나 쪽 면이 wall_z)을 openings[(x0, x1, z0, z1)] 구멍을 남기고 상자로 채운다."""
    cz = wall_z - inward * th / 2
    xs = sorted({x_lo, x_hi} | {o[0] for o in openings} | {o[1] for o in openings})
    for xa, xb in zip(xs, xs[1:]):
        if xb - xa < 1e-4:
            continue
        xm = (xa + xb) / 2
        holes = sorted((o[2], o[3]) for o in openings if o[0] <= xm <= o[1])
        z = 0.0
        for za, zb in holes + [(height, height)]:
            if za - z > 1e-4:
                part.box(B(xm, cz, (z + za) / 2), (xb - xa, th, za - z), "_static", surface)
            z = max(z, zb)


def shop_room(room, glass, frames, lights, cx, wall_z, inward, th, z_floor, height, depth, seed, S, lit_name=None):
    """벽 구멍 뒤의 상점 내부(아레나 밖이라 걸어 들어갈 수 없다): 바닥·벽·천장·조명판, 선반과 상품, 가운데 진열대,
    벽 구멍의 유리와 문틀. 장식일 뿐 판정과 무관하다."""
    import random
    rnd = random.Random(seed)
    w = 5.0
    back = wall_z - inward * th
    far = back - inward * depth
    mid = (back + far) / 2
    zc = z_floor + height / 2
    room.box(B(cx, mid, z_floor - 0.02), (w + 0.2, depth, 0.04), "_static", S["shop_floor"])
    room.box(B(cx, mid, z_floor + height + 0.02), (w + 0.2, depth, 0.04), "_static", S["shop_wall"])
    room.box(B(cx, far - inward * 0.02, zc), (w + 0.2, 0.04, height), "_static", S["shop_wall"])
    for sx in (-1.0, 1.0):
        room.box(B(cx + sx * (w / 2 + 0.08), mid, zc), (0.04, depth, height), "_static", S["shop_wall"])
    for lx in (-1.2, 1.2):
        room.box(B(cx + lx, mid, z_floor + height - 0.01), (1.6, 0.5, 0.02), "_static", S["shop_light"])
    # 뒷벽 선반 3칸과 옆벽 선반
    units = [(cx + ox, far - inward * 0.22, 1.45, 0.36, "x") for ox in (-1.6, 0.0, 1.6)]
    for sx in (-1.0, 1.0):
        units.append((cx + sx * (w / 2 - 0.2), mid + inward * 0.4, 0.36, depth - 1.4, "z"))
    for ux, uz, uw, ud, axis in units:
        sh = min(2.1, height - 0.4)
        size_back = (uw, 0.03, sh) if axis == "x" else (0.03, ud, sh)
        room.box(B(ux, uz - inward * (0.16 if axis == "x" else 0.0), z_floor + sh / 2), size_back, "_static", S["shop_shelf"])
        for lev in range(4):
            zb = z_floor + 0.25 + lev * (sh - 0.3) / 3.5
            room.box(B(ux, uz, zb), (uw, 0.34, 0.03) if axis == "x" else (0.34, ud, 0.03), "_static", S["shop_shelf"])
            span = uw if axis == "x" else ud
            t = -span / 2 + 0.06
            while t < span / 2 - 0.08:
                iw = rnd.uniform(0.06, 0.22)
                ih = rnd.uniform(0.08, 0.26)
                idp = rnd.uniform(0.12, 0.26)
                mat = S["prod_%d" % rnd.randint(1, 6)]
                if axis == "x":
                    room.box(B(ux + t + iw / 2, uz, zb + 0.015 + ih / 2), (iw, idp, ih), "_static", mat)
                else:
                    room.box(B(ux, uz + t + iw / 2, zb + 0.015 + ih / 2), (idp, iw, ih), "_static", mat)
                t += iw + rnd.uniform(0.01, 0.05)
    # 가운데 진열대
    room.box(B(cx, mid + inward * 0.3, z_floor + 0.4), (1.6, 0.9, 0.8), "_static", S["shop_shelf"])
    for i in range(6):
        iw = rnd.uniform(0.12, 0.3)
        room.box(B(cx - 0.6 + i * 0.24, mid + inward * 0.3 + rnd.uniform(-0.25, 0.25), z_floor + 0.8 + 0.05), (iw, 0.18, 0.1), "_static", S["prod_%d" % rnd.randint(1, 6)])
    # 유리와 문틀(벽 두께 가운데)
    gz = wall_z - inward * th * 0.5
    glass.box(B(cx, gz, z_floor + height * 0.5), (w, 0.02, height), "_static", 0)
    for fx in (-w / 2, 0.0, w / 2):
        frames.box(B(cx + fx, gz, z_floor + height * 0.5), (0.08, 0.1, height), "_static", 0)
    frames.box(B(cx, gz, z_floor + height - 0.04), (w, 0.1, 0.08), "_static", 0)
    frames.box(B(cx, gz, z_floor + 0.04), (w, 0.1, 0.08), "_static", 0)
    if lit_name:
        em = bpy.data.objects.new(lit_name, None)
        em.location = B(cx, mid, z_floor + height - 0.35)
        bpy.context.scene.collection.objects.link(em)
        lights.append(lit_name)


def quad_part(part, corners, surface):
    """바닥 사각형. 법선이 위(+Z)를 보게 한다(게임 재질은 뒷면을 그리지 않을 수 있다)."""
    b = bmesh.new()
    vs = [b.verts.new(c) for c in corners]
    f = b.faces.new(vs)
    f.normal_update()
    if f.normal.z < 0:
        f.normal_flip()
    part.add_bm(b, Matrix.Identity(4), "_static", surface, False)


def cylinder(part, center, radius, z0, z1, surface, seg=SEG, caps=True):
    part.tube(center + Vector((0, 0, z0)), center + Vector((0, 0, z1)), radius, radius, "_static", surface, seg, caps=caps, smooth=True)


def occluder_radius(r, seg=SEG):
    """다각형 기둥이 반지름 r의 원기둥을 빈틈없이 덮도록(내접원 ≥ r) 반지름을 키운다."""
    return r / math.cos(math.pi / seg) + 0.01


def build(layout_json):
    nc.reset_scene()
    mats = make_materials()
    col = bpy.context.scene.collection
    lay = layout_json["layout"]
    x0, z0, x1, z1 = lay["bounds"]
    objects = []

    def done(part):
        ob, tris = part.build(None, mats, col)
        objects.append((ob.name, tris))
        return ob

    # ---------------- 바닥: 2 m 돌 타일 바둑판 + 분수 둘레 띠
    floor = nc.Part("Floor", ["floor_light", "floor_dark", "floor_inlay"])
    t = 2.0
    nx = int(round((x1 - x0) / t))
    nz = int(round((z1 - z0) / t))
    for i in range(nx):
        for j in range(nz):
            gx0, gz0 = x0 + i * t, z0 + j * t
            corners = [B(gx0, gz0), B(gx0 + t, gz0), B(gx0 + t, gz0 + t), B(gx0, gz0 + t)]
            quad_part(floor, corners, (i + j) % 2)
    ring = bmesh.new()
    inner, outer = [], []
    for k in range(48):
        a = 2 * math.pi * k / 48
        inner.append(ring.verts.new(B(4.2 * math.cos(a), 4.2 * math.sin(a), 0.004)))
        outer.append(ring.verts.new(B(4.8 * math.cos(a), 4.8 * math.sin(a), 0.004)))
    for k in range(48):
        ring.faces.new((inner[k], outer[k], outer[(k + 1) % 48], inner[(k + 1) % 48]))
    bmesh.ops.recalc_face_normals(ring, faces=ring.faces)
    for f in ring.faces:
        if f.normal.z < 0:
            f.normal_flip()
    floor.add_bm(ring, Matrix.Identity(4), "_static", 2, False)
    # 벽에서 1.2 m 안쪽을 도는 짙은 돌 테두리 띠(폭 0.3 m)
    inset, bw = 1.2, 0.3
    for (ax0, az0_, ax1, az1_) in ((x0 + inset, z0 + inset, x1 - inset, z0 + inset + bw), (x0 + inset, z1 - inset - bw, x1 - inset, z1 - inset),
                                   (x0 + inset, z0 + inset + bw, x0 + inset + bw, z1 - inset - bw), (x1 - inset - bw, z0 + inset + bw, x1 - inset, z1 - inset - bw)):
        quad_part(floor, [B(ax0, az0_, 0.003), B(ax1, az0_, 0.003), B(ax1, az1_, 0.003), B(ax0, az1_, 0.003)], 2)
    done(floor)

    # ---------------- 외벽: 상점 전면(셔터·간판·기둥형 벽)과 2층 회랑, 천장, 채광창
    walls = nc.Part("Walls", ["wall_plaster", "pilaster", "ceiling"])
    shutters = nc.Part("Shutters", ["shutter", "shutter_dark"])
    signs = nc.Part("ShopSigns", ["sign_band", "sign_a", "sign_b", "sign_c", "sign_d", "sign_text"])
    w = x1 - x0
    d = z1 - z0
    th = 0.4
    for (cx, cz, sx, sz) in ((x0 - th / 2, (z0 + z1) / 2, th, d), (x1 + th / 2, (z0 + z1) / 2, th, d)):
        walls.box(B(cx, cz, CEILING / 2), (sx, sz, CEILING), "_static", 0)
    # 북·남쪽 벽: 열린 상점(1층)과 2층 상점 자리에 구멍을 남긴다(D-35).
    art = layout_json.get("art", {})
    open_ground = set(art.get("open_shops", []))
    shop_xs = []
    xx = x0 + 1.0
    while xx + 6.0 <= x1 - 1.0:
        if abs(xx + 3.0) >= 5.5:
            shop_xs.append(xx + 3.0)
        xx += 6.0
    room = nc.Part("ShopInteriors", ["shop_floor", "shop_wall", "shop_shelf", "shop_light", "prod_1", "prod_2", "prod_3", "prod_4", "prod_5", "prod_6"])
    RS = {n: i for i, n in enumerate(room.materials)}
    glass_p = nc.Part("ShopGlass", ["glass"])
    frames_p = nc.Part("ShopFrames", ["metal_dark"])
    shop_lights = []
    kk = 0
    for wall_z, inward in ((z0, 1.0), (z1, -1.0)):
        holes = []
        for cx_ in shop_xs:
            if kk in open_ground:
                holes.append((cx_ - 2.5, cx_ + 2.5, 0.0, 3.2))
                shop_room(room, glass_p, frames_p, shop_lights, cx_, wall_z, inward, th, 0.0, 3.2, 4.0, 100 + kk, RS, f"ShopLight_{kk:02d}")
            holes.append((cx_ - 2.5, cx_ + 2.5, GALLERY_Z + 0.3, GALLERY_Z + 2.9))
            shop_room(room, glass_p, frames_p, shop_lights, cx_, wall_z, inward, th, GALLERY_Z + 0.3, 2.6, 2.6, 200 + kk, RS)
            kk += 1
        wall_with_openings(walls, x0 - th, x1 + th, wall_z, inward, th, CEILING, holes, 0)
    # 천장 판: 가운데 채광창 자리(16 x 10 m)를 비운다. 햇빛이 이 구멍으로 들어와 바닥에 빛 무늬를 만든다.
    hx, hz = 8.0, 5.0
    cx0, cx1, cz0, cz1 = x0 - th, x1 + th, z0 - th, z1 + th
    for (ax0, ax1, az0, az1) in ((cx0, cx1, cz0, -hz), (cx0, cx1, hz, cz1), (cx0, -hx, -hz, hz), (hx, cx1, -hz, hz)):
        walls.box(B((ax0 + ax1) / 2, (az0 + az1) / 2, CEILING + 0.15), (ax1 - ax0, az1 - az0, 0.3), "_static", 2)
    # 상점 칸: 북·남쪽 벽을 따라 6 m 간격. 가운데(에스컬레이터·정문)는 비운다.
    sign_cycle = [1, 2, 3, 4]
    k = 0
    for wall_z, inward in ((z0, 1.0), (z1, -1.0)):
        x = x0 + 1.0
        while x + 6.0 <= x1 - 1.0:
            cx = x + 3.0
            if abs(cx) < 5.5:
                x += 6.0
                continue
            face_z = wall_z + inward * 0.02
            if k not in open_ground:
                shutters.box(B(cx, face_z, 1.6), (5.0, 0.06, 3.2), "_static", 0)
                for s in range(10):
                    shutters.box(B(cx, face_z + inward * 0.03, 0.2 + s * 0.3), (5.0, 0.03, 0.04), "_static", 1)
            signs.box(B(cx, face_z + inward * 0.05, 3.75), (5.2, 0.12, 0.7), "_static", 0)
            signs.box(B(cx, face_z + inward * 0.12, 3.75), (3.6, 0.04, 0.32), "_static", sign_cycle[k % 4])
            # 가게 이름(빛나는 글자). 글자 메시는 Blender +Y(= Godot -Z)를 보므로 북쪽 벽은 Z축으로 180° 돌린다.
            rot = Matrix.Rotation(math.pi if inward > 0 else 0.0, 4, "Z")
            signs.text(SHOP_NAMES[k % len(SHOP_NAMES)], 0.24, Matrix.Translation(B(cx, face_z + inward * 0.16, 3.75)) @ rot, "_static", 5, depth=0.02)
            k += 1
            walls.box(B(x + 0.1, wall_z + inward * 0.15, 2.4), (0.4, 0.3, 4.8), "_static", 1)
            x += 6.0
    # 남쪽 정문 셔터(닫힘)
    shutters.box(B(0.0, z1 - 0.03, 1.8), (8.0, 0.08, 3.6), "_static", 0)
    for s in range(12):
        shutters.box(B(0.0, z1 - 0.08, 0.2 + s * 0.3), (8.0, 0.03, 0.05), "_static", 1)
    done(walls)
    done(shutters)
    done(signs)
    done(room)
    done(glass_p)
    done(frames_p)
    # 2층 회랑: 벽을 따라 2.4 m 폭의 바닥판과 난간. 보행 높이보다 한참 위다.
    gal = nc.Part("Gallery", ["gallery", "rail"])
    gal_glass = nc.Part("GalleryGlass", ["glass"])
    gw = 2.4
    for (cx, cz, sx, sz) in (((x0 + x1) / 2, z0 + gw / 2, w, gw), ((x0 + x1) / 2, z1 - gw / 2, w, gw),
                             (x0 + gw / 2, (z0 + z1) / 2, gw, d - 2 * gw), (x1 - gw / 2, (z0 + z1) / 2, gw, d - 2 * gw)):
        gal.box(B(cx, cz, GALLERY_Z), (sx, sz, 0.35), "_static", 0)
    for (ax, az, bx, bz) in ((x0 + gw, z0 + gw, x1 - gw, z0 + gw), (x0 + gw, z1 - gw, x1 - gw, z1 - gw),
                             (x0 + gw, z0 + gw, x0 + gw, z1 - gw), (x1 - gw, z0 + gw, x1 - gw, z1 - gw)):
        a = B(ax, az, GALLERY_Z + 1.1)
        b = B(bx, bz, GALLERY_Z + 1.1)
        gal.tube(a, b, 0.04, 0.04, "_static", 1, 8)
        n_posts = int((a - b).length / 1.5)
        for i in range(n_posts + 1):
            p = a.lerp(b, i / max(n_posts, 1))
            gal.tube(p - Vector((0, 0, 1.1)), p, 0.025, 0.025, "_static", 1, 6)
        gal_glass.box((a + b) / 2 + Vector((0, 0, -0.5)), (abs(a.x - b.x) + 0.02, abs(a.y - b.y) + 0.02, 0.92), "_static", 0)
        gal.box((a + b) / 2 + Vector((0, 0, -1.04)), (abs(a.x - b.x) + 0.06, abs(a.y - b.y) + 0.06, 0.06), "_static", 1)
    done(gal)
    done(gal_glass)
    # 2층 장식: 회랑 벽 쪽의 화분과 벤치(아무도 올라가지 않는다)
    up = nc.Part("GalleryDecor", ["planter", "foliage", "bench_wood", "metal_dark"])
    for gx in [x0 + 4.0 + 6.0 * i for i in range(7)]:
        for gz_, sgn in ((z0 + 1.6, 1.0), (z1 - 1.6, -1.0)):
            c = B(gx, gz_, GALLERY_Z + 0.175)
            up.tube(c, c + Vector((0, 0, 0.55)), 0.32, 0.36, "_static", 0, 16)
            for kq in range(6):
                a_ = 2 * math.pi * kq / 6
                up.ellipsoid(c + Vector((math.cos(a_) * 0.18, math.sin(a_) * 0.18, 0.78)), (0.24, 0.24, 0.28), "_static", 1, seg=(12, 8))
            up.ellipsoid(c + Vector((0, 0, 1.0)), (0.22, 0.22, 0.3), "_static", 1, seg=(12, 8))
            bc = B(gx + 3.0, gz_ - sgn * 0.6, GALLERY_Z + 0.175)
            for kq in range(4):
                up.box(bc + Vector((0, -0.18 + kq * 0.12, 0.43)), (1.6, 0.09, 0.04), "_static", 2)
            for sx_ in (-0.65, 0.65):
                up.box(bc + Vector((sx_, 0, 0.2)), (0.06, 0.4, 0.4), "_static", 3)
    done(up)
    # 채광창: 분수 위 천장의 빛나는 유리 격자
    # 채광창: 천장 구멍 위의 빛나는 유리(SkylightGlass, 게임에서 그림자를 드리우지 않는다)와
    # 창살 격자(Skylight, 그림자를 드리워 바닥에 격자 무늬를 남긴다).
    glass = nc.Part("SkylightGlass", ["skylight"])
    glass.box(B(0.0, 0.0, CEILING + 0.32), (16.0, 10.0, 0.04), "_static", 0)
    done(glass)
    sky = nc.Part("Skylight", ["rail", "pillar_trim"])
    for i in range(9):
        sky.box(B(-8.0 + i * 2.0, 0.0, CEILING + 0.2), (0.12, 10.0, 0.2), "_static", 0)
    for j in range(6):
        sky.box(B(0.0, -5.0 + j * 2.0, CEILING + 0.2), (16.0, 0.12, 0.2), "_static", 0)
    # 구멍 둘레의 테두리(천장 판의 단면을 가린다)
    for (bx, bz, sx_, sz_) in ((0.0, -5.0, 16.4, 0.2), (0.0, 5.0, 16.4, 0.2), (-8.0, 0.0, 0.2, 10.4), (8.0, 0.0, 0.2, 10.4)):
        sky.box(B(bx, bz, CEILING - 0.05), (sx_, sz_, 0.3), "_static", 1)
    done(sky)

    # 천장 격자 보(4 m 간격)와 칸마다 번갈아 넣은 매립 조명판. 채광창 구멍 위는 비운다.
    beams = nc.Part("CeilingBeams", ["beam", "ceiling_glow"])
    for gx in range(int(x0) + 4, int(x1), 4):
        for (za, zb) in ((z0, -5.0), (5.0, z1)):
            beams.box(B(gx, (za + zb) / 2, CEILING - 0.18), (0.3, zb - za, 0.36), "_static", 0)
        if abs(gx) > 8:
            beams.box(B(gx, 0.0, CEILING - 0.18), (0.3, 10.0, 0.36), "_static", 0)
    for gz_ in range(int(z0) + 4, int(z1), 4):
        for (xa, xb) in ((x0, -8.0), (8.0, x1)):
            beams.box(B((xa + xb) / 2, gz_, CEILING - 0.18), (xb - xa, 0.3, 0.36), "_static", 0)
        if abs(gz_) > 5:
            beams.box(B(0.0, gz_, CEILING - 0.18), (16.0, 0.3, 0.36), "_static", 0)
    for gx in range(int(x0) + 2, int(x1), 4):
        for gz_ in range(int(z0) + 2, int(z1), 4):
            if abs(gx) < 8.5 and abs(gz_) < 5.5:
                continue
            if (gx // 4 + gz_ // 4) % 2 == 0:
                beams.box(B(gx, gz_, CEILING - 0.01), (1.4, 1.4, 0.02), "_static", 1)
    done(beams)

    # 펜던트 조명: 맵 데이터의 다운라이트 위치마다 천장에서 늘어뜨린 갓등. 빛은 게임의 OmniLight가 낸다.
    dl = layout_json.get("lighting", {}).get("downlights", {})
    lamp_y = float(dl.get("height", 7.0)) + 0.15
    lamps = nc.Part("Lamps", ["lamp_shade", "lamp_glow"])
    for pt in dl.get("points", []):
        c = B(float(pt[0]), float(pt[1]))
        lamps.tube(c + Vector((0, 0, lamp_y + 0.35)), c + Vector((0, 0, CEILING)), 0.012, 0.012, "_static", 0, 6, caps=False)
        lamps.tube(c + Vector((0, 0, lamp_y)), c + Vector((0, 0, lamp_y + 0.35)), 0.42, 0.12, "_static", 0, 32, caps=False)
        lamps.tube(c + Vector((0, 0, lamp_y + 0.34)), c + Vector((0, 0, lamp_y + 0.4)), 0.13, 0.13, "_static", 0, 16)
        lamps.tube(c + Vector((0, 0, lamp_y + 0.02)), c + Vector((0, 0, lamp_y + 0.05)), 0.4, 0.4, "_static", 1, 32)
    done(lamps)

    # ---------------- 배치 구조물
    deco = nc.Part("Decor", ["pillar_trim", "counter", "kiosk_top", "alcove_sign", "metal_dark", "bench_wood", "planter", "foliage", "fountain_stone", "water", "barrier", "escalator_panel"])
    S = {n: i for i, n in enumerate(deco.materials)}
    emergency = nc.Part("EmergencyStrips", ["emergency"])
    screens = nc.Part("Screens", ["screen_sale", "screen_season", "screen_directory", "screen_wayfinding", "menu_coffee", "menu_juice", "menu_icecream", "menu_phone"])
    for o in lay["obstacles"]:
        oid = o["id"]
        cx, cz = o["center"]
        h = float(o["height"])
        tag = o["tag"]
        c = B(cx, cz)
        if o["kind"] == "circle":
            r = float(o["radius"])
            if tag == "pillar":
                p = nc.Part(f"OCC_{oid}", ["pillar"])
                cylinder(p, c, occluder_radius(r), 0.0, h, 0)
                done(p)
                cylinder(deco, c, occluder_radius(r) + 0.06, 0.0, 0.25, S["pillar_trim"])
                cylinder(deco, c, occluder_radius(r) + 0.04, 3.2, 3.32, S["pillar_trim"])
            elif tag == "fountain":
                deco.tube(c, c + Vector((0, 0, 0.5)), r, r, "_static", S["fountain_stone"], 40, caps=False)
                deco.tube(c, c + Vector((0, 0, 0.5)), r - 0.3, r - 0.3, "_static", S["fountain_stone"], 40, caps=False)
                ring2 = bmesh.new()
                ia, oa = [], []
                for kk in range(40):
                    a = 2 * math.pi * kk / 40
                    ia.append(ring2.verts.new(c + Vector((math.cos(a) * (r - 0.3), math.sin(a) * (r - 0.3), 0.5))))
                    oa.append(ring2.verts.new(c + Vector((math.cos(a) * r, math.sin(a) * r, 0.5))))
                for kk in range(40):
                    ring2.faces.new((ia[kk], oa[kk], oa[(kk + 1) % 40], ia[(kk + 1) % 40]))
                for f in ring2.faces:
                    f.normal_update()
                    if f.normal.z < 0:
                        f.normal_flip()
                deco.add_bm(ring2, Matrix.Identity(4), "_static", S["fountain_stone"], False)
                cylinder(deco, c, r - 0.3, 0.0, 0.38, S["water"], 40)
                cylinder(deco, c, 0.45, 0.0, 0.7, S["fountain_stone"], 20)
                cylinder(deco, c, 1.1, 0.7, 0.8, S["fountain_stone"], 28)
                cylinder(deco, c, 0.18, 0.8, 1.2, S["fountain_stone"], 14)
                cylinder(deco, c, 0.55, 1.2, 1.26, S["fountain_stone"], 20)
                # 물: 윗접시에서 넘쳐 떨어지는 물 커튼과 가운데 물줄기(반투명, 게임에서 흘러내린다)
                fw = nc.Part("FountainWater", ["water_jet"])
                fw.tube(c + Vector((0, 0, 0.40)), c + Vector((0, 0, 0.78)), 1.17, 1.115, "_static", 0, 48, caps=False)
                fw.tube(c + Vector((0, 0, 1.24)), c + Vector((0, 0, 1.78)), 0.05, 0.022, "_static", 0, 16, caps=False)
                fw.ellipsoid(c + Vector((0, 0, 1.8)), (0.09, 0.09, 0.07), "_static", 0, seg=(16, 10))
                fw.tube(c + Vector((0, 0, 0.82)), c + Vector((0, 0, 1.22)), 0.58, 0.56, "_static", 0, 32, caps=False)
                done(fw)
            elif tag == "planter":
                cylinder(deco, c, r, 0.0, h * 0.75, S["planter"], 18)
                cylinder(deco, c, r + 0.04, h * 0.7, h * 0.78, S["planter"], 18)
                for kk in range(7):
                    a = 2 * math.pi * kk / 7
                    deco.ellipsoid(c + Vector((math.cos(a) * r * 0.55, math.sin(a) * r * 0.55, h * 0.92)), (r * 0.5, r * 0.5, 0.26), "_static", S["foliage"], seg=(12, 8))
                for kk in range(4):
                    a = 2 * math.pi * (kk + 0.5) / 4
                    deco.ellipsoid(c + Vector((math.cos(a) * r * 0.22, math.sin(a) * r * 0.22, h * 1.12)), (r * 0.42, r * 0.42, 0.3), "_static", S["foliage"], seg=(12, 8))
        else:
            sx, sz = o["size"]
            if tag in ("kiosk", "board", "alcove_wall", "escalator", "sign"):
                # 차폐물: 판정 상자보다 1 cm씩 큰 불투명 상자.
                mat = {"kiosk": KIOSK_MAT.get(oid, "kiosk_red"), "board": "board_frame", "alcove_wall": "alcove_wall", "escalator": "escalator", "sign": "board_frame"}[tag]
                p = nc.Part(f"OCC_{oid}", [mat])
                p.box(c + Vector((0, 0, h / 2)), (sx + 0.02, sz + 0.02, h + 0.01), "_static", 0)
                done(p)
            if tag == "kiosk":
                deco.box(c + Vector((0, 0, h - 0.18)), (sx + 0.06, sz + 0.06, 0.3), "_static", S["kiosk_top"])
                menu = KIOSK_MENU.get(oid)
                if menu:
                    for sgn in (-1.0, 1.0):
                        screen_quad(screens, c + Vector((0, sgn * (sz / 2 + 0.034), h - 0.18)), (0, sgn, 0), sx - 0.1, 0.26, screens.materials.index(menu))
                deco.box(c + Vector((0, 0, 1.0)), (sx + 0.04, sz + 0.04, 0.06), "_static", S["counter"])
                deco.box(c + Vector((0, 0, 0.06)), (sx + 0.06, sz + 0.06, 0.12), "_static", S["metal_dark"])
            elif tag == "board":
                for sgn in (-1.0, 1.0):
                    deco.box(c + Vector((0, sgn * (sz / 2 + 0.008), h * 0.58)), (sx - 0.2, 0.01, h * 0.62 + 0.1), "_static", S["metal_dark"])
                    screen_quad(screens, c + Vector((0, sgn * (sz / 2 + 0.016), h * 0.58)), (0, sgn, 0), sx - 0.3, h * 0.62, 0 if sgn < 0 else 1)
            elif tag == "sign":
                # 안내 사이니지 벽: 양면에 층별 안내판(빛나는 패널). 판정 상자보다 큰 불투명 상자 위에 붙인다.
                long_x = sx >= sz
                for sgn in (-1.0, 1.0):
                    off = Vector((0, sgn * (sz / 2 + 0.008), 0)) if long_x else Vector((sgn * (sx / 2 + 0.008), 0, 0))
                    size = (sx - 0.2, 0.01, h * 0.55 + 0.1) if long_x else (0.01, sz - 0.2, h * 0.55 + 0.1)
                    deco.box(c + off + Vector((0, 0, h * 0.55)), size, "_static", S["metal_dark"])
                    nrm = (0, sgn, 0) if long_x else (sgn, 0, 0)
                    face = c + off * ((abs(off.length) + 0.008) / max(off.length, 1e-6)) + Vector((0, 0, h * 0.55))
                    screen_quad(screens, face, nrm, (sx if long_x else sz) - 0.3, h * 0.55, 2 if sgn > 0 else 3)
                deco.box(c + Vector((0, 0, h + 0.03)), (sx + 0.06, sz + 0.06, 0.06), "_static", S["pillar_trim"])
            elif tag == "alcove_wall":
                deco.box(c + Vector((0, 0, h + 0.02)), (sx + 0.04, sz + 0.04, 0.05), "_static", S["pillar_trim"])
            elif tag == "escalator":
                # 멈춘 에스컬레이터: 판정 상자 위로 올라가는 경사로와 막아 둔 차단봉.
                for kk in range(10):
                    deco.box(c + Vector((0, 0.0, h + 0.1 + kk * 0.2)), (sx * 0.5, sz * 0.9 - kk * 0.08, 0.2), "_static", S["escalator_panel"])
                for sgn in (-1.0, 1.0):
                    post = c + Vector((sgn * 3.2, sz / 2 + 0.6, 0.0))
                    deco.tube(post, post + Vector((0, 0, 1.0)), 0.05, 0.05, "_static", S["metal_dark"], 10)
                deco.box(c + Vector((0, sz / 2 + 0.6, 0.9)), (6.4, 0.05, 0.12), "_static", S["barrier"])
            elif tag == "bench":
                long_x = sx >= sz
                for kk in range(4):
                    off = -0.18 + kk * 0.12
                    pos = c + (Vector((0, off, 0.43)) if long_x else Vector((off, 0, 0.43)))
                    deco.box(pos, (sx, 0.09, 0.04) if long_x else (0.09, sz, 0.04), "_static", S["bench_wood"])
                for sgn in (-1.0, 1.0):
                    pos = c + (Vector((sgn * (sx / 2 - 0.15), 0, 0.2)) if long_x else Vector((0, sgn * (sz / 2 - 0.15), 0.2)))
                    deco.box(pos, (0.06, sz * 0.9, 0.4) if long_x else (sx * 0.9, 0.06, 0.4), "_static", S["metal_dark"])
    # 알코브 표지판(서쪽: 화장실 WC, 동쪽: 엘리베이터 LIFT)과 알코브 천장
    for ax, label in ((-20.0, "WC"), (20.0, "LIFT")):
        start = deco.vert_count()
        sgn = 1.0 if ax < 0 else -1.0
        deco.text(label, 0.5, Matrix.Translation(B(ax + sgn * 2.05, 0.0, 3.4)) @ Matrix.Rotation(math.radians(-90 * sgn), 4, "Z"), "_static", S["alcove_sign"], depth=0.04)
        deco.box(B(ax, 0.0, 3.05), (4.0, 6.2, 0.1), "_static", S["pillar_trim"])
        # 비상등(2단계에만 켬)
        emergency.box(B(ax + sgn * 2.0, -2.6, 2.9), (0.08, 0.6, 0.12), "_static", 0)
        emergency.box(B(ax + sgn * 2.0, 2.6, 2.9), (0.08, 0.6, 0.12), "_static", 0)
    emergency.box(B(-3.0, z1 - 0.1, 3.9), (0.6, 0.06, 0.12), "_static", 0)
    emergency.box(B(3.0, z1 - 0.1, 3.9), (0.6, 0.06, 0.12), "_static", 0)
    emergency.box(B(0.0, z0 + 0.1, 3.6), (0.8, 0.06, 0.12), "_static", 0)
    done(deco)
    done(emergency)
    done(screens)
    return objects


def main():
    layout = nc.read_json(os.path.join(ROOT, "data", "maps", "atrium.json"))
    objects = build(layout)
    glb = os.path.join(ROOT, "assets", "arena", "arena_atrium.glb")
    nc.export_glb(glb)
    nc.save_blend(os.path.join(ROOT, "art_source", "arena_atrium.blend"))
    nc.write_json(os.path.join(ROOT, "assets", "arena", "arena_atrium.manifest.json"), {
        "version": 1,
        "generator": "tools/blender/build_arena_atrium.py",
        "map": "atrium",
        "nodes": {name: {"tris": tris} for name, tris in objects},
    })
    print(f"BUILT arena: {len(objects)} objects, tris {sum(t for _, t in objects)} -> {glb}")


main()
