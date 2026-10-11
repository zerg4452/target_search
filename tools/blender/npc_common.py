"""NPC 공용 골격·애니메이션·도형 도우미 (GAME_DESIGN.md §12.4~§12.5).

Blender 5.2 배경 모드에서 쓴다. 좌표: Blender Z 위, 인물 정면 +Y, 인물의 왼쪽 -X.
glTF로 내보내면 Godot에서 정면 -Z, 오른쪽 +X가 된다.

모든 부품은 뼈 하나에 가중치 1로 붙는 강체 스키닝(마네킹 관절 방식)이다.
부품 하나 = 슬롯 노드 하나 = Blender 오브젝트 하나. 오브젝트 이름이 슬롯 노드 이름이다(§12.5 이름 계약).
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
        self.bone_names = []

    def _bone_index(self, bone):
        if bone not in self.bone_names:
            self.bone_names.append(bone)
        return self.bone_names.index(bone)

    def add_bm(self, src, matrix, bone, surface=0, smooth=True, flip=False):
        """임시 bmesh를 변환해 복사해 넣는다."""
        bi = self._bone_index(bone)
        vmap = {}
        for v in src.verts:
            nv = self.bm.verts.new(matrix @ v.co)
            nv[self.bone_layer] = bi
            vmap[v] = nv
        for f in src.faces:
            vs = [vmap[v] for v in f.verts]
            if flip:
                vs.reverse()
            try:
                nf = self.bm.faces.new(vs)
            except ValueError:
                continue
            nf.material_index = surface
            nf.smooth = smooth
        src.free()

    # ---- 기본 도형 (모두 임시 bmesh를 만든 뒤 add_bm) ----
    def ellipsoid(self, center, radii, bone, surface=0, seg=(16, 10), keep=None, smooth=True):
        b = bmesh.new()
        bmesh.ops.create_uvsphere(b, u_segments=seg[0], v_segments=seg[1], radius=1.0)
        m = Matrix.Translation(Vector(center)) @ Matrix.Diagonal(Vector(radii)).to_4x4()
        if keep is not None:
            # keep(world_point) 가 거짓인 꼭짓점을 지운다(머리카락 경계 등).
            dead = [v for v in b.verts if not keep(m @ v.co)]
            bmesh.ops.delete(b, geom=dead, context="VERTS")
        self.add_bm(b, m, bone, surface, smooth)

    def tube(self, p0, p1, r0, r1, bone, surface=0, seg=12, caps=True, smooth=True, squash=1.0):
        """p0→p1 축의 원뿔대. squash는 단면을 정면(Y) 방향으로 납작하게 한다."""
        p0 = Vector(p0)
        p1 = Vector(p1)
        axis = p1 - p0
        length = axis.length
        b = bmesh.new()
        bmesh.ops.create_cone(b, cap_ends=caps, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=length)
        # create_cone: Z축, 중심이 원점. 아래(-Z)가 radius1.
        rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
        m = Matrix.Translation((p0 + p1) * 0.5) @ rot @ Matrix.Diagonal(Vector((1.0, squash, 1.0))).to_4x4()
        self.add_bm(b, m, bone, surface, smooth)

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
        # 꼭짓점 높이로 뼈를 정한다: 조각을 높이 구간별로 나눠 넣는다.
        groups = {}
        for f in b.faces:
            zc = sum(v.co.z for v in f.verts) / len(f.verts)
            groups.setdefault(bone_of(zc), []).append(f)
        for bone, faces in groups.items():
            sub = bmesh.new()
            vmap = {}
            for f in faces:
                vs = []
                for v in f.verts:
                    if v not in vmap:
                        vmap[v] = sub.verts.new(v.co)
                    vs.append(vmap[v])
                sub.faces.new(vs)
            self.add_bm(sub, Matrix.Identity(4), bone, surface, True)
        b.free()

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
        return out

    # ---- 오브젝트로 만들기 ----
    def build(self, arm_obj, mats, collection):
        me = bpy.data.meshes.new(self.name)
        self.bm.verts.ensure_lookup_table()
        bones = [self.bone_names[v[self.bone_layer]] for v in self.bm.verts]
        tris = sum(len(f.verts) - 2 for f in self.bm.faces)
        used = sorted({f.material_index for f in self.bm.faces})
        if used != list(range(len(self.materials))):
            raise RuntimeError(f"{self.name}: 표면 {used}가 재질 {self.materials}와 맞지 않음")
        self.bm.to_mesh(me)
        self.bm.free()
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
                if bn not in groups:
                    groups[bn] = ob.vertex_groups.new(name=bn)
                groups[bn].add([i], 1.0, "REPLACE")
        return ob, tris


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

def head_surface_y(x, z, lift=0.0):
    """머리 타원체 정면(+Y) 표면의 y."""
    u = ((x - HEAD_C.x) / HEAD_R.x) ** 2 + ((z - HEAD_C.z) / HEAD_R.z) ** 2
    return HEAD_C.y + HEAD_R.y * math.sqrt(max(0.0, 1.0 - u)) + lift


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
    """어깨(z_top)에서 z_end까지 팔을 감싸는 소매. 팔꿈치에서 둘로 나눠 각 뼈에 붙인다."""
    elbow = 1.13
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

def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
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
