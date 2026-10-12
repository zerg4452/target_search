"""NPC 공용 골격·애니메이션·도형 도우미 (GAME_DESIGN.md §12.4~§12.5).

Blender 5.2 배경 모드에서 쓴다. 좌표: Blender Z 위, 인물 정면 +Y, 인물의 왼쪽 -X.
glTF로 내보내면 Godot에서 정면 -Z, 오른쪽 +X가 된다.

조각마다 뼈 하나를 정하고, 관절(허리·가슴, 팔꿈치, 무릎) 가까이의 꼭짓점만 위치로 두 뼈에 가중치를 나눈다
(D-33 부드러운 관절). 같은 위치의 꼭짓점은 어느 조각이든 같은 가중치라 관절에서 틈이 벌어지지 않는다.
부품 하나 = 슬롯 노드 하나 = Blender 오브젝트 하나. 오브젝트 이름이 슬롯 노드 이름이다(§12.5 이름 계약).
UV는 1 UV = 1 m다. 원통형 조각(몸통 로프트·원뿔대)은 둘레를 펼치고, 나머지는 면 방향으로 상자 투영한다.
게임은 이 UV에 재질 세부 텍스처를 입힌다(data/material_details.json).
"""
import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 30

# 뼈: 이름 -> (머리, 꼬리, 부모). 키 1.72 m 기준.
BONES = {
    "hips": ((0.0, 0.0, 0.90), (0.0, 0.0, 1.02), None),
    "spine": ((0.0, 0.0, 1.02), (0.0, 0.0, 1.22), "hips"),
    "chest": ((0.0, 0.0, 1.22), (0.0, 0.0, 1.42), "spine"),
    "neck": ((0.0, 0.0, 1.42), (0.0, 0.0, 1.50), "chest"),
    "head": ((0.0, 0.0, 1.50), (0.0, 0.0, 1.72), "neck"),
}
for _s, _x in (("L", -1.0), ("R", 1.0)):
    BONES.update({
        f"upper_arm_{_s}": ((0.19 * _x, 0.0, 1.39), (0.215 * _x, 0.0, 1.13), "chest"),
        f"forearm_{_s}": ((0.215 * _x, 0.0, 1.13), (0.235 * _x, 0.0, 0.89), f"upper_arm_{_s}"),
        f"hand_{_s}": ((0.235 * _x, 0.0, 0.89), (0.24 * _x, 0.0, 0.80), f"forearm_{_s}"),
        f"thigh_{_s}": ((0.09 * _x, 0.0, 0.90), (0.09 * _x, 0.0, 0.50), "hips"),
        f"shin_{_s}": ((0.09 * _x, 0.0, 0.50), (0.09 * _x, 0.0, 0.09), f"thigh_{_s}"),
        f"foot_{_s}": ((0.09 * _x, 0.0, 0.09), (0.09 * _x, 0.13, 0.03), f"shin_{_s}"),
    })

# 관절 가중치 나누기: (부모 뼈, 자식 뼈, 관절 앞뒤로 섞는 길이 m, 뼈 축에서 이 거리 안의 꼭짓점만). 손목·발목·어깨·목은 강체.
JOINT_BLEND = [("hips", "spine", 0.07, 0.26), ("spine", "chest", 0.08, 0.26)]
for _s in ("L", "R"):
    JOINT_BLEND += [(f"upper_arm_{_s}", f"forearm_{_s}", 0.06, 0.11), (f"thigh_{_s}", f"shin_{_s}", 0.07, 0.13)]

# 원통형 조각의 둘레 분할 배율. NPC·플레이어 생성기가 정한다(아레나는 1).
SEG_SCALE = 1.0
SHARP_ANGLE_DEG = 50.0
# 고품질 인물(D-35): 원뿔대를 길이 방향으로 나누는 간격(m, 0이면 나누지 않음), 로프트 단면 사이 보간 간격(m),
# 옷 주름을 넣을 재질 ID(생성기가 팔레트의 detail로 정한다).
LENGTH_STEP = 0.0
RING_STEP = 0.0
CLOTH_MATERIALS = set()
SHOULDER_YOKE = False

HEAD_C = Vector((0.0, 0.005, 1.605))
HEAD_R = Vector((0.083, 0.098, 0.112))


# ============================================================== 씬·재질

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def make_materials(palette):
    """palette: {id: {"color": [r,g,b] (sRGB), "roughness": f, "metallic": f}} -> {id: bpy material}"""
    out = {}
    for mid, d in palette.items():
        m = bpy.data.materials.new(mid)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        c = d["color"]
        lin = [srgb_to_linear(v) for v in c]
        bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
        bsdf.inputs["Roughness"].default_value = float(d.get("roughness", 0.8))
        bsdf.inputs["Metallic"].default_value = float(d.get("metallic", 0.0))
        out[mid] = m
    return out


