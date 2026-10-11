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
    "poster_1": {"color": [0.90, 0.40, 0.55], "roughness": 0.5, "emission": 1.0},
    "poster_2": {"color": [0.35, 0.80, 0.85], "roughness": 0.5, "emission": 1.0},
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
}
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


def quad_part(part, corners, surface):
    b = bmesh.new()
    vs = [b.verts.new(c) for c in corners]
    b.faces.new(vs)
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
    done(floor)

    # ---------------- 외벽: 상점 전면(셔터·간판·기둥형 벽)과 2층 회랑, 천장, 채광창
    walls = nc.Part("Walls", ["wall_plaster", "pilaster", "ceiling"])
    shutters = nc.Part("Shutters", ["shutter", "shutter_dark"])
    signs = nc.Part("ShopSigns", ["sign_band", "sign_a", "sign_b", "sign_c", "sign_d"])
    w = x1 - x0
    d = z1 - z0
    th = 0.4
    for (cx, cz, sx, sz) in (((x0 + x1) / 2, z0 - th / 2, w + 2 * th, th), ((x0 + x1) / 2, z1 + th / 2, w + 2 * th, th),
                             (x0 - th / 2, (z0 + z1) / 2, th, d), (x1 + th / 2, (z0 + z1) / 2, th, d)):
        walls.box(B(cx, cz, CEILING / 2), (sx, sz, CEILING), "_static", 0)
    walls.box(B((x0 + x1) / 2, (z0 + z1) / 2, CEILING + 0.15), (w + 2 * th, d + 2 * th, 0.3), "_static", 2)
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
            shutters.box(B(cx, face_z, 1.6), (5.0, 0.06, 3.2), "_static", 0)
            for s in range(10):
                shutters.box(B(cx, face_z + inward * 0.03, 0.2 + s * 0.3), (5.0, 0.03, 0.04), "_static", 1)
            signs.box(B(cx, face_z + inward * 0.05, 3.75), (5.2, 0.12, 0.7), "_static", 0)
            signs.box(B(cx, face_z + inward * 0.12, 3.75), (3.6, 0.04, 0.32), "_static", sign_cycle[k % 4])
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
    # 2층 회랑: 벽을 따라 2.4 m 폭의 바닥판과 난간. 보행 높이보다 한참 위다.
    gal = nc.Part("Gallery", ["gallery", "rail"])
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
        gal.box((a + b) / 2 + Vector((0, 0, -0.55)), (abs(a.x - b.x) + 0.02, abs(a.y - b.y) + 0.02, 0.9), "_static", 0)
    done(gal)
    # 채광창: 분수 위 천장의 빛나는 유리 격자
    sky = nc.Part("Skylight", ["skylight", "rail"])
    sky.box(B(0.0, 0.0, CEILING - 0.02), (16.0, 10.0, 0.04), "_static", 0)
    for i in range(9):
        sky.box(B(-8.0 + i * 2.0, 0.0, CEILING - 0.08), (0.1, 10.0, 0.12), "_static", 1)
    for j in range(6):
        sky.box(B(0.0, -5.0 + j * 2.0, CEILING - 0.08), (16.0, 0.1, 0.12), "_static", 1)
    done(sky)

    # ---------------- 배치 구조물
    deco = nc.Part("Decor", ["pillar_trim", "counter", "kiosk_top", "poster_1", "poster_2", "alcove_sign", "metal_dark", "bench_wood", "planter", "foliage", "fountain_stone", "water", "barrier", "escalator_panel"])
    S = {n: i for i, n in enumerate(deco.materials)}
    emergency = nc.Part("EmergencyStrips", ["emergency"])
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
            elif tag == "planter":
                cylinder(deco, c, r, 0.0, h * 0.75, S["planter"], 18)
                cylinder(deco, c, r + 0.04, h * 0.7, h * 0.78, S["planter"], 18)
                for kk in range(5):
                    a = 2 * math.pi * kk / 5
                    deco.ellipsoid(c + Vector((math.cos(a) * r * 0.45, math.sin(a) * r * 0.45, h * 0.95)), (r * 0.55, r * 0.55, 0.28), "_static", S["foliage"], seg=(10, 7))
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
                deco.box(c + Vector((0, 0, 1.0)), (sx + 0.04, sz + 0.04, 0.06), "_static", S["counter"])
                deco.box(c + Vector((0, 0, 0.06)), (sx + 0.06, sz + 0.06, 0.12), "_static", S["metal_dark"])
            elif tag == "board":
                for sgn in (-1.0, 1.0):
                    deco.box(c + Vector((0, sgn * (sz / 2 + 0.012), h * 0.58)), (sx - 0.3, 0.01, h * 0.62), "_static", S["poster_1"] if sgn < 0 else S["poster_2"])
            elif tag == "sign":
                # 안내 사이니지 벽: 양면에 층별 안내판(빛나는 패널). 판정 상자보다 큰 불투명 상자 위에 붙인다.
                long_x = sx >= sz
                for sgn in (-1.0, 1.0):
                    off = Vector((0, sgn * (sz / 2 + 0.012), 0)) if long_x else Vector((sgn * (sx / 2 + 0.012), 0, 0))
                    size = (sx - 0.3, 0.01, h * 0.55) if long_x else (0.01, sz - 0.3, h * 0.55)
                    deco.box(c + off + Vector((0, 0, h * 0.55)), size, "_static", S["poster_2"] if sgn > 0 else S["poster_1"])
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