def srgb_to_linear(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


# ============================================================== 부품(조각 누적)

class Part:
    """슬롯 노드 하나. 조각마다 뼈와 표면 번호를 기록해 강체 스키닝한다."""

    def __init__(self, name, materials):
        self.name = name
        self.materials = list(materials)
        self.bm = bmesh.new()
        self.bone_layer = self.bm.verts.layers.int.new("bone")
        self.uv_layer = self.bm.loops.layers.uv.new("UVMap")
        self.uvset_layer = self.bm.faces.layers.int.new("uvset")   # 1이면 만들 때 UV를 정했다(원통 펼침)
        self.bone_names = []

    def _bone_index(self, bone):
        if bone not in self.bone_names:
            self.bone_names.append(bone)
        return self.bone_names.index(bone)

    def add_bm(self, src, matrix, bone, surface=0, smooth=True, flip=False, cyl=None, bone_of_vert=None):
        """임시 bmesh를 변환해 복사해 넣는다.
        cyl=반지름이면 임시 bmesh의 Z축 둘레로 UV를 펼친다(u = 각 × 반지름, v = z).
        bone_of_vert(월드 좌표)가 있으면 꼭짓점마다 뼈를 정한다(로프트 몸통)."""
        bi = self._bone_index(bone) if bone_of_vert is None else -1
        src_uv = src.loops.layers.uv.active   # 임시 bmesh에 UV가 있으면 그대로 옮긴다(광고판 그림 등)
        vmap = {}
        for v in src.verts:
            nv = self.bm.verts.new(matrix @ v.co)
            nv[self.bone_layer] = bi if bone_of_vert is None else self._bone_index(bone_of_vert(nv.co))
            vmap[v] = nv
        for f in src.faces:
            vs = [vmap[v] for v in f.verts]
            src_vs = list(f.verts)
            if flip:
                vs.reverse()
                src_vs.reverse()
            try:
                nf = self.bm.faces.new(vs)
            except ValueError:
                continue
            nf.material_index = surface
            nf.smooth = smooth
            if src_uv is not None:
                loops = list(f.loops)
                if flip:
                    loops.reverse()
                for loop, sl in zip(nf.loops, loops):
                    loop[self.uv_layer].uv = sl[src_uv].uv
                nf[self.uvset_layer] = 1
            elif cyl is not None:
                pts = [v.co for v in src_vs]
                ths = [math.atan2(q.x, q.y) for q in pts]
                if max(ths) - min(ths) > math.pi:
                    ths = [t + 2 * math.pi if t < 0 else t for t in ths]
                for loop, th, q in zip(nf.loops, ths, pts):
                    loop[self.uv_layer].uv = (th * cyl, q.z)
                nf[self.uvset_layer] = 1
        src.free()

    def _cloth_folds(self):
        """옷 재질 꼭짓점을 팔꿈치 안쪽·무릎 뒤·바지 밑단에서 법선 방향으로 물결지게 민다(D-35).
        위치·법선만으로 정해지므로 같은 노드는 모든 NPC에서 같다. 몸통(가방끈이 지나는 곳)은 건드리지 않는다."""
        cloth = {i for i, m in enumerate(self.materials) if m in CLOTH_MATERIALS}
        if not cloth:
            return
        self.bm.normal_update()
        self.bm.verts.ensure_lookup_table()
        hit = set()
        for f in self.bm.faces:
            if f.material_index in cloth and f.smooth:
                for v in f.verts:
                    hit.add(v.index)
        moves = []
        for i in hit:
            v = self.bm.verts[i]
            bone = self.bone_names[v[self.bone_layer]] if v[self.bone_layer] >= 0 else ""
            d = fold_offset(bone, v.co, v.normal)
            if d != 0.0:
                moves.append((v, v.normal.copy() * d))
        for v, dv in moves:
            v.co += dv

    def _box_uvs(self):
        """만들 때 UV를 정하지 않은 면은 면 방향으로 상자 투영한다(1 UV = 1 m)."""
        for f in self.bm.faces:
            if f[self.uvset_layer]:
                continue
            f.normal_update()
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for loop in f.loops:
                c = loop.vert.co
                if ax == 0:
                    uv = (c.y, c.z)
                elif ax == 1:
                    uv = (c.x, c.z)
                else:
                    uv = (c.x, c.y)
                loop[self.uv_layer].uv = uv

    # ---- 기본 도형 (모두 임시 bmesh를 만든 뒤 add_bm) ----
    def ellipsoid(self, center, radii, bone, surface=0, seg=(16, 10), keep=None, smooth=True):
        b = bmesh.new()
        seg = (_scaled(seg[0], 1.0 + (SEG_SCALE - 1.0) * 0.6), _scaled(seg[1], 1.0 + (SEG_SCALE - 1.0) * 0.5))
        bmesh.ops.create_uvsphere(b, u_segments=seg[0], v_segments=seg[1], radius=1.0)
        m = Matrix.Translation(Vector(center)) @ Matrix.Diagonal(Vector(radii)).to_4x4()
        if keep is not None:
            # keep(world_point) 가 거짓인 꼭짓점을 지운다(머리카락 경계 등).
            dead = [v for v in b.verts if not keep(m @ v.co)]
            bmesh.ops.delete(b, geom=dead, context="VERTS")
        self.add_bm(b, m, bone, surface, smooth)

    def tube(self, p0, p1, r0, r1, bone, surface=0, seg=12, caps=True, smooth=True, squash=1.0, lengthwise=True):
        """p0→p1 축의 원뿔대. squash는 단면을 정면(Y) 방향으로 납작하게 한다."""
        p0 = Vector(p0)
        p1 = Vector(p1)
        axis = p1 - p0
        length = axis.length
        b = bmesh.new()
        seg = _scaled(seg, SEG_SCALE)
        bmesh.ops.create_cone(b, cap_ends=caps, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=length)
        # create_cone: Z축, 중심이 원점. 아래(-Z)가 radius1.
        if lengthwise and LENGTH_STEP > 0.0 and length > LENGTH_STEP * 1.5:
            side = [e for e in b.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > length * 0.5]
            cuts = min(24, int(length / LENGTH_STEP))
            if side and cuts > 0:
                bmesh.ops.subdivide_edges(b, edges=side, cuts=cuts, use_grid_fill=False)
        rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
        m = Matrix.Translation((p0 + p1) * 0.5) @ rot @ Matrix.Diagonal(Vector((1.0, squash, 1.0))).to_4x4()
        self.add_bm(b, m, bone, surface, smooth, cyl=(r0 + r1) * 0.5)

    def box(self, center, size, bone, surface=0, rot=None, bevel=0.0, smooth=False):
        b = bmesh.new()
        bmesh.ops.create_cube(b, size=1.0)
        if bevel > 0.0:
            # 크기를 먼저 적용해야 모서리 반경이 일정하다.
            bmesh.ops.scale(b, vec=Vector(size), verts=b.verts)
            bmesh.ops.bevel(b, geom=list(b.edges), offset=bevel, segments=2, affect="EDGES", profile=0.5)
            scale = Matrix.Identity(4)
        else:
            scale = Matrix.Diagonal(Vector(size)).to_4x4()
        r = (rot if rot is not None else Matrix.Identity(3)).to_4x4()
        m = Matrix.Translation(Vector(center)) @ r @ scale
        self.add_bm(b, m, bone, surface, smooth)

    def torus(self, center, major, minor, bone, surface=0, seg=(16, 6), rot=None, scale=(1, 1, 1)):
        b = bmesh.new()
        rings = []
        for i in range(seg[0]):
            a = 2 * math.pi * i / seg[0]
            ring = []
            for j in range(seg[1]):
                c = 2 * math.pi * j / seg[1]
                r = major + minor * math.cos(c)
                ring.append(b.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(c))))
            rings.append(ring)
        for i in range(seg[0]):
            for j in range(seg[1]):
                a0, a1 = rings[i], rings[(i + 1) % seg[0]]
                b.faces.new((a0[j], a1[j], a1[(j + 1) % seg[1]], a0[(j + 1) % seg[1]]))
        r = (rot if rot is not None else Matrix.Identity(3)).to_4x4()
        m = Matrix.Translation(Vector(center)) @ r @ Matrix.Diagonal(Vector(scale)).to_4x4()
        self.add_bm(b, m, bone, surface, True)

    def polygon_slab(self, pts2d, depth, matrix, bone, surface=0):
        """평면 다각형(XZ 평면, 법선 +Y)을 두께 depth로 세운 판."""
        b = bmesh.new()
        front = [b.verts.new((x, depth * 0.5, z)) for x, z in pts2d]
        back = [b.verts.new((x, -depth * 0.5, z)) for x, z in pts2d]
        b.faces.new(list(reversed(front)))
        b.faces.new(back)
        n = len(pts2d)
        for i in range(n):
            j = (i + 1) % n
            b.faces.new((front[i], front[j], back[j], back[i]))
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        self.add_bm(b, matrix, bone, surface, False)

    def ribbon(self, pts, width, thick, outward, bone_of, surface=0):
        """점 목록을 따라가는 납작한 끈. outward(p) = 바깥 법선, bone_of(p) = 뼈 이름."""
        pts = [Vector(p) for p in pts]
        rings = []
        for i, p in enumerate(pts):
            t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            n = Vector(outward(p))
            n = (n - t * n.dot(t)).normalized()
            side = t.cross(n).normalized()
            hw = width * 0.5
            rings.append([p + side * hw, p + side * hw + n * thick, p - side * hw + n * thick, p - side * hw])
        for i in range(len(pts) - 1):
            b = bmesh.new()
            vs0 = [b.verts.new(v) for v in rings[i]]
            vs1 = [b.verts.new(v) for v in rings[i + 1]]
            for k in range(4):
                b.faces.new((vs0[k], vs0[(k + 1) % 4], vs1[(k + 1) % 4], vs1[k]))
            if i == 0:
                b.faces.new(list(reversed(vs0)))
            if i == len(pts) - 2:
                b.faces.new(vs1)
            bmesh.ops.recalc_face_normals(b, faces=b.faces)
            self.add_bm(b, Matrix.Identity(4), bone_of((pts[i] + pts[i + 1]) * 0.5), surface, False)

    def loft(self, rings, bone_of, surface=0, seg=20, cap_bottom=False, cap_top=True, skip=None, bulge=None):
        """타원 단면을 높이별로 이은 몸통. rings: [(z, rx, ry, yoff)] 아래→위.
        skip(theta, z) 가 참인 면은 만들지 않는다(앞트임 등). bulge(theta, z) -> 반지름 배율."""
        b = bmesh.new()
        seg = _scaled(seg, SEG_SCALE)
        if SHOULDER_YOKE and cap_top and rings[-1][0] > 1.33 and rings[-1][1] > 0.12:
            # 상의 몸통: 평평한 윗면 대신 목 쪽으로 비스듬히 좁아지는 둥근 어깨를 덧붙인다(D-35).
            z0, rx0, ry0, yo0 = rings[-1]
            extra = []
            for k in range(1, 6):
                t = k / 5
                e = math.sin(t * math.pi / 2)
                extra.append((z0 + 0.055 * t ** 0.8, rx0 + (0.068 - rx0) * e, ry0 + (0.07 - ry0) * e ** 1.6, yo0 - 0.004 * t))
            rings = list(rings) + extra
        if RING_STEP > 0.0:
            rings = densify_rings(rings, RING_STEP)
        layers = []
        for z, rx, ry, yo in rings:
            ring = []
            for i in range(seg):
                th = 2 * math.pi * i / seg
                k = bulge(th, z) if bulge else 1.0
                ring.append(b.verts.new((rx * k * math.sin(th), yo + ry * k * math.cos(th), z)))
            layers.append(ring)
        for li in range(len(layers) - 1):
            r0, r1 = layers[li], layers[li + 1]
            zm = (rings[li][0] + rings[li + 1][0]) * 0.5
            for i in range(seg):
                j = (i + 1) % seg
                thm = 2 * math.pi * (i + 0.5) / seg
                if skip and skip(thm, zm):
                    continue
                b.faces.new((r0[i], r0[j], r1[j], r1[i]))
        if cap_top:
            b.faces.new(list(layers[-1]))
        if cap_bottom:
            b.faces.new(list(reversed(layers[0])))
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        # 한 덩어리로 넣고 꼭짓점 높이로 뼈를 정한다. 관절 근처는 build()가 두 뼈에 가중치를 나눈다.
        r_avg = sum((r[1] + r[2]) * 0.5 for r in rings) / len(rings)
        self.add_bm(b, Matrix.Identity(4), "", surface, True, cyl=r_avg, bone_of_vert=lambda q: bone_of(q.z))

    def sweep(self, pts, normals, widths, thick, bone, surface=0, sides=8, tip=True):
        """점 목록을 따라 가는 납작한 타원 단면 띠(머리 다발·눈썹 등). widths[i] = 그 점의 반폭,
        normals[i] = 그 점에서 두께 방향. tip이면 끝을 한 점으로 모은다."""
        b = bmesh.new()
        rings = []
        n = len(pts)
        for i in range(n):
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            nn = Vector(normals[i])
            nn = (nn - t * nn.dot(t)).normalized()
            side = t.cross(nn).normalized()
            w = widths[i]
            h = thick[i] if isinstance(thick, (list, tuple)) else thick
            if tip and i == n - 1:
                rings.append([b.verts.new(pts[i])])
                continue
            ring = []
            for k in range(sides):
                a = 2 * math.pi * k / sides
                ring.append(b.verts.new(pts[i] + side * (w * math.cos(a)) + nn * (h * math.sin(a))))
            rings.append(ring)
        for i in range(n - 1):
            r0, r1 = rings[i], rings[i + 1]
            for k in range(sides):
                k2 = (k + 1) % sides
                if len(r1) == 1:
                    b.faces.new((r0[k], r0[k2], r1[0]))
                else:
                    b.faces.new((r0[k], r0[k2], r1[k2], r1[k]))
        b.faces.new(list(reversed(rings[0])))
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        self.add_bm(b, Matrix.Identity(4), bone, surface, True)

    def text(self, body, size, matrix, bone, surface=0, depth=0.003, extrude_y=True):
        """Blender 기본 글꼴의 글자를 메시로 바꿔 넣는다. 글자는 XZ 평면(정면 +Y)에 선다."""
        cu = bpy.data.curves.new("txt", "FONT")
        cu.body = body
        cu.size = size
        cu.extrude = depth * 0.5
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.resolution_u = 2
        ob = bpy.data.objects.new("txt", cu)
        bpy.context.scene.collection.objects.link(ob)
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        b = bmesh.new()
        b.from_mesh(me)
        # 글꼴은 XY 평면에 눕고 +Z에서 읽힌다 → X축 90°로 세우면 -Y에서 읽히므로 Z축 180°를 더해 정면 +Y에서 읽히게 한다.
        upright = Matrix.Rotation(math.radians(180), 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "X")
        bmesh.ops.transform(b, matrix=upright, verts=b.verts)
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        self.add_bm(b, matrix, bone, surface, False)
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        bpy.data.meshes.remove(me)

    def wrap(self, surface_y, verts_from=0):
        """verts_from 이후 꼭짓점의 y를 표면 함수 기준으로 옮긴다(평면 인쇄물을 몸통에 감기)."""
        self.bm.verts.ensure_lookup_table()
        for v in self.bm.verts[verts_from:]:
            v.co.y = surface_y(v.co.x, v.co.z, v.co.y)

    def vert_count(self):
        return len(self.bm.verts)

    # ---- 좌우 반전 ----
    def mirrored(self, name):
        out = Part(name, self.materials)
        self.bm.verts.ensure_lookup_table()
        vmap = {}
        for v in self.bm.verts:
            nv = out.bm.verts.new((-v.co.x, v.co.y, v.co.z))
            bone = self.bone_names[v[self.bone_layer]]
            nv[out.bone_layer] = out._bone_index(swap_side(bone))
            vmap[v] = nv
        for f in self.bm.faces:
            nf = out.bm.faces.new([vmap[v] for v in reversed(f.verts)])
            nf.material_index = f.material_index
            nf.smooth = f.smooth
            nf[out.uvset_layer] = f[self.uvset_layer]
            for nl, ol in zip(nf.loops, reversed(list(f.loops))):
                uv = ol[self.uv_layer].uv
                nl[out.uv_layer].uv = (-uv.x, uv.y)
        return out

    # ---- 오브젝트로 만들기 ----
    def build(self, arm_obj, mats, collection):
        me = bpy.data.meshes.new(self.name)
        if arm_obj is not None and CLOTH_MATERIALS:
            self._cloth_folds()
        self._box_uvs()
        self.bm.verts.ensure_lookup_table()
        bones = [self.bone_names[v[self.bone_layer]] for v in self.bm.verts]
        positions = [v.co.copy() for v in self.bm.verts]
        tris = sum(len(f.verts) - 2 for f in self.bm.faces)
        used = sorted({f.material_index for f in self.bm.faces})
        if used != list(range(len(self.materials))):
            raise RuntimeError(f"{self.name}: 표면 {used}가 재질 {self.materials}와 맞지 않음")
        self.bm.to_mesh(me)
        self.bm.free()
        # 곡면은 부드럽게, 꺾인 모서리(상자 모서리·원뿔대 뚜껑)는 날카롭게.
        me.set_sharp_from_angle(angle=math.radians(SHARP_ANGLE_DEG))
        for mid in self.materials:
            me.materials.append(mats[mid])
        ob = bpy.data.objects.new(self.name, me)
        collection.objects.link(ob)
        if arm_obj is not None:
            ob.parent = arm_obj
            mod = ob.modifiers.new("Armature", "ARMATURE")
            mod.object = arm_obj
            groups = {}
            for i, bn in enumerate(bones):
                for wb, w in joint_weights(bn, positions[i]):
                    if wb not in groups:
                        groups[wb] = ob.vertex_groups.new(name=wb)
                    groups[wb].add([i], w, "REPLACE")
        return ob, tris


def densify_rings(rings, step):
    """로프트 단면 사이에 Catmull-Rom 보간 단면을 넣어 몸통 곡선을 매끄럽게 한다(원래 단면은 그대로 지난다)."""
    out = []
    n = len(rings)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        p0 = rings[max(i - 1, 0)]
        p3 = rings[min(i + 2, n - 1)]
        out.append(a)
        k = int((b[0] - a[0]) / step)
        for j in range(1, k):
            t = j / k
            vals = []
            for c in range(4):
                v0, v1, v2, v3 = p0[c], a[c], b[c], p3[c]
                vals.append(0.5 * ((2 * v1) + (-v0 + v2) * t + (2 * v0 - 5 * v1 + 4 * v2 - v3) * t * t + (-v0 + 3 * v1 - 3 * v2 + v3) * t * t * t))
            vals[0] = a[0] + (b[0] - a[0]) * t   # 높이는 고르게
            out.append(tuple(vals))
    out.append(rings[-1])
    return out


def _bell(x, w):
    return math.exp(-(x / w) ** 2)


def fold_offset(bone, p, n):
    """옷 주름 변위(m, 법선 방향). 팔꿈치 안쪽(앞), 무릎 뒤, 바지 밑단, 소맷부리 근처에 고리 모양 주름."""
    side = bone[-1:] if bone[-2:] in ("_L", "_R") else ""
    if not side:
        return 0.0
    sgn = 1.0 if side == "R" else -1.0
    if bone.startswith(("upper_arm", "forearm")):
        j = Vector(BONES[f"forearm_{side}"][0])
        axis = (Vector(BONES[f"forearm_{side}"][1]) - j).normalized()
        inner = Vector((0.0, 1.0, 0.0))     # 팔꿈치는 앞으로 굽는다
        width, amp, period = 0.075, 0.0042, 0.026
    elif bone.startswith(("thigh", "shin")):
        j = Vector(BONES[f"shin_{side}"][0])
        axis = (Vector(BONES[f"shin_{side}"][1]) - j).normalized()
        inner = Vector((0.0, -1.0, 0.0))    # 무릎은 뒤로 굽는다
        width, amp, period = 0.085, 0.0048, 0.030
    else:
        return 0.0
    rel = p - j
    s_ = rel.dot(axis)
    radial = rel - axis * s_
    if radial.length < 1e-6:
        return 0.0
    rdir = radial.normalized()
    ang = math.atan2(rdir.x * sgn, rdir.y)            # 좌우 대칭인 둘레각
    facing = max(0.0, rdir.dot(inner))
    d = amp * _bell(s_, width) * (0.25 + 0.75 * facing ** 1.5) * math.sin(2 * math.pi * s_ / period + 1.6 * math.sin(2 * ang))
    # 바지 밑단·소맷부리에 쌓이는 주름
    if bone.startswith("shin") and p.z < 0.24:
        t = min(1.0, (0.24 - p.z) / 0.1)
        d += 0.0032 * t * math.sin(2 * math.pi * p.z / 0.028 + 2.2 * math.sin(3 * ang))
    if bone.startswith("forearm") and p.z < 1.0:
        t = min(1.0, (1.0 - p.z) / 0.08)
        d += 0.0022 * t * math.sin(2 * math.pi * p.z / 0.022 + 2.0 * math.sin(3 * ang))
    # 넓은 결의 잔물결
    d += 0.0011 * math.sin(p.z * 61.0 + 3.0 * math.sin(ang * 2.0 + p.z * 13.0))
    return d


def _scaled(seg, k):
    return max(int(seg), int(round(seg * k)))


def joint_weights(bone, p):
    """꼭짓점 위치 p(휴지 자세)와 정해진 뼈로 [(뼈, 가중치)]. 관절 근처면 위치만으로 부모·자식에 나눈다."""
    best = None
    for parent, child, reach, radial in JOINT_BLEND:
        if bone not in (parent, child):
            continue
        j = Vector(BONES[child][0])
        d = (Vector(BONES[child][1]) - j).normalized()
        s_ = (p - j).dot(d)
        if abs(s_) >= reach:
            continue
        axis = d if s_ >= 0.0 else (Vector(BONES[parent][1]) - Vector(BONES[parent][0])).normalized()
        rel = p - j
        off = rel - axis * rel.dot(axis)
        if off.length > radial:
            continue
        if best is None or abs(s_) < abs(best[0]):
            best = (s_, parent, child, reach)
    if best is None:
        return [(bone, 1.0)]
    s_, parent, child, reach = best
    t = (s_ + reach) / (2.0 * reach)
    wc = t * t * (3.0 - 2.0 * t)
    out = []
    if wc < 0.999:
        out.append((parent, 1.0 - wc))
    if wc > 0.001:
        out.append((child, wc))
    return out


def swap_side(bone):
    if bone.endswith("_L"):
        return bone[:-2] + "_R"
    if bone.endswith("_R"):
        return bone[:-2] + "_L"
    return bone


# ============================================================== 골격

def build_armature(name="NpcSkeleton"):
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    for bn, (h, t, parent) in BONES.items():
        eb = arm.edit_bones.new(bn)
        eb.head = h
        eb.tail = t
        eb.roll = 0.0
        if parent:
            eb.parent = arm.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


def _local_rot(arm_obj, bone, R):
    """뼈 머리를 중심으로 한 (부모 기준) 회전 R(골격 공간)을 그 뼈의 로컬 회전으로 바꾼다."""
    B = arm_obj.data.bones[bone].matrix_local.to_3x3()
    return (B.inverted() @ R @ B).to_quaternion()


def _local_loc(arm_obj, bone, d):
    B = arm_obj.data.bones[bone].matrix_local.to_3x3()
    return B.inverted() @ Vector(d)


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def ry(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rz(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def _key_pose(arm_obj, frame, pose):
    """pose: {bone: (Matrix3 회전 또는 None, 위치 오프셋 또는 None)}. 모든 뼈를 키로 남긴다."""
    for pb in arm_obj.pose.bones:
        rot, loc = pose.get(pb.name, (None, None))
        pb.rotation_quaternion = _local_rot(arm_obj, pb.name, rot) if rot is not None else Quaternion()
        pb.location = _local_loc(arm_obj, pb.name, loc) if loc is not None else Vector()
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def _walk_pose(p, thigh_a, knee_a, arm_a, bob, lean=0.0):
    s = math.sin(2 * math.pi * p)
    c = math.cos(2 * math.pi * p)
    pose = {
        "hips": (rz(3.0 * s), (0.0, 0.0, bob * math.cos(4 * math.pi * p) - bob)),
        "spine": (rx(-lean), None),
        "chest": (rz(-5.0 * s), None),
        "head": (rz(2.0 * s), None),
        "thigh_L": (rx(thigh_a * s), None),
        "thigh_R": (rx(-thigh_a * s), None),
        "shin_L": (rx(-knee_a * max(0.0, c) - 4.0), None),
        "shin_R": (rx(-knee_a * max(0.0, -c) - 4.0), None),
        "foot_L": (rx(6.0 * max(0.0, -s)), None),
        "foot_R": (rx(6.0 * max(0.0, s)), None),
        "upper_arm_L": (rx(-arm_a * s), None),
        "upper_arm_R": (rx(arm_a * s), None),
        "forearm_L": (rx(10.0 + 6.0 * max(0.0, -s)), None),
        "forearm_R": (rx(10.0 + 6.0 * max(0.0, s)), None),
    }
    return pose


def _new_action(arm_obj, name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm_obj.animation_data.action = act
    return act


def _finish_action(arm_obj, act, frames):
    track = arm_obj.animation_data.nla_tracks.new()
    track.name = act.name
    track.strips.new(act.name, 0, act)
    arm_obj.animation_data.action = None


def build_animations(arm_obj, player=False):
    """§12.4 애니메이션. 모두 제자리 동작이며 이동은 코드가 맡는다. 반환: {이름: 길이(초)}"""
    arm_obj.animation_data_create()
    out = {}

    def cycle(name, seconds, pose_fn, step=1):
        act = _new_action(arm_obj, name)
        n = int(round(seconds * FPS))
        for f in range(0, n + 1, step):
            _key_pose(arm_obj, f, pose_fn((f % n) / n))
        _finish_action(arm_obj, act, n)
        out[name] = seconds

    def oneshot(name, keys):
        """keys: [(초, pose)]"""
        act = _new_action(arm_obj, name)
        for t, pose in keys:
            _key_pose(arm_obj, int(round(t * FPS)), pose)
        _finish_action(arm_obj, act, int(round(keys[-1][0] * FPS)))
        out[name] = keys[-1][0]

    # 걷기: 1.25 m/s에서 한 주기 1.0초(두 걸음, 보폭 0.625 m).
    cycle("walk", 1.0, lambda p: _walk_pose(p, 24.0, 42.0, 16.0, 0.012))
    # 대기: 4초 반복. 숨쉬기와 아주 작은 흔들림.
    cycle("idle", 4.0, lambda p: {
        "chest": (rx(-1.2 * math.sin(2 * math.pi * p)), None),
        "head": (rz(1.5 * math.sin(2 * math.pi * p)) @ rx(1.0 * math.sin(4 * math.pi * p)), None),
        "upper_arm_L": (ry(-1.0 * math.sin(2 * math.pi * p)) @ rx(2.0), None),
        "upper_arm_R": (ry(1.0 * math.sin(2 * math.pi * p)) @ rx(2.0), None),
        "forearm_L": (rx(6.0), None),
        "forearm_R": (rx(6.0), None),
    }, step=4)
    base_arms = {"forearm_L": (rx(6.0), None), "forearm_R": (rx(6.0), None)}

    def with_arms(d):
        d2 = dict(base_arms)
        d2.update(d)
        return d2

    # 두리번거리기 2.5초: 고개를 좌우로.
    oneshot("look_around", [
        (0.0, with_arms({})),
        (0.6, with_arms({"head": (rz(38.0), None), "neck": (rz(10.0), None)})),
        (1.1, with_arms({"head": (rz(38.0), None), "neck": (rz(10.0), None)})),
        (1.8, with_arms({"head": (rz(-38.0), None), "neck": (rz(-10.0), None)})),
        (2.2, with_arms({"head": (rz(-30.0), None)})),
        (2.5, with_arms({})),
    ])
    # 호출 반응: 회전(0.4초)은 코드가 하고, 여기서는 고개를 갸웃한다. 2.9초.
    oneshot("call_react", [
        (0.0, with_arms({})),
        (0.35, with_arms({"head": (ry(12.0), None)})),
        (2.5, with_arms({"head": (ry(12.0), None)})),
        (2.9, with_arms({})),
    ])
    # 오답 지목된 NPC의 갸웃(1.2초). 표식이 아니라 짧은 반응이다.
    oneshot("wrong_accused", [
        (0.0, with_arms({})),
        (0.3, with_arms({"head": (ry(-14.0), None), "upper_arm_L": (ry(-8.0), None), "upper_arm_R": (ry(8.0), None)})),
        (0.9, with_arms({"head": (ry(-14.0), None)})),
        (1.2, with_arms({})),
    ])
    # 착지 0.8초.
    oneshot("land", [
        (0.0, with_arms({"hips": (None, (0, 0, -0.14)), "thigh_L": (rx(35), None), "thigh_R": (rx(35), None),
                         "shin_L": (rx(-62), None), "shin_R": (rx(-62), None), "foot_L": (rx(27), None), "foot_R": (rx(27), None),
                         "spine": (rx(12), None), "upper_arm_L": (ry(-18), None), "upper_arm_R": (ry(18), None)})),
        (0.5, with_arms({"hips": (None, (0, 0, -0.03)), "thigh_L": (rx(8), None), "thigh_R": (rx(8), None),
                         "shin_L": (rx(-14), None), "shin_R": (rx(-14), None), "foot_L": (rx(6), None), "foot_R": (rx(6), None)})),
        (0.8, with_arms({})),
    ])
    # 정체 공개(타겟 전용, 승패가 정해진 뒤에만): 고개를 숙였다가 천천히 들어 이쪽을 본다.
    oneshot("reveal", [
        (0.0, with_arms({})),
        (0.6, with_arms({"head": (rx(-18), None)})),
        (1.6, with_arms({"head": (rx(6), None), "chest": (rx(4), None)})),
        (2.0, with_arms({"head": (rx(4), None), "chest": (rx(3), None)})),
    ])
    if player:
        cycle("run", 0.66, lambda p: _walk_pose(p, 38.0, 70.0, 34.0, 0.03, lean=8.0))
        oneshot("accuse_point", [
            (0.0, with_arms({})),
            (0.25, with_arms({"upper_arm_R": (rx(78), None), "forearm_R": (rx(4), None)})),
            (0.5, with_arms({"upper_arm_R": (rx(78), None), "forearm_R": (rx(4), None)})),
        ])
    # 휴지 자세로 되돌린다.
    for pb in arm_obj.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    return out


# ============================================================== 몸 표면 도우미

HEAD_SCULPT = False   # 고품질 인물(D-35)에서 켠다: 턱·광대·눈두덩·눈구멍을 조각한 머리


def _smooth(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def head_jaw(w, front):
    """머리 아래쪽 앞부분을 좁혀 턱선을 만든다(x 배율)."""
    if not HEAD_SCULPT:
        return 1.0
    return 1.0 - 0.17 * _smooth(0.05, -0.9, w) * (0.45 + 0.55 * front)


def head_relief(u, w):
    """정면 얼굴의 높낮이(m, +Y). u, w = 머리 중심 기준 정규화 x, z."""
    if not HEAD_SCULPT:
        return 0.0
    au = abs(u)
    d = 0.0
    d += 0.0042 * math.exp(-((w - 0.2) / 0.075) ** 2) * math.exp(-((au - 0.36) / 0.24) ** 2)    # 눈썹뼈
    d -= 0.0062 * math.exp(-(((w - 0.085) / 0.11) ** 2 + ((au - 0.37) / 0.15) ** 2))           # 눈구멍
    d += 0.0030 * math.exp(-(((w + 0.12) / 0.14) ** 2 + ((au - 0.56) / 0.17) ** 2))            # 광대
    d += 0.0040 * math.exp(-((w + 0.52) / 0.2) ** 2) * math.exp(-(u / 0.36) ** 2)              # 입 둘레
    d += 0.0060 * math.exp(-((w + 0.84) / 0.12) ** 2) * math.exp(-(u / 0.3) ** 2)               # 턱끝
    d -= 0.0025 * math.exp(-((w + 0.68) / 0.06) ** 2) * math.exp(-(u / 0.25) ** 2)              # 턱 위 오목
    return d


def sculpt_head_point(p):
    """머리 타원체 위의 점을 조각한 머리 위로 옮긴다."""
    if not HEAD_SCULPT:
        return p
    w = (p.z - HEAD_C.z) / HEAD_R.z
    fy = (p.y - HEAD_C.y) / HEAD_R.y
    front = _smooth(-0.3, 0.5, fy)
    x = HEAD_C.x + (p.x - HEAD_C.x) * head_jaw(w, front)
    u = (x - HEAD_C.x) / HEAD_R.x
    y = p.y + head_relief(u, w) * _smooth(0.1, 0.6, fy)
    return Vector((x, y, p.z))


def head_surface_y(x, z, lift=0.0):
    """머리 정면(+Y) 표면의 y. 조각한 머리면 턱선 좁힘과 얼굴 높낮이를 반영한다."""
    w = (z - HEAD_C.z) / HEAD_R.z
    jx = head_jaw(w, 1.0)
    uu = (x - HEAD_C.x) / (HEAD_R.x * jx)
    u2 = uu * uu + w * w
    base = HEAD_C.y + HEAD_R.y * math.sqrt(max(0.0, 1.0 - u2))
    fy = (base - HEAD_C.y) / HEAD_R.y
    return base + head_relief((x - HEAD_C.x) / HEAD_R.x, w) * _smooth(0.1, 0.6, fy) + lift


class Profile:
    """loft 단면 목록을 높이로 보간한다. 인쇄물·끈을 몸통 표면에 붙일 때 쓴다."""

    def __init__(self, rings):
        self.rings = rings

    def at(self, z):
        rs = self.rings
        if z <= rs[0][0]:
            return rs[0][1:]
        for a, b in zip(rs, rs[1:]):
            if a[0] <= z <= b[0]:
                t = (z - a[0]) / (b[0] - a[0])
                return tuple(a[i] + (b[i] - a[i]) * t for i in (1, 2, 3))
        return rs[-1][1:]

    def point(self, theta_deg, z, offset=0.0):
        """정면 0°, 인물의 오른쪽(+X) 90°."""
        rx_, ry_, yo = self.at(z)
        th = math.radians(theta_deg)
        p = Vector((rx_ * math.sin(th), yo + ry_ * math.cos(th), z))
        n = Vector((math.sin(th) / max(rx_, 1e-4), math.cos(th) / max(ry_, 1e-4), 0.0)).normalized()
        return p + n * offset

    def front_y(self, x, z, sign=1.0):
        rx_, ry_, yo = self.at(z)
        u = min(0.999, (x / rx_) ** 2)
        return yo + sign * ry_ * math.sqrt(1.0 - u)

    def outward(self, p):
        rx_, ry_, yo = self.at(p.z)
        return Vector(((p.x) / max(rx_, 1e-4) ** 2, (p.y - yo) / max(ry_, 1e-4) ** 2, 0.0)).normalized()


def bone_by_height(z):
    if z < 0.97:
        return "hips"
    if z < 1.22:
        return "spine"
    return "chest"


def limb_bone(side, z, upper="upper_arm", lower="forearm"):
    return f"{upper}_{side}" if z > 1.13 else f"{lower}_{side}"


def arm_point(side, z):
    """팔 뼈 축 위에서 높이 z인 점(휴지 자세)."""
    sx = -1.0 if side == "L" else 1.0
    if z >= 1.13:
        t = (1.39 - z) / (1.39 - 1.13)
        return Vector((sx * (0.19 + 0.025 * t), 0.0, z))
    t = (1.13 - z) / (1.13 - 0.89)
    return Vector((sx * (0.215 + 0.02 * t), 0.0, z))


def sleeve(part, side, z_top, z_end, r_top, r_end, surface=0, seg=12, cuff=0.0):
    """어깨(z_top)에서 z_end까지 팔을 감싸는 소매. 팔꿈치에서 둘로 나눠 각 뼈에 붙인다.
    어깨 끝은 납작한 공으로 덮어 원뿔대 뚜껑의 각진 모서리가 보이지 않게 한다."""
    elbow = 1.13
    if SHOULDER_YOKE:
        # 둥근 어깨 끝(삼각근): 소매 원통을 조금 낮춰 시작하고 그 끝을 타원체로 덮는다(D-35).
        z_cap = z_top - 0.05
        sx = -1.0 if side == "L" else 1.0
        part.ellipsoid(arm_point(side, z_cap) + Vector((-sx * 0.006, 0.0, 0.0)), (r_top * 1.06, r_top * 1.05, r_top * 1.2),
                       f"upper_arm_{side}", surface, seg=(seg + 4, 12))
        z_top = z_cap
    else:
        part.ellipsoid(arm_point(side, z_top - 0.012), (r_top * 1.0, r_top * 1.04, r_top * 0.5), f"upper_arm_{side}", surface, seg=(seg, 8))

    if z_end < elbow:
        r_mid = r_top + (r_end - r_top) * (z_top - elbow) / (z_top - z_end)
        part.tube(arm_point(side, z_top), arm_point(side, elbow - 0.03), r_top, r_mid, f"upper_arm_{side}", surface, seg)
        part.ellipsoid(arm_point(side, elbow), (r_mid, r_mid, r_mid), f"forearm_{side}", surface, seg=(seg, 6))
        part.tube(arm_point(side, elbow), arm_point(side, z_end), r_mid, r_end, f"forearm_{side}", surface, seg)
    else:
        part.tube(arm_point(side, z_top), arm_point(side, z_end), r_top, r_end, f"upper_arm_{side}", surface, seg)
    if cuff > 0.0:
        bone = limb_bone(side, z_end)
        part.tube(arm_point(side, z_end + cuff * 0.5), arm_point(side, z_end - cuff * 0.5), r_end + 0.006, r_end + 0.006, bone, surface, seg)


def leg_point(side, z):
    sx = -1.0 if side == "L" else 1.0
    return Vector((sx * 0.09, 0.0, z))


def trouser_legs(part, z_hem, r_thigh, r_knee, r_hem, surface=0, seg=12, rings=None):
    for side in ("L", "R"):
        part.tube(leg_point(side, 0.93), leg_point(side, 0.47), r_thigh, r_knee, f"thigh_{side}", surface, seg)
        part.ellipsoid(leg_point(side, 0.50), (r_knee, r_knee, r_knee), f"shin_{side}", surface, seg=(seg, 6))
        part.tube(leg_point(side, 0.50), leg_point(side, z_hem), r_knee, r_hem, f"shin_{side}", surface, seg)


# ============================================================== 내보내기·목록

def export_glb(path, vertex_color=None):
    """vertex_color: 꼭짓점 색으로 내보낼 색 속성 이름(NPC의 미리 구운 주변광 차폐 "AO"). 없으면 내보내지 않는다."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    extra = {"export_vertex_color": "NAME", "export_vertex_color_name": vertex_color, "export_all_vertex_colors": False} \
        if vertex_color else {"export_vertex_color": "NONE"}
    bpy.ops.export_scene.gltf(
        **extra,
        filepath=path,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_anim_slide_to_zero=True,
        export_skins=True,
        export_def_bones=False,
        export_morph=False,
        export_materials="EXPORT",
    )


def save_blend(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, check_existing=False)


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def cloth_scrap(part, size, seed, bone=None, surface=0, center=(0, 0, 0.012)):
    """찢긴 옷 조각: 들쭉날쭉한 납작한 다각형(바닥에 눕힘)."""
    rnd = random.Random(seed)
    pts = []
    n = 11
    for i in range(n):
        a = 2 * math.pi * i / n
        r = size * (0.55 + 0.45 * rnd.random())
        pts.append((r * math.cos(a), r * math.sin(a) * 0.7))
    m = Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.radians(-90), 4, "X")
    part.polygon_slab(pts, 0.012, m, bone or "_static", surface)
