"""쇼핑몰 손님 외형 세트(§6.1): 타입 A 후드, B 코트, C 패딩 조끼, D 정장(예비)과 플레이어.

함수마다 슬롯 노드(Part)를 만든다. 노드 이름과 표면(재질) 순서는 data/outfits/mall_guest/*/appearance.json·variants.json과 맞아야 한다.
모든 부품은 결정적(난수 시드 고정)이다.
"""
import math

import bmesh
from mathutils import Matrix, Vector

from npc_common import (HEAD_C, HEAD_R, Part, Profile, arm_point, bone_by_height, cloth_scrap, head_surface_y,
                        leg_point, rx, ry, rz, sculpt_head_point, sleeve, trouser_legs)

# 고품질 얼굴·손(D-35). 생성기가 켠다(npc_common.HEAD_SCULPT와 함께).
HQ_FACE = False
EYE_X = 0.031
EYE_Z = 1.615


# ============================================================== 공용

def stick(part, start, surf, plane_y, depth, lift=0.002, sign=1.0, max_edge=0.02):
    """start 이후 꼭짓점(평면 plane_y, 두께 depth로 만든 판)을 표면 surf(x, z)에 붙인다.
    볼록한 몸통에 평평한 큰 면을 붙이면 꼭짓점 사이가 몸 안으로 묻히므로, 먼저 면을 잘게 나눈다."""
    bm = part.bm
    bm.verts.ensure_lookup_table()
    fresh = set(bm.verts[start:])
    faces = [f for f in bm.faces if all(v in fresh for v in f.verts)]
    if faces and max_edge > 0.0:
        # 앞뒤(±Y)를 향한 넓은 면만 나눈다. 옆면·모서리는 그대로 둔다.
        for f in faces:
            f.normal_update()
        broad = [f for f in faces if abs(f.normal.y) > 0.7]
        if broad:
            res = bmesh.ops.triangulate(bm, faces=broad)
            tris = res["faces"]
            edges = list({e for f in tris for e in f.edges})
            longest = max(e.calc_length() for e in edges)
            cuts = min(6, int(math.ceil(longest / max_edge)) - 1)
            if cuts > 0:
                bmesh.ops.subdivide_edges(bm, edges=edges, cuts=cuts, use_grid_fill=True)
    bm.verts.ensure_lookup_table()
    for v in bm.verts[start:]:
        v.co.y = surf(v.co.x, v.co.z) + sign * (lift + (v.co.y - plane_y) * sign + depth * 0.5)


def _dense(path, step=0.02):
    """[(a, z), ...] 제어점 사이를 z·각 거리 기준으로 촘촘하게."""
    out = []
    for (a0, z0), (a1, z1) in zip(path, path[1:]):
        n = max(1, int(max(abs(z1 - z0), abs(a1 - a0) * 0.003) / step))
        for i in range(n):
            t = i / n
            out.append((a0 + (a1 - a0) * t, z0 + (z1 - z0) * t))
    out.append(path[-1])
    return out


def surf_seam(part, prof, path, surface=0, width=0.0042, thick=0.0016, lift=0.0008):
    """몸통 표면을 따라가는 솔기·가장자리(같은 재질의 얇은 띠, D-35 디테일). path = [(정면 기준 각°, z), ...]"""
    if not HQ_FACE:
        return
    pts = [prof.point(a, z, lift) for a, z in _dense(path)]
    part.ribbon(pts, width, thick, prof.outward, lambda q: bone_by_height(q.z), surface)


def leg_radius(z, z_hem, r_thigh, r_knee, r_hem):
    if z > 0.5:
        return r_knee + (r_thigh - r_knee) * min(1.0, (z - 0.47) / 0.46)
    return r_hem + (r_knee - r_hem) * max(0.0, (z - z_hem) / max(0.5 - z_hem, 1e-3))


def leg_seam(part, side, z_top, z_hem, radii, angle_deg, surface=0, width=0.0042, thick=0.0017, lift=0.0032):
    """radii = (밑단 높이, 허벅지 반지름, 무릎 반지름, 밑단 반지름) — trouser_legs와 같은 값."""
    """바짓가랑이를 따라 내려가는 솔기·주름선. angle_deg: 정면 0°, 바깥쪽 90°(좌우 대칭)."""
    if not HQ_FACE:
        return
    sx = -1.0 if side == "L" else 1.0
    a = math.radians(angle_deg)
    d = Vector((sx * math.sin(a), math.cos(a), 0.0))
    pts = []
    z = z_top
    while z > z_hem + 0.01:
        r = leg_radius(z, *radii)
        pts.append(leg_point(side, z) + d * (r + lift))
        z -= 0.02
    part.ribbon(pts, width, thick, lambda q: d, lambda q: f"thigh_{side}" if q.z > 0.5 else f"shin_{side}", surface)


def waistband(part, rings, z0, z1, surface=0, grow=1.03):
    """허리 밴드: 골반 단면보다 조금 큰 띠."""
    if not HQ_FACE:
        return
    prof = Profile(rings)
    band = []
    for z in (z0, z1):
        rx_, ry_, yo = prof.at(z)
        band.append((z, rx_ * grow, ry_ * grow, yo))
    part.loft(band, lambda z: "hips", surface, seg=22, cap_top=False)


def belt_loops(part, prof, z, surface=0):
    if not HQ_FACE:
        return
    for a in (-150.0, -62.0, 62.0, 150.0, 180.0):
        q = prof.point(a, z, 0.006)
        n = prof.outward(q)
        rot = Vector((0, 1, 0)).rotation_difference(n).to_matrix()
        part.box(q, (0.011, 0.005, 0.04), "hips", surface, rot=rot)


def transform_part(part, matrix):
    part.bm.verts.ensure_lookup_table()
    for v in part.bm.verts:
        v.co = matrix @ v.co


def sculpted_head(p):
    """조각한 머리(D-35): 촘촘한 타원체를 턱선·눈구멍·광대·입 둘레·턱끝 모양으로 옮긴다."""
    b = bmesh.new()
    bmesh.ops.create_uvsphere(b, u_segments=34, v_segments=24, radius=1.0)
    for v in b.verts:
        q = Vector((HEAD_C.x + v.co.x * HEAD_R.x, HEAD_C.y + v.co.y * HEAD_R.y, HEAD_C.z + v.co.z * HEAD_R.z))
        v.co = sculpt_head_point(q)
    p.add_bm(b, Matrix.Identity(4), "head", 0, True)


def nose(p):
    # 콧대: 높이별 타원 단면을 이은 한 덩어리. 뒤쪽 절반은 얼굴 속에 묻힌다.
    rings = []
    for i in range(9):
        t = i / 8
        z = 1.634 - 0.046 * t
        prot = 0.0015 + 0.0125 * t ** 1.15
        yo = head_surface_y(0.0, z) - 0.006
        rings.append((z, 0.0060 + 0.0032 * t, prot + 0.006, yo))
    p.loft(list(reversed(rings)), lambda z: "head", seg=16, cap_bottom=True, cap_top=True)
    p.ellipsoid((0.0, head_surface_y(0.0, 1.586) + 0.0098, 1.586), (0.0088, 0.0082, 0.0074), "head", seg=(14, 10))
    for sx in (-1.0, 1.0):
        x = sx * 0.0102
        p.ellipsoid((x * 0.9, head_surface_y(x, 1.583) + 0.0022, 1.583), (0.0058, 0.0058, 0.0048), "head", seg=(10, 8))


def ears(p):
    for sx in (-1.0, 1.0):
        p.ellipsoid((sx * 0.0845, -0.004, 1.597), (0.0085, 0.0205, 0.031), "head", seg=(12, 10))
        p.ellipsoid((sx * 0.0905, -0.006, 1.600), (0.0035, 0.0175, 0.027), "head", seg=(10, 8))   # 귓바퀴 테
        p.ellipsoid((sx * 0.0855, -0.001, 1.574), (0.0072, 0.0095, 0.012), "head", seg=(10, 8))  # 귓불


def eyelids(p):
    """윗눈꺼풀: 눈알 윗부분을 덮는 피부 껍질(얼굴 노드의 눈알과 같은 자리)."""
    for sx in (-1.0, 1.0):
        x = sx * EYE_X
        c = Vector((x, head_surface_y(x, EYE_Z) - 0.0035, EYE_Z + 0.0004))
        p.ellipsoid(c, (0.0142, 0.0098, 0.0096), "head", seg=(14, 10), keep=lambda q, c=c: q.z > c.z + 0.0032 and q.y > c.y - 0.004)


def hand(p, side):
    """손바닥 + 손가락 넷(세 마디) + 엄지(두 마디). 손바닥은 몸 쪽을 본다. 손 뼈에 강체로 붙는다."""
    sx = -1.0 if side == "L" else 1.0
    inward = -sx
    bone = f"hand_{side}"
    cx = arm_point(side, 0.89).x * 1.02
    p.ellipsoid((cx, 0.004, 0.850), (0.0175, 0.037, 0.043), bone, seg=(12, 9))
    p.ellipsoid((cx - inward * 0.004, 0.004, 0.872), (0.015, 0.03, 0.024), bone, seg=(10, 6))   # 손목 쪽 두께
    for fy, length, r in ((0.024, 0.070, 0.0080), (0.0085, 0.078, 0.0083), (-0.0075, 0.074, 0.0080), (-0.022, 0.060, 0.0071)):
        pt = Vector((cx, 0.004 + fy, 0.812))
        ang = 0.0
        rr = r
        for frac, bend in ((0.45, 8.0), (0.32, 16.0), (0.23, 13.0)):
            ang += math.radians(bend)
            d = Vector((math.sin(ang) * inward, 0.0, -math.cos(ang)))
            nxt = pt + d * length * frac
            p.ellipsoid(pt, (rr, rr, rr), bone, seg=(6, 4))
            p.tube(pt, nxt, rr, rr * 0.93, bone, seg=6, caps=False, lengthwise=False)
            pt = nxt
            rr *= 0.93
        p.ellipsoid(pt, (rr, rr, rr * 1.1), bone, seg=(7, 5))
        # 손톱: 손가락 끝 바깥쪽(손등 쪽)의 납작한 볼록
        p.ellipsoid(pt + Vector((-inward * rr * 0.75, 0.0, rr * 0.9)), (rr * 0.35, rr * 0.75, rr * 1.0), bone, seg=(6, 4))
        # 손등 마디(손가락 뿌리)
        p.ellipsoid(Vector((cx - inward * 0.0125, 0.004 + fy, 0.818)), (0.006, 0.0075, 0.0075), bone, seg=(6, 4))
    tb = Vector((cx + inward * 0.011, 0.004 + 0.031, 0.846))
    d1 = Vector((inward * 0.35, 0.42, -0.84)).normalized()
    d2 = Vector((inward * 0.55, 0.30, -0.78)).normalized()
    t1 = tb + d1 * 0.032
    t2 = t1 + d2 * 0.026
    p.ellipsoid(tb, (0.0105, 0.0105, 0.0105), bone, seg=(6, 4))
    p.tube(tb, t1, 0.0102, 0.0094, bone, seg=6, caps=False, lengthwise=False)
    p.ellipsoid(t1, (0.0094, 0.0094, 0.0094), bone, seg=(6, 4))
    p.tube(t1, t2, 0.0094, 0.0086, bone, seg=6, caps=False, lengthwise=False)
    p.ellipsoid(t2, (0.0086, 0.0086, 0.0094), bone, seg=(7, 5))


def body_skin():
    p = Part("Body", ["mat_skin"])
    if HQ_FACE:
        sculpted_head(p)
        nose(p)
        ears(p)
        eyelids(p)
    else:
        p.ellipsoid(HEAD_C, HEAD_R, "head", seg=(20, 12))
        for sx in (-1.0, 1.0):
            p.ellipsoid((sx * 0.083, 0.0, 1.595), (0.012, 0.022, 0.03), "head", seg=(8, 6))
        p.ellipsoid((0.0, head_surface_y(0.0, 1.587) - 0.004, 1.587), (0.011, 0.016, 0.021), "head", seg=(8, 6))
    if HQ_FACE:
        p.tube((0, -0.004, 1.40), (0, 0.0, 1.55), 0.054, 0.047, "neck", seg=14, squash=0.92)
    else:
        p.tube((0, 0, 1.40), (0, 0, 1.53), 0.048, 0.044, "neck", seg=12)
    for side in ("L", "R"):
        p.tube(arm_point(side, 1.40), arm_point(side, 1.13), 0.042, 0.036, f"upper_arm_{side}", seg=10, lengthwise=False)
        p.ellipsoid(arm_point(side, 1.13), (0.036, 0.036, 0.036), f"forearm_{side}", seg=(10, 6))
        p.tube(arm_point(side, 1.13), arm_point(side, 0.885), 0.035, 0.028, f"forearm_{side}", seg=10, lengthwise=False)
        if HQ_FACE:
            hand(p, side)
        else:
            hp = arm_point(side, 0.89)
            p.ellipsoid((hp.x * 1.02, 0.006, 0.836), (0.025, 0.043, 0.06), f"hand_{side}", seg=(10, 8))
        p.tube(leg_point(side, 0.92), leg_point(side, 0.50), 0.06, 0.047, f"thigh_{side}", seg=8, lengthwise=False)
        p.tube(leg_point(side, 0.52), leg_point(side, 0.08), 0.045, 0.036, f"shin_{side}", seg=8, lengthwise=False)
    return p


FACE_MATS = ["mat_feature", "mat_eye_white", "mat_iris", "mat_lip"]


def brow(p, sx, frown):
    """가늘어지는 눈썹(안쪽이 두껍다). frown이면 안쪽이 내려간다."""
    pts = []
    for i in range(7):
        t = i / 6
        x = sx * (0.013 + 0.033 * t)
        z = 1.642 + 0.0045 * math.sin(math.pi * (0.25 + 0.75 * t)) - (0.0065 * (1.0 - t) if frown else 0.0)
        pts.append(Vector((x, head_surface_y(x, z) + 0.0012, z)))
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        r0 = 0.0034 - 0.0018 * i / 6
        p.tube(a, b, r0, r0 - 0.0003, "head", 0, seg=5, squash=0.45, lengthwise=False)


def mouth(p, kind):
    def mz(x):
        if kind == "smile":
            return 1.543 + 30.0 * x * x
        return 1.548 - 1.5 * x * x
    pts = []
    for i in range(11):
        x = -0.0195 + 0.039 * i / 10
        z = mz(x)
        pts.append(Vector((x, head_surface_y(x, z) + 0.0018, z)))
    for a, b in zip(pts, pts[1:]):
        p.tube(a, b, 0.0011, 0.0011, "head", 0, seg=5, squash=0.6, lengthwise=False)
    # 윗입술·아랫입술(입술 색): 입선 위아래의 납작한 볼록
    zc = mz(0.0)
    p.ellipsoid((0.0, head_surface_y(0.0, zc + 0.0042) - 0.0012, zc + 0.0042), (0.0185, 0.0036, 0.0036), "head", 3, seg=(16, 8))
    p.ellipsoid((0.0, head_surface_y(0.0, zc - 0.0058) - 0.0012, zc - 0.0058), (0.0160, 0.0044, 0.0048), "head", 3, seg=(16, 8))


def face(name, mouth_kind="neutral", brows="flat", mole=False):
    """표정 = 눈·눈썹·입(§12.2: 분명한 명도 대비). 조각한 머리 표면에 붙인다(D-35: 입체 눈과 입술)."""
    if not HQ_FACE:
        return face_simple(name, mouth_kind, brows, mole)
    p = Part(name, FACE_MATS)
    for sx in (-1.0, 1.0):
        x = sx * EYE_X
        y0 = head_surface_y(x, EYE_Z)
        c = Vector((x, y0 - 0.0035, EYE_Z))
        p.ellipsoid(c, (0.0128, 0.0088, 0.0084), "head", 1, seg=(12, 9))                       # 흰자
        p.ellipsoid(c + Vector((0, 0.0074, -0.0004)), (0.0062, 0.0018, 0.0062), "head", 2, seg=(12, 5))   # 홍채
        p.ellipsoid(c + Vector((0, 0.0090, -0.0004)), (0.0028, 0.0007, 0.0028), "head", 0, seg=(8, 4))   # 동공
        # 윗속눈썹 선: 눈꺼풀 가장자리를 따라가는 짙은 선
        pts = []
        for i in range(9):
            t = -1.0 + 2.0 * i / 8
            xx = x + sx * 0.0138 * t
            zz = EYE_Z + 0.0036 + 0.0040 * (1.0 - t * t)
            pts.append(Vector((xx, head_surface_y(xx, zz) - 0.0002 + 0.0042 * (1.0 - t * t) ** 0.5, zz)))
        for a, b in zip(pts, pts[1:]):
            p.tube(a, b, 0.0013, 0.0013, "head", 0, seg=5, lengthwise=False)
        brow(p, sx, brows == "frown")
    mouth(p, mouth_kind)
    if mole:
        x = -0.037
        p.ellipsoid((x, head_surface_y(x, 1.588), 1.588), (0.0085, 0.004, 0.0085), "head", 0, seg=(8, 6))
    return p


def face_simple(name, mouth="neutral", brows="flat", mole=False):
    """표정 = 눈·눈썹·입 도형(§12.2: 분명한 명도 대비). 머리 타원체 표면에 붙인다."""
    p = Part(name, ["mat_feature"])
    for sx in (-1.0, 1.0):
        x = sx * 0.031
        p.ellipsoid((x, head_surface_y(x, 1.615) - 0.002, 1.615), (0.011, 0.005, 0.0075), "head", seg=(10, 6))
        bz = 1.643 if brows == "flat" else 1.640
        ang = 0.0 if brows == "flat" else -sx * 18.0
        p.box((x, head_surface_y(x, bz) + 0.0005, bz), (0.031, 0.006, 0.0058), "head", rot=ry(ang))
    if mouth == "neutral":
        p.box((0.0, head_surface_y(0.0, 1.548) + 0.0005, 1.548), (0.036, 0.006, 0.0055), "head")
    else:
        pts = []
        for i in range(9):
            x = -0.027 + 0.054 * i / 8
            z = 1.543 + 17.0 * x * x
            pts.append(Vector((x, head_surface_y(x, z) + 0.0005, z)))
        for a, b in zip(pts, pts[1:]):
            p.tube(a, b, 0.0034, 0.0034, "head", seg=6, squash=0.6)
    if mole:
        x = -0.037
        p.ellipsoid((x, head_surface_y(x, 1.588), 1.588), (0.0085, 0.004, 0.0085), "head", seg=(8, 6))
    return p


def hair_cap(part, hairline, scale=(1.07, 1.06, 1.05), shift=(0.0, -0.003, 0.007), top=None, surface=0, seg=(22, 14)):
    c = HEAD_C + Vector(shift)
    r = Vector((HEAD_R.x * scale[0], HEAD_R.y * scale[1], HEAD_R.z * scale[2]))

    def keep(p):
        if top is not None and p.z > top:
            return False
        return p.z > hairline(p)

    part.ellipsoid(c, r, "head", surface, seg, keep=keep)
    return c, r


def cap_surface_z(c, r, x, y, lift=0.0):
    u = ((x - c.x) / r.x) ** 2 + ((y - c.y) / r.y) ** 2
    return c.z + r.z * math.sqrt(max(0.0, 1.0 - u)) + lift


def sph(c, r, az, el, lift=0.0):
    """머리카락 덮개(타원체 c, r) 위의 점과 바깥 법선. az: 정면 0°·오른쪽(+X) 90°, el: 적도 0°·정수리 90°(넘으면 뒤로)."""
    a = math.radians(az)
    e = math.radians(el)
    d = Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))
    q = Vector((c.x + r.x * d.x, c.y + r.y * d.y, c.z + r.z * d.z))
    n = Vector((d.x / r.x, d.y / r.y, d.z / r.z)).normalized()
    return q + n * lift, n


def _interp(path, t):
    k = len(path) - 1
    f = min(t * k, k - 1e-6)
    i = int(f)
    u = f - i
    a, b = path[i], path[i + 1]
    return a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u


def hair_lock(part, c, r, path, width, hairline=None, surface=0, lift=(0.002, 0.0048, 0.0018), thick=0.0034, steps=8):
    """머리 다발 하나: 덮개 표면을 따라 path[(az, el)]로 흐르고 끝으로 갈수록 가늘어진다.
    hairline(점)보다 아래로 내려가는 끝은 머리선 위에서 멈춘다."""
    pts, nrm, ws, th = [], [], [], []
    for i in range(steps + 1):
        t = i / steps
        az, el = _interp(path, t)
        lf = lift[0] + (lift[1] - lift[0]) * min(1.0, t / 0.4) if t < 0.4 else lift[1] + (lift[2] - lift[1]) * (t - 0.4) / 0.6
        q, n = sph(c, r, az, el, lf)
        if hairline is not None and i > 2 and q.z < hairline(q) + 0.004:
            break
        pts.append(q)
        nrm.append(n)
        ws.append(width * (1.0 - 0.8 * t ** 1.4))
        th.append(thick * (1.0 - 0.6 * t))
    if len(pts) >= 3:
        part.sweep(pts, nrm, ws, th, "head", surface, sides=6)


def side_part_locks(part, c, r, part_x, hairline, surface=0):
    """옆 가르마 머리(D-35): 가르마에서 한쪽으로 넘긴 다발, 반대쪽으로 짧게 넘긴 다발, 정수리에서 뒤로 내린 다발.
    part_x 쪽의 반대 방향으로 넘긴다(왼쪽 가르마면 오른쪽으로)."""
    to = 1.0 if part_x < 0 else -1.0
    for k in range(18):
        el = 32.0 + 2.7 * k
        arg = (part_x - to * 0.006) / (r.x * math.cos(math.radians(el)))
        if abs(arg) >= 0.98:
            continue
        az = math.degrees(math.asin(arg))
        hair_lock(part, c, r, [(az, el), (az + to * 32.0, el - 6.0), (az + to * 70.0, max(14.0, el - 26.0))],
                  0.023 + 0.005 * (k % 3), hairline, surface, thick=0.0042, lift=(0.0025, 0.0062, 0.002))
    for k in range(10):
        el = 38.0 + 3.6 * k
        arg = (part_x + to * 0.006) / (r.x * math.cos(math.radians(el)))
        if abs(arg) >= 0.98:
            continue
        az = math.degrees(math.asin(arg))
        hair_lock(part, c, r, [(az, el), (az - to * 22.0, el - 10.0), (az - to * 46.0, max(20.0, el - 26.0))],
                  0.017 + 0.004 * (k % 2), hairline, surface, thick=0.0038)
    for k in range(13):
        az = 106.0 + 12.0 * k
        hair_lock(part, c, r, [(az + to * 4.0, 74.0), (az, 50.0), (az - to * 3.0, 18.0)], 0.022, hairline, surface,
                  lift=(0.0008, 0.003, 0.0015), thick=0.003)


def part_line(part, c, r, x, surface=1):
    if HQ_FACE:
        # 가르마: 매끈한 피부색 띠(앞 → 정수리)
        pts, nrm = [], []
        for i in range(9):
            y = 0.088 - 0.115 * i / 8
            z = cap_surface_z(c, r, x, y, 0.0012)
            q = Vector((x, y, z))
            pts.append(q)
            nrm.append(Vector(((q.x - c.x) / r.x ** 2, (q.y - c.y) / r.y ** 2, (q.z - c.z) / r.z ** 2)).normalized())
        part.sweep(pts, nrm, [0.0042] * len(pts), 0.0011, "head", surface, sides=6, tip=False)
        return
    part_line_boxes(part, c, r, x, surface)


def part_line_boxes(part, c, r, x, surface=1):
    """가르마: 머리카락 위의 피부색 줄(앞 → 정수리)."""
    pts = []
    for i in range(7):
        y = 0.088 - 0.115 * i / 6
        pts.append(Vector((x, y, cap_surface_z(c, r, x, y, 0.0015))))
    for a, b in zip(pts, pts[1:]):
        mid = (a + b) * 0.5
        d = b - a
        ang = math.degrees(math.atan2(d.z, -d.y))
        part.box(mid, (0.011, d.length + 0.002, 0.004), "head", surface, rot=rx(ang))


def hair_a(name, long=False, gloss=False):
    p = Part(name, ["mat_hair_brown_gloss" if gloss else "mat_hair_brown", "mat_skin"])
    if long:
        c, r = hair_cap(p, lambda q: 1.535 + 0.55 * q.y)
        p.ellipsoid((0.0, -0.062, 1.52), (0.088, 0.05, 0.11), "head", seg=(16, 10))
        for sx in (-1.0, 1.0):
            p.ellipsoid((sx * 0.084, -0.008, 1.575), (0.022, 0.065, 0.072), "head", seg=(12, 8))
    else:
        c, r = hair_cap(p, lambda q: 1.60 + 0.6 * q.y)
    # 가르마 반대쪽(오른쪽)으로 넘긴 앞머리 덩어리 — 좌우 반전 변이가 잘 보이게 한다.
    if HQ_FACE:
        p.ellipsoid((0.034, 0.078, 1.668), (0.04, 0.026, 0.016), "head", seg=(14, 8))
        side_part_locks(p, c, r, -0.034, lambda q: (1.535 + 0.55 * q.y) if long else (1.60 + 0.6 * q.y))
    else:
        p.ellipsoid((0.036, 0.083, 1.676), (0.052, 0.034, 0.027), "head", seg=(14, 8))
    part_line(p, c, r, -0.034)
    return p


def round_sole(part, x, y0, rx, ry, h, bone, surface):
    """신발 모양을 따르는 둥근 밑창(D-35). 위아래 가장자리를 조금 둥글린 타원 판."""
    start = part.vert_count()
    part.loft([(0.0, rx * 0.97, ry * 0.985, y0), (h * 0.25, rx, ry, y0), (h * 0.8, rx, ry, y0), (h, rx * 0.97, ry * 0.985, y0)],
              lambda z: bone, surface, seg=26, cap_bottom=True, cap_top=True)
    part.bm.verts.ensure_lookup_table()
    for v in part.bm.verts[start:]:
        v.co.x += x


def sneaker(part, side, mats=(0, 1, 2), thick=0.0, laces=True, stripes=True, high=False, sole_surface=None):
    """mats = (몸통, 끈, 줄무늬) 표면 번호. 오른발 기준을 side로 좌우 반전."""
    sx = -1.0 if side == "L" else 1.0
    x = sx * 0.09
    bone = f"foot_{side}"
    s_body, s_lace, s_stripe = mats
    sole_h = 0.028 + thick
    if HQ_FACE:
        round_sole(part, x, 0.058, 0.053, 0.137, sole_h, bone, sole_surface if sole_surface is not None else s_body)
    else:
        part.box((x, 0.06, sole_h * 0.5), (0.098, 0.27, sole_h), bone, sole_surface if sole_surface is not None else s_body, bevel=0.008)
    zc = sole_h + 0.022
    part.ellipsoid((x, 0.055, zc), (0.05, 0.128, 0.046), bone, s_body, seg=(14, 8), keep=lambda q: q.z > sole_h - 0.004)
    collar_top = 0.17 + thick if high else 0.095 + thick
    part.tube((x, -0.012, sole_h + 0.02), (x, -0.012, collar_top), 0.049, 0.047, bone, s_body, seg=12)
    if laces:
        for i in range(4):
            y = 0.035 + i * 0.025
            z = zc + 0.046 * math.sqrt(max(0.0, 1.0 - ((y - 0.055) / 0.128) ** 2)) + 0.003
            part.box((x, y, z), (0.042, 0.008, 0.006), bone, s_lace)
        if high:
            for i in range(3):
                part.box((x, 0.032, collar_top - 0.015 - i * 0.022), (0.04, 0.008, 0.006), bone, s_lace)
    if HQ_FACE:
        part.ellipsoid((x, -0.055, sole_h + 0.03), (0.05, 0.03, 0.038), bone, s_body, seg=(12, 8))      # 뒤꿈치 보강
        part.box((x, 0.03, zc + 0.05), (0.036, 0.05, 0.01), bone, s_body, rot=rx(-28), bevel=0.003)     # 혀
        if laces:
            ky = 0.035 + 3 * 0.025
            kz = zc + 0.046 * math.sqrt(max(0.0, 1.0 - ((ky - 0.055) / 0.128) ** 2)) + 0.007
            for s2 in (-1.0, 1.0):
                part.torus((x + s2 * 0.012, ky - 0.006, kz), 0.009, 0.0022, bone, s_lace, seg=(10, 4), rot=ry(90 + s2 * 25))
                part.tube((x + s2 * 0.004, ky, kz), (x + s2 * 0.016, ky - 0.02, kz - 0.016), 0.0022, 0.002, bone, s_lace, seg=5)
    if stripes:
        ox = x + sx * 0.049
        for k, z in enumerate((zc - 0.004, zc + 0.014)):
            part.box((ox, 0.07, z), (0.006, 0.11 - k * 0.02, 0.008), bone, s_stripe, rot=rx(-8))


def low_shoe(part, side, surface=0, height=0.035, strap=False, toe_seam=False):
    sx = -1.0 if side == "L" else 1.0
    x = sx * 0.09
    bone = f"foot_{side}"
    if HQ_FACE:
        round_sole(part, x, 0.057, 0.05, 0.134, 0.024, bone, surface)
    else:
        part.box((x, 0.06, 0.012), (0.094, 0.265, 0.024), bone, surface, bevel=0.007)
    part.ellipsoid((x, 0.055, 0.045), (0.047, 0.127, height), bone, surface, seg=(14, 8), keep=lambda q: q.z > 0.02)
    part.tube((x, -0.02, 0.03), (x, -0.02, 0.085), 0.045, 0.044, bone, surface, seg=12)
    if HQ_FACE:
        part.box((x, -0.042, 0.016), (0.08, 0.07, 0.032), bone, surface, bevel=0.004)                # 굽
        start = part.vert_count()
        part.torus((0.0, 0.057, 0.0), 1.0, 0.06, bone, surface, seg=(30, 4), scale=(0.051, 0.135, 0.047))   # 웰트
        part.bm.verts.ensure_lookup_table()
        for v in part.bm.verts[start:]:
            v.co.x += x
            v.co.z += 0.025
    if strap:
        part.box((x, 0.085, 0.072), (0.07, 0.022, 0.008), bone, surface, rot=rx(-14))
    if toe_seam:
        part.box((x, 0.12, 0.066), (0.07, 0.006, 0.006), bone, surface, rot=rx(-28))


def pelvis(part, rings, surface=0):
    part.loft(rings, lambda z: "hips", surface, seg=18, cap_top=True)


# ============================================================== 타입 A: 후드 손님

HOODIE = [(0.86, 0.178, 0.128, 0.0), (0.92, 0.176, 0.127, 0.0), (1.05, 0.170, 0.122, 0.0), (1.20, 0.178, 0.126, 0.0),
          (1.32, 0.190, 0.124, 0.0), (1.39, 0.192, 0.115, -0.005), (1.435, 0.155, 0.095, -0.01), (1.46, 0.07, 0.055, -0.01)]
HOODIE_P = Profile(HOODIE)
JEANS_PELVIS = [(0.73, 0.158, 0.108, 0.0), (0.80, 0.170, 0.12, 0.0), (0.90, 0.172, 0.12, 0.0), (0.95, 0.170, 0.118, 0.0)]
JEANS_P = Profile(JEANS_PELVIS)


def hoodie(name, rolled_right=False):
    p = Part(name, ["mat_hoodie_gray"])
    p.loft(HOODIE, bone_by_height, seg=22, cap_bottom=True)
    p.loft([(0.855, 0.183, 0.133, 0.0), (0.895, 0.181, 0.131, 0.0)], lambda z: "hips", seg=22, cap_top=False)
    p.ellipsoid((0.0, -0.10, 1.445), (0.12, 0.068, 0.075), "chest", seg=(14, 8))
    p.torus((0.0, -0.008, 1.452), 0.078, 0.019, "chest", seg=(18, 6), scale=(1.0, 0.9, 1.0))
    for side in ("L", "R"):
        if rolled_right and side == "R":
            sleeve(p, side, 1.41, 1.06, 0.062, 0.057)
            p.torus(arm_point(side, 1.05), 0.056, 0.016, "forearm_R", seg=(14, 6))
            p.torus(arm_point(side, 1.08), 0.058, 0.015, "forearm_R", seg=(14, 6))
        else:
            sleeve(p, side, 1.41, 0.94, 0.062, 0.05, cuff=0.025)
    for a in (-90.0, 90.0):
        surf_seam(p, HOODIE_P, [(a, 0.90), (a, 1.37)])
        surf_seam(p, HOODIE_P, [(a, 1.395), (a * 0.92, 1.44)], width=0.0038)
    return p


def kangaroo_pocket():
    p = Part("KangarooPocket", ["mat_pocket_gray"])
    p.box((0.0, 0.0, 1.0), (0.23, 0.012, 0.115), "spine")
    stick(p, 0, lambda x, z: HOODIE_P.front_y(x, z), 0.0, 0.012, lift=0.001)
    # 주머니 입구 테두리(비스듬한 양옆)와 윗단
    for sx in (-1.0, 1.0):
        a0 = math.degrees(math.asin(min(0.99, 0.112 / 0.172))) * sx
        a1 = math.degrees(math.asin(min(0.99, 0.075 / 0.172))) * sx
        surf_seam(p, HOODIE_P, [(a0, 0.95), (a1, 1.052)], lift=0.0135, width=0.005, thick=0.002)
    surf_seam(p, HOODIE_P, [(-25.0, 1.056), (25.0, 1.056)], lift=0.0135, width=0.005, thick=0.002)
    return p


def logo(name, shape):
    p = Part(name, ["mat_print_dark", "mat_print_light"])
    z = 1.285
    if shape == "circle":
        p.tube((0, -0.0015, z), (0, 0.0015, z), 0.05, 0.05, "chest", 0, seg=24, smooth=False)
    else:
        h = 0.115
        w = 0.13
        p.polygon_slab([(-w / 2, -h / 3), (w / 2, -h / 3), (0.0, 2 * h / 3)], 0.003, Matrix.Translation((0, 0, z)), "chest", 0)
    stick(p, 0, lambda x, zz: HOODIE_P.front_y(x, zz), 0.0, 0.003, lift=0.003, max_edge=0.03)
    start = p.vert_count()
    p.text("ECHO", 0.022, Matrix.Translation((0.0, 0.0, z - (0.012 if shape != "circle" else 0.0))), "chest", 1, depth=0.002)
    stick(p, start, lambda x, zz: HOODIE_P.front_y(x, zz), 0.0, 0.002, lift=0.0065, max_edge=0.0)
    return p


def back_text(name, zero=False):
    p = Part(name, ["mat_print_light"])
    z = 1.27
    p.text("ECH0" if zero else "ECHO", 0.115, Matrix.Translation((0, 0, z)) @ rz(180).to_4x4(), "chest", 0, depth=0.003)
    if zero:
        p.bm.verts.ensure_lookup_table()
        xs = [v.co.x for v in p.bm.verts]
        # 등에서 읽히도록 Z축 180° 돌렸으므로 마지막 글자 '0'은 x가 가장 큰 쪽이다.
        x0 = max(xs) - 0.034
        p.box((x0, 0.0, z), (0.009, 0.004, 0.09), "chest", 0, rot=ry(-32))
    stick(p, 0, lambda x, zz: HOODIE_P.front_y(x, zz, -1.0), 0.0, 0.004, lift=0.004, sign=-1.0, max_edge=0.0)
    return p


def hood_strings(name, both=True):
    p = Part(name, ["mat_string_white"])
    for sx in ((-1.0, 1.0) if both else (-1.0,)):
        x = sx * 0.036
        y0 = HOODIE_P.front_y(x, 1.40) + 0.012
        y1 = HOODIE_P.front_y(x, 1.20) + 0.008
        p.tube((x, y0, 1.43), (x, y1, 1.21), 0.0058, 0.0058, "chest", seg=8)
        p.tube((x, y1, 1.215), (x, y1 + 0.001, 1.185), 0.0085, 0.0085, "chest", seg=8)
    return p


def jeans(name, rolled=False):
    p = Part(name, ["mat_denim"])
    pelvis(p, JEANS_PELVIS)
    hem = 0.22 if rolled else 0.13
    trouser_legs(p, hem, 0.072, 0.063, 0.058)
    if rolled:
        for side in ("L", "R"):
            p.tube(leg_point(side, 0.255), leg_point(side, 0.20), 0.067, 0.067, f"shin_{side}", seg=12)
    for sx in (-1.0, 1.0):
        start = p.vert_count()
        p.box((sx * 0.08, 0.0, 0.80), (0.10, 0.008, 0.10), "hips")
        stick(p, start, lambda x, z: JEANS_P.front_y(x, z, -1.0), 0.0, 0.008, lift=0.001, sign=-1.0)
    waistband(p, JEANS_PELVIS, 0.912, 0.952)
    belt_loops(p, JEANS_P, 0.932)
    surf_seam(p, JEANS_P, [(6.0, 0.91), (6.0, 0.83), (-2.0, 0.805)])                 # 앞 지퍼 솔기
    for sx in (-1.0, 1.0):
        surf_seam(p, JEANS_P, [(sx * 62.0, 0.91), (sx * 45.0, 0.865), (sx * 38.0, 0.84)], width=0.005)   # 앞주머니 입구
    radii = (0.072, 0.063, 0.058)
    for side in ("L", "R"):
        leg_seam(p, side, 0.86, hem, (hem,) + radii, 90.0)
    return p


def pants_tab(name, sx):
    p = Part(name, ["mat_tab_red"])
    x = sx * 0.128
    p.box((x, 0.0, 0.832), (0.018, 0.006, 0.032), "hips")
    stick(p, 0, lambda xx, z: JEANS_P.front_y(xx, z, -1.0), 0.0, 0.006, lift=0.009, sign=-1.0)
    return p


def socks(name, mat):
    p = Part(name, [mat])
    for side in ("L", "R"):
        p.tube(leg_point(side, 0.16), leg_point(side, 0.05), 0.047, 0.046, f"shin_{side}", seg=12)
    return p


def sneakers(name, thick=0.0):
    p = Part(name, ["mat_sneaker_white", "mat_lace_white", "mat_stripe_gray"])
    for side in ("L", "R"):
        sneaker(p, side, thick=thick)
    return p


def loafers(name):
    p = Part(name, ["mat_loafer_brown"])
    for side in ("L", "R"):
        low_shoe(p, side, strap=True)
    return p


def sling_bag(name, ring=True, buckle="round"):
    mats = ["mat_bag_black", "mat_keyring_yellow"] if ring else ["mat_bag_black"]
    p = Part(name, mats)
    prof = HOODIE_P
    off = 0.012
    front = [(-90, 1.452), (-55, 1.41), (-28, 1.34), (0, 1.235), (28, 1.13), (60, 1.055), (95, 1.0), (125, 0.995)]
    back = [(-90, 1.452), (-125, 1.41), (-152, 1.33), (-180, 1.23), (-200, 1.13)]
    pts_f = [prof.point(t, z, off) for t, z in front]
    pts_b = [prof.point(t, z, off) for t, z in back]
    p.ribbon(pts_f, 0.036, 0.006, prof.outward, bone_by_height)
    p.ribbon(pts_b, 0.036, 0.006, prof.outward, bone_by_height)
    # 등 오른쪽 아래의 가방 본체
    th = 152.0
    c = prof.point(th, 1.02, 0.048)
    n = prof.outward(c)
    phi = math.degrees(math.atan2(-n.x, n.y))
    p.box(c, (0.27, 0.07, 0.15), "spine", rot=rz(phi) @ ry(-18), bevel=0.02, smooth=True)
    # 가슴의 버클
    bc = prof.point(-6, 1.275, off + 0.008)
    if buckle == "round":
        p.torus(bc, 0.02, 0.0055, "chest", seg=(14, 6), rot=rx(90))
    else:
        for dx, dz, sx_, sz_ in ((0, 0.021, 0.05, 0.009), (0, -0.021, 0.05, 0.009), (0.021, 0, 0.009, 0.05), (-0.021, 0, 0.009, 0.05)):
            p.box((bc.x + dx, bc.y, bc.z + dz), (sx_, 0.008, sz_), "chest")
    if ring:
        tangent = Vector((math.cos(math.radians(phi)), math.sin(math.radians(phi)), 0.0))
        rc = c + tangent * 0.12 + n * 0.035 + Vector((0, 0, -0.045))
        p.torus(rc, 0.017, 0.0045, "spine", 1, seg=(14, 6), rot=rz(phi) @ rx(90))
    return p


def watch(name):
    p = Part(name, ["mat_watch_black"])
    c = arm_point("L", 0.915)
    p.torus(c, 0.032, 0.0075, "forearm_L", seg=(16, 6))
    p.box((c.x - 0.036, c.y + 0.006, c.z), (0.012, 0.032, 0.032), "forearm_L", bevel=0.003)
    return p


def cap(name):
    p = Part(name, ["mat_cap_cream"])
    c = HEAD_C + Vector((0, -0.004, 0.012))
    r = Vector((HEAD_R.x * 1.13, HEAD_R.y * 1.11, HEAD_R.z * 1.06))
    p.ellipsoid(c, r, "head", seg=(20, 12), keep=lambda q: q.z > 1.638)
    p.box((0.0, 0.122, 1.648), (0.16, 0.10, 0.009), "head", rot=rx(-9), bevel=0.004, smooth=True)
    p.ellipsoid((0.0, -0.005, 1.735), (0.012, 0.012, 0.008), "head", seg=(8, 4))
    return p


def earbud(name, side, mat):
    p = Part(name, [mat])
    sx = -1.0 if side == "L" else 1.0
    p.ellipsoid((sx * 0.09, 0.012, 1.597), (0.011, 0.011, 0.011), "head", seg=(10, 6))
    p.tube((sx * 0.092, 0.014, 1.592), (sx * 0.094, 0.018, 1.565), 0.0045, 0.0045, "head", seg=8)
    return p


def earring(name):
    p = Part(name, ["mat_earring_gold"])
    p.torus((-0.09, 0.004, 1.555), 0.017, 0.0038, "head", seg=(14, 6), rot=ry(90))
    return p


def remnant_sling_bag():
    p = Part("Remnant_SlingBag", ["mat_bag_black", "mat_keyring_yellow"])
    p.box((0.0, 0.0, 0.036), (0.27, 0.15, 0.07), "_static", bevel=0.02, smooth=True)
    p.torus((0.22, 0.08, 0.008), 0.11, 0.006, "_static", seg=(20, 4), scale=(1.0, 0.5, 0.6))
    p.torus((0.15, -0.03, 0.008), 0.017, 0.0045, "_static", 1, seg=(14, 6))
    return p


def remnant_sneaker():
    p = Part("Remnant_Sneaker", ["mat_sneaker_white", "mat_lace_white", "mat_stripe_gray"])
    sneaker(p, "R")
    transform_part(p, Matrix.Translation((0, 0, 0.05)) @ Matrix.Rotation(math.radians(80), 4, "Y") @ Matrix.Translation((-0.09, -0.06, -0.05)))
    return p


def build_a_hoodie():
    parts = [
        body_skin(),
        hair_a("HairPartLeft"), hair_a("HairPartLeft").mirrored("HairPartRight"), hair_a("HairLongPartLeft", long=True),
        face("FaceNeutral"), face("FaceSmile", mouth_kind="smile"), face("FaceFrown", brows="frown"), face("FaceNeutralMole", mole=True),
        hoodie("Hoodie"), hoodie("HoodieSleeveRolledR", rolled_right=True),
        kangaroo_pocket(),
        logo("LogoCircle", "circle"), logo("LogoTriangle", "triangle"),
        back_text("BackTextECHO"), back_text("BackTextECH0", zero=True),
        hood_strings("HoodStringsBoth"), hood_strings("HoodStringLeftOnly", both=False),
        jeans("JeansStraight"), jeans("JeansRolled", rolled=True),
        pants_tab("TabRight", 1.0), pants_tab("TabLeft", -1.0),
        socks("Socks", "mat_sock_white"),
        sneakers("Sneakers"), sneakers("SneakersThickSole", thick=0.03), loafers("Loafers"),
        sling_bag("BagSlingLeft"), sling_bag("BagSlingLeft").mirrored("BagSlingRight"),
        sling_bag("BagSlingLeftNoRing", ring=False), sling_bag("BagSlingLeftSquareBuckle", buckle="square"),
        watch("WatchLeft"), watch("WatchLeft").mirrored("WatchRight"),
        cap("CapCream"),
        earbud("EarbudRight", "R", "mat_earbud_white"), earring("EarringLeft"),
    ]
    scrap = Part("Remnant_HoodScrap", ["mat_hoodie_gray"])
    cloth_scrap(scrap, 0.16, 11)
    remnants = [remnant_sling_bag(), scrap, remnant_sneaker()]
    return parts, remnants


# ============================================================== 타입 B: 코트 손님

COAT = [(0.54, 0.235, 0.24, 0.0), (0.70, 0.212, 0.185, 0.0), (0.88, 0.19, 0.145, 0.0), (1.02, 0.183, 0.138, 0.0),
        (1.20, 0.19, 0.138, 0.0), (1.33, 0.203, 0.135, 0.0), (1.395, 0.20, 0.12, -0.005), (1.44, 0.16, 0.10, -0.01),
        (1.47, 0.075, 0.06, -0.01)]
COAT_P = Profile(COAT)
SLACKS_PELVIS = [(0.80, 0.165, 0.115, 0.0), (0.93, 0.168, 0.117, 0.0)]


def hair_b(name, gloss=False):
    p = Part(name, ["mat_hair_black_gloss" if gloss else "mat_hair_black"])
    c, r = hair_cap(p, lambda q: 1.612 + 0.5 * q.y, scale=(1.055, 1.05, 1.045))
    p.ellipsoid((0.0, 0.05, 1.703), (0.07, 0.055, 0.026), "head", seg=(14, 8))
    if HQ_FACE:
        # 뒤로 넘긴 머리: 앞 머리선에서 정수리를 넘어 뒤로 흐르는 다발
        for k in range(21):
            az = -72.0 + 7.2 * k
            hair_lock(p, c, r, [(az, 30.0), (az * 0.8, 75.0), (az * 0.6, 120.0), (az * 0.5, 158.0)], 0.019, None, 0,
                      lift=(0.004, 0.0068, 0.0018), thick=0.004, steps=14)
    return p


def glasses(name, shape):
    p = Part(name, ["mat_glasses_black"])
    z = 1.615
    for sx in (-1.0, 1.0):
        x = sx * 0.032
        y = head_surface_y(x, z) + 0.012
        if shape == "square":
            for dx, dz, w, h in ((0, 0.013, 0.038, 0.004), (0, -0.013, 0.038, 0.004), (0.017, 0, 0.004, 0.03), (-0.017, 0, 0.004, 0.03)):
                p.box((x + dx, y, z + dz), (w, 0.004, h), "head")
        else:
            p.torus((x, y, z), 0.018, 0.0024, "head", seg=(18, 5), rot=rx(90))
        p.box((sx * 0.086, 0.035, z + 0.005), (0.004, 0.10, 0.004), "head")
    p.box((0.0, head_surface_y(0.0, z) + 0.016, z + 0.006), (0.03, 0.004, 0.004), "head")
    return p


def coat(name, belted=False, collar_up=False):
    mats = ["mat_coat_beige", "mat_belt_brown"] if belted else ["mat_coat_beige"]
    p = Part(name, mats)
    p.loft(COAT, bone_by_height, seg=22, cap_top=True)
    for sx in (-1.0, 1.0):
        start = p.vert_count()
        pts = [(0.0, 0.0), (sx * 0.075, 0.0), (sx * 0.02, -0.22)]
        if sx > 0:
            pts = [pts[0], pts[2], pts[1]]
        p.polygon_slab(pts, 0.008, Matrix.Translation((sx * 0.02, 0, 1.43)), "chest")
        stick(p, start, lambda x, z: COAT_P.front_y(x, z), 0.0, 0.008, lift=0.001)
    if collar_up:
        p.tube((0, -0.008, 1.42), (0, -0.008, 1.535), 0.083, 0.078, "neck", seg=18, caps=False)
    else:
        p.torus((0.0, -0.008, 1.448), 0.08, 0.02, "chest", seg=(18, 6), scale=(1.0, 0.92, 1.0))
    for side in ("L", "R"):
        sleeve(p, side, 1.41, 0.905, 0.066, 0.056, cuff=0.03)
    if HQ_FACE:
        for sx in (-1.0, 1.0):
            start = p.vert_count()
            p.box((sx * 0.12, 0.0, 0.86), (0.13, 0.008, 0.048), "hips")
            stick(p, start, lambda x, z: COAT_P.front_y(x, z), 0.0, 0.008, lift=0.0015)
            surf_seam(p, COAT_P, [(sx * 90.0, 0.58), (sx * 90.0, 1.36)])
            side = "L" if sx < 0 else "R"
            tab = arm_point(side, 0.94) + Vector((sx * 0.056, -0.02, 0.0))
            p.box(tab, (0.006, 0.05, 0.022), f"forearm_{side}", 0, bevel=0.002)
        surf_seam(p, COAT_P, [(180.0, 0.56), (180.0, 1.38)])
        surf_seam(p, COAT_P, [(174.0, 0.55), (174.0, 0.74)], width=0.0035)                 # 뒤트임
    if belted:
        p.loft([(0.975, 0.191, 0.146, 0.0), (1.045, 0.191, 0.146, 0.0)], lambda z: "spine", 1, seg=22, cap_top=False)
        start = p.vert_count()
        p.box((0.0, 0.0, 1.01), (0.05, 0.01, 0.055), "spine", 1)
        stick(p, start, lambda x, z: COAT_P.front_y(x, z), 0.0, 0.01, lift=0.008)
    return p


def coat_buttons(name, count=4, gold=False):
    p = Part(name, ["mat_button_brown"])
    for i, z in enumerate((1.28, 1.17, 1.06, 0.95)):
        if count == 3 and i == 2:
            continue
        start = p.vert_count()
        p.tube((0.03, -0.002, z), (0.03, 0.002, z), 0.0135, 0.0135, "spine" if z < 1.22 else "chest", seg=12, smooth=False)
        stick(p, start, lambda x, zz: COAT_P.front_y(x, zz), 0.0, 0.004, lift=0.002)
    return p


def slacks(name, cuffed=False):
    p = Part(name, ["mat_slacks_black"])
    pelvis(p, SLACKS_PELVIS)
    trouser_legs(p, 0.10, 0.074, 0.06, 0.056)
    waistband(p, SLACKS_PELVIS, 0.895, 0.935)
    for side in ("L", "R"):
        leg_seam(p, side, 0.86, 0.10, (0.10, 0.074, 0.06, 0.056), 8.0, width=0.0032, thick=0.0022)
        leg_seam(p, side, 0.86, 0.10, (0.10, 0.074, 0.06, 0.056), 90.0)
    if cuffed:
        for side in ("L", "R"):
            p.tube(leg_point(side, 0.145), leg_point(side, 0.095), 0.064, 0.064, f"shin_{side}", seg=12)
    return p


def derby(name):
    p = Part(name, ["mat_shoe_black"])
    for side in ("L", "R"):
        low_shoe(p, side, toe_seam=True)
    return p


def chelsea(name):
    p = Part(name, ["mat_shoe_black", "mat_boot_elastic"])
    for side in ("L", "R"):
        low_shoe(p, side)
        sx = -1.0 if side == "L" else 1.0
        x = sx * 0.09
        p.tube((x, -0.015, 0.06), (x, -0.015, 0.18), 0.05, 0.047, f"foot_{side}", seg=12)
        for s2 in (-1.0, 1.0):
            p.box((x + s2 * 0.049, -0.012, 0.13), (0.006, 0.05, 0.075), f"foot_{side}", 1)
    return p


def tote(name):
    p = Part(name, ["mat_tote_brown"])
    p.box((0.29, 0.0, 0.62), (0.085, 0.30, 0.25), "hand_R", bevel=0.012, smooth=True)
    for sy in (-1.0, 1.0):
        p.tube((0.29, sy * 0.075, 0.74), (0.255, sy * 0.012, 0.81), 0.006, 0.006, "hand_R", seg=8)
    return p


def scarf(name, striped=False):
    mats = ["mat_scarf_burgundy", "mat_scarf_stripe"] if striped else ["mat_scarf_burgundy"]
    p = Part(name, mats)
    p.torus((0.0, 0.0, 1.462), 0.072, 0.03, "neck", seg=(18, 8), scale=(1.0, 0.96, 0.75))
    for k, (x, ztop, zbot) in enumerate(((-0.045, 1.43, 1.16), (-0.005, 1.43, 1.20))):
        start = p.vert_count()
        p.box((x, 0.0, (ztop + zbot) / 2), (0.07, 0.012, ztop - zbot), "chest")
        stick(p, start, lambda xx, z: COAT_P.front_y(xx, z), 0.0, 0.012, lift=0.004 + 0.006 * k)
        if striped:
            for j in range(3):
                zs = zbot + 0.03 + j * 0.035
                start = p.vert_count()
                p.box((x, 0.0, zs), (0.072, 0.014, 0.014), "chest", 1)
                stick(p, start, lambda xx, z: COAT_P.front_y(xx, z), 0.0, 0.014, lift=0.004 + 0.006 * k)
    return p


def build_b_coat():
    parts = [
        body_skin(),
        hair_b("HairSlick"),
        face("FaceNeutral"), face("FaceSmile", mouth_kind="smile"),
        glasses("GlassesSquare", "square"), glasses("GlassesRound", "round"),
        coat("CoatLong"), coat("CoatLongBelted", belted=True), coat("CoatCollarUp", collar_up=True),
        coat_buttons("ButtonsFour"), coat_buttons("ButtonsThree", count=3),
        slacks("SlacksStraight"), slacks("SlacksCuffed", cuffed=True),
        derby("ShoesDerby"), chelsea("ChelseaBoots"),
        tote("ToteRight"), tote("ToteRight").mirrored("ToteLeft"),
        scarf("ScarfPlain"), scarf("ScarfStriped", striped=True),
    ]
    rt = Part("Remnant_Tote", ["mat_tote_brown"])
    rt.box((0.0, 0.0, 0.043), (0.30, 0.25, 0.085), "_static", bevel=0.012, smooth=True)
    rt.torus((0.0, 0.17, 0.01), 0.07, 0.006, "_static", seg=(16, 4), scale=(1.0, 0.6, 0.5))
    rg = glasses("Remnant_Glasses", "square")
    transform_part(rg, Matrix.Translation((0, 0, 0.012)) @ Matrix.Rotation(math.radians(-90), 4, "X") @ Matrix.Translation((0, -0.12, -1.615)))
    scrap = Part("Remnant_CoatScrap", ["mat_coat_beige"])
    cloth_scrap(scrap, 0.2, 23)
    return parts, [rt, rg, scrap]


# ============================================================== 타입 C: 패딩 조끼 손님

VEST = [(0.84, 0.198, 0.148, 0.0), (0.95, 0.196, 0.146, 0.0), (1.08, 0.19, 0.142, 0.0), (1.20, 0.197, 0.145, 0.0),
        (1.31, 0.205, 0.142, 0.0), (1.38, 0.20, 0.13, -0.005), (1.43, 0.16, 0.108, -0.01), (1.455, 0.085, 0.07, -0.01)]
VEST_P = Profile(VEST)
INNER = [(0.84, 0.172, 0.123, 0.0), (1.05, 0.166, 0.119, 0.0), (1.20, 0.175, 0.123, 0.0), (1.32, 0.187, 0.121, 0.0),
         (1.39, 0.19, 0.113, -0.005), (1.435, 0.15, 0.092, -0.01), (1.46, 0.068, 0.053, -0.01)]
CARGO_PELVIS = [(0.80, 0.17, 0.12, 0.0), (0.93, 0.172, 0.121, 0.0)]


def beanie(name, pompom=False):
    p = Part(name, ["mat_beanie_rust"])
    c = HEAD_C + Vector((0.0, -0.004, 0.01))
    r = Vector((HEAD_R.x * 1.12, HEAD_R.y * 1.10, HEAD_R.z * 1.08))
    p.ellipsoid(c, r, "head", seg=(20, 12), keep=lambda q: q.z > 1.665)
    p.loft([(1.662, r.x * 0.985, r.y * 0.985, c.y), (1.70, r.x * 0.93, r.y * 0.93, c.y)], lambda z: "head", seg=20, cap_top=False)
    if pompom:
        p.ellipsoid((0.0, -0.01, 1.765), (0.066, 0.066, 0.06), "head", seg=(12, 8))
    return p


def hair_c(name, long=False):
    p = Part(name, ["mat_hair_chestnut"])
    front = 1.626 if long else 1.652

    def hairline(q):
        t = min(1.0, max(0.0, q.y / 0.06))
        return 1.58 + (front - 1.58) * t

    c, r = hair_cap(p, hairline, top=1.675)
    if HQ_FACE:
        # 비니 아래로 내려온 앞머리 다발
        el0 = math.degrees(math.asin(min(1.0, (1.671 - c.z) / r.z)))
        for k in range(11):
            az = -62.0 + 12.4 * k
            el1 = math.degrees(math.asin(max(-1.0, min(1.0, (front + 0.002 - c.z) / r.z))))
            hair_lock(p, c, r, [(az, el0), (az + 3.0 * ((k % 3) - 1), el1)], 0.016, None, 0,
                      lift=(0.002, 0.004, 0.0025), steps=6)
    return p


def inner_shirt(name, pushed=False):
    p = Part(name, ["mat_inner_white"])
    p.loft(INNER, bone_by_height, seg=20, cap_bottom=True)
    for side in ("L", "R"):
        if pushed:
            sleeve(p, side, 1.41, 1.03, 0.056, 0.05)
            p.torus(arm_point(side, 1.03), 0.05, 0.015, f"forearm_{side}", seg=(14, 6))
            p.torus(arm_point(side, 1.06), 0.052, 0.014, f"forearm_{side}", seg=(14, 6))
        else:
            sleeve(p, side, 1.41, 0.925, 0.056, 0.046, cuff=0.02)
    return p


def vest(name, open_front=False):
    p = Part(name, ["mat_vest_green", "mat_zip_dark"])

    def bulge(th, z):
        return 1.0 + 0.035 * math.cos(2 * math.pi * (z - 0.84) / 0.12)

    def skip(th, z):
        s = math.sin(th)
        if z > 1.18 and abs(s) > 0.86:
            return True
        if open_front and z > 0.84 and math.cos(th) > math.cos(math.radians(26)):
            return True
        return False

    rings = []
    for i in range(len(VEST) - 1):
        a, b = VEST[i], VEST[i + 1]
        for k in range(3):
            t = k / 3
            rings.append(tuple(a[j] + (b[j] - a[j]) * t for j in range(4)))
    rings.append(VEST[-1])
    p.loft(rings, bone_by_height, seg=24, cap_top=True, skip=skip, bulge=bulge)
    p.tube((0, -0.01, 1.43), (0, -0.01, 1.505), 0.088, 0.084, "neck", seg=18, caps=False)
    zip_x = (-0.093, 0.093) if open_front else (0.0,)
    for zx in zip_x:
        start = p.vert_count()
        p.box((zx, 0.0, 1.16), (0.009, 0.006, 0.60), "spine", 1)
        stick(p, start, lambda x, z: VEST_P.front_y(x, z) * 1.035, 0.0, 0.006, lift=0.003)
    return p


def vest_patch(name, shape):
    p = Part(name, ["mat_patch_light"])
    x, z = -0.085, 1.30
    if shape == "square":
        p.box((x, 0.0, z), (0.048, 0.004, 0.048), "chest")
    else:
        p.tube((x, -0.002, z), (x, 0.002, z), 0.027, 0.027, "chest", seg=20, smooth=False)
    stick(p, 0, lambda xx, zz: VEST_P.front_y(xx, zz) * 1.035, 0.0, 0.004, lift=0.004)
    return p


def cargo(name, pockets=("L", "R")):
    p = Part(name, ["mat_cargo", "mat_cargo_pocket"])
    pelvis(p, CARGO_PELVIS)
    trouser_legs(p, 0.15, 0.082, 0.066, 0.062)
    for side in pockets:
        sx = -1.0 if side == "L" else 1.0
        p.box((sx * 0.17, 0.0, 0.69), (0.034, 0.13, 0.16), f"thigh_{side}", 1, bevel=0.008, smooth=True)
        if HQ_FACE:
            p.box((sx * 0.189, 0.0, 0.757), (0.012, 0.142, 0.05), f"thigh_{side}", 1, bevel=0.004)   # 주머니 덮개
            p.box((sx * 0.196, 0.0, 0.742), (0.006, 0.014, 0.014), f"thigh_{side}", 1, bevel=0.002)  # 똑딱단추
    for side in ("L", "R"):
        leg_seam(p, side, 0.86, 0.15, (0.15, 0.082, 0.066, 0.062), 180.0)
    return p


def hightops(name, high=True):
    p = Part(name, ["mat_hightop_charcoal", "mat_lace_dark", "mat_sole_white"])
    for side in ("L", "R"):
        sneaker(p, side, mats=(0, 1, 0), stripes=False, high=high, sole_surface=2)
    return p


def backpack(name, straps=("L", "R")):
    p = Part(name, ["mat_backpack_gray"])
    shift = 0.0 if len(straps) == 2 else 0.05
    tilt = 0.0 if len(straps) == 2 else -10.0
    c = Vector((shift, -0.235, 1.17))
    p.box(c, (0.30, 0.13, 0.40), "chest", rot=ry(tilt), bevel=0.04, smooth=True)
    p.box(c + Vector((0.0, -0.075, -0.07)), (0.22, 0.04, 0.16), "chest", rot=ry(tilt), bevel=0.02, smooth=True)
    for side in straps:
        sx = -1.0 if side == "L" else 1.0
        th = sx * 32.0
        pts = [VEST_P.point(th, 1.14, 0.03), VEST_P.point(th * 0.9, 1.30, 0.032), VEST_P.point(sx * 72.0, 1.43, 0.03),
               VEST_P.point(sx * 150.0, 1.42, 0.03), Vector((shift + sx * 0.1, -0.175, 1.33))]
        p.ribbon(pts, 0.05, 0.008, lambda q: VEST_P.outward(q) if q.y > -0.15 else Vector((0, -1, 0.3)).normalized(), bone_by_height)
    return p


def earphones(name, sides=("L", "R")):
    p = Part(name, ["mat_earbud_black"])
    for side in sides:
        sx = -1.0 if side == "L" else 1.0
        p.ellipsoid((sx * 0.09, 0.012, 1.597), (0.011, 0.011, 0.011), "head", seg=(10, 6))
        pts = [Vector((sx * 0.092, 0.015, 1.585)), Vector((sx * 0.075, 0.06, 1.48)), VEST_P.point(sx * 25.0, 1.40, 0.035), VEST_P.point(sx * 8.0, 1.29, 0.032)]
        bones = ["head", "neck", "chest"]
        for i, (a, b) in enumerate(zip(pts, pts[1:])):
            p.tube(a, b, 0.0028, 0.0028, bones[i], seg=6)
    return p


def build_c_vest():
    parts = [
        body_skin(),
        beanie("BeanieFlat"), beanie("BeaniePompom", pompom=True),
        hair_c("FringeShort"), hair_c("FringeLong", long=True),
        face("FaceNeutral"), face("FaceSmile", mouth_kind="smile"), face("FaceNeutralMole", mole=True),
        inner_shirt("LongSleeveWhite"), inner_shirt("SleevesPushed", pushed=True),
        vest("VestPuffer"), vest("VestOpen", open_front=True),
        vest_patch("PatchSquare", "square"), vest_patch("PatchCircle", "circle"),
        cargo("CargoBoth"), cargo("CargoRightOnly", pockets=("R",)),
        hightops("HighTops"), hightops("LowTops", high=False),
        backpack("BackpackTwoStraps"), backpack("BackpackOneStrap", straps=("R",)),
        earphones("EarbudsBlack"), earphones("EarbudLeftOnly", sides=("L",)),
    ]
    rb = Part("Remnant_Backpack", ["mat_backpack_gray"])
    rb.box((0.0, 0.0, 0.07), (0.30, 0.40, 0.13), "_static", bevel=0.04, smooth=True)
    rbn = beanie("Remnant_Beanie")
    transform_part(rbn, Matrix.Translation((0, 0, 0.02)) @ Matrix.Rotation(math.radians(100), 4, "X") @ Matrix.Translation((0, 0, -1.69)))
    scrap = Part("Remnant_VestScrap", ["mat_vest_green"])
    cloth_scrap(scrap, 0.18, 37)
    return parts, [rb, rbn, scrap]


# ============================================================== 타입 D: 정장 손님 (예비, M2)

JACKET = [(0.76, 0.192, 0.142, 0.0), (0.88, 0.186, 0.136, 0.0), (1.02, 0.178, 0.13, 0.0), (1.20, 0.188, 0.132, 0.0),
          (1.33, 0.203, 0.13, 0.0), (1.395, 0.20, 0.118, -0.005), (1.44, 0.16, 0.10, -0.01), (1.47, 0.075, 0.06, -0.01)]
JACKET_P = Profile(JACKET)
SHIRT = [(1.0, 0.17, 0.122, 0.0), (1.20, 0.178, 0.125, 0.0), (1.33, 0.19, 0.122, 0.0), (1.395, 0.188, 0.11, -0.005),
         (1.44, 0.15, 0.092, -0.01), (1.47, 0.066, 0.052, -0.01)]
SHIRT_P = Profile(SHIRT)


def hair_d(name, gloss=False):
    p = Part(name, ["mat_hair_dark_gloss" if gloss else "mat_hair_dark", "mat_skin"])
    c, r = hair_cap(p, lambda q: 1.612 + 0.62 * q.y, scale=(1.055, 1.05, 1.04), shift=(0.0, -0.004, 0.004))
    if HQ_FACE:
        p.ellipsoid((-0.03, 0.068, 1.686), (0.042, 0.032, 0.016), "head", seg=(14, 8))
    else:
        p.ellipsoid((-0.03, 0.07, 1.692), (0.05, 0.04, 0.022), "head", seg=(14, 8))
    if HQ_FACE:
        side_part_locks(p, c, r, 0.036, lambda q: 1.612 + 0.62 * q.y)
    part_line(p, c, r, 0.036)
    return p


def jacket(name, open_to_hem=False):
    """닫힌 재킷 몸통 위에 셔츠가 보이는 V자(표면 1, 흰색)와 옷깃을 붙인다. 열린 변이는 V가 밑단까지 이어진다."""
    p = Part(name, ["mat_suit_navy", "mat_shirt_white"])
    p.loft(JACKET, bone_by_height, seg=26, cap_top=True, cap_bottom=True)
    bottom = 0.80 if open_to_hem else 1.12
    start = p.vert_count()
    if open_to_hem:
        pts = [(-0.085, 0.0), (0.085, 0.0), (0.03, -0.31), (0.03, -0.62), (-0.03, -0.62), (-0.03, -0.31)]
    else:
        pts = [(-0.085, 0.0), (0.085, 0.0), (0.0, -(1.44 - bottom))]
    p.polygon_slab(pts, 0.004, Matrix.Translation((0, 0, 1.44)), "chest", 1)
    stick(p, start, lambda x, z: JACKET_P.front_y(x, z), 0.0, 0.004, lift=0.001)
    for sx in (-1.0, 1.0):
        start = p.vert_count()
        pts = [(sx * 0.085, 0.0), (sx * 0.13, -0.05), (sx * 0.035, -(1.44 - max(bottom, 1.12)) - 0.01), (sx * 0.004, -(1.44 - max(bottom, 1.12)) + 0.02)]
        p.polygon_slab(pts, 0.008, Matrix.Translation((0, 0, 1.44)), "chest", 0)
        stick(p, start, lambda x, z: JACKET_P.front_y(x, z), 0.0, 0.008, lift=0.004)
    for side in ("L", "R"):
        sleeve(p, side, 1.41, 0.925, 0.062, 0.052)
    if HQ_FACE:
        start = p.vert_count()
        p.box((-0.10, 0.0, 1.29), (0.085, 0.006, 0.016), "chest")                          # 가슴 웰트 포켓(왼쪽)
        stick(p, start, lambda x, z: JACKET_P.front_y(x, z), 0.0, 0.006, lift=0.0015)
        for sx in (-1.0, 1.0):
            start = p.vert_count()
            p.box((sx * 0.115, 0.0, 0.92), (0.13, 0.007, 0.045), "hips")
            stick(p, start, lambda x, z: JACKET_P.front_y(x, z), 0.0, 0.007, lift=0.0015)
            surf_seam(p, JACKET_P, [(sx * 90.0, 0.78), (sx * 90.0, 1.36)])
            side = "L" if sx < 0 else "R"
            for k in range(3):
                q = arm_point(side, 0.955 + k * 0.022) + Vector((sx * 0.046, -0.026, 0.0))
                p.tube(q - Vector((sx * 0.003, 0, 0)), q + Vector((sx * 0.004, 0, 0)), 0.0065, 0.0065, f"forearm_{side}", seg=8)
        surf_seam(p, JACKET_P, [(180.0, 0.78), (180.0, 1.40)])
    if not open_to_hem:
        for z in (1.07, 0.97):
            start = p.vert_count()
            p.tube((0.0, -0.002, z), (0.0, 0.002, z), 0.011, 0.011, "spine", seg=10, smooth=False)
            stick(p, start, lambda x, zz: JACKET_P.front_y(x, zz), 0.0, 0.004, lift=0.002)
    return p


def shirt(name):
    p = Part(name, ["mat_shirt_white"])
    p.torus((0.0, 0.004, 1.476), 0.063, 0.015, "neck", seg=(18, 6), scale=(1.0, 0.95, 1.0))
    for side in ("L", "R"):
        p.tube(arm_point(side, 0.935), arm_point(side, 0.90), 0.05, 0.049, f"forearm_{side}", seg=12)
    return p


def tie(name, striped=False):
    mats = ["mat_tie_burgundy", "mat_tie_stripe"] if striped else ["mat_tie_burgundy"]
    p = Part(name, mats)
    p.box((0.0, JACKET_P.front_y(0.0, 1.445) + 0.008, 1.445), (0.03, 0.02, 0.026), "chest", bevel=0.004, smooth=True)
    start = p.vert_count()
    pts = [(-0.014, 0.0), (0.014, 0.0), (0.036, -0.27), (0.0, -0.30), (-0.036, -0.27)]
    p.polygon_slab(pts, 0.006, Matrix.Translation((0, 0, 1.432)), "chest")
    stick(p, start, lambda x, z: JACKET_P.front_y(x, z), 0.0, 0.006, lift=0.006)
    if striped:
        for j in range(4):
            z = 1.38 - j * 0.07
            start = p.vert_count()
            p.box((0.0, 0.0, z), (0.062, 0.006, 0.013), "chest", 1, rot=ry(32))
            stick(p, start, lambda x, zz: JACKET_P.front_y(x, zz), 0.0, 0.006, lift=0.0075)
    return p


def pocket_square(name):
    p = Part(name, ["mat_pocket_white"])
    pts = [(-0.035, 0.0), (0.035, 0.0), (0.012, 0.028), (0.0, 0.016), (-0.014, 0.03)]
    p.polygon_slab(pts, 0.006, Matrix.Translation((-0.105, 0, 1.262)), "chest")
    stick(p, 0, lambda x, z: JACKET_P.front_y(x, z), 0.0, 0.006, lift=0.003)
    return p


def lapel_pin(name):
    p = Part(name, ["mat_pin_gold"])
    p.tube((-0.078, -0.002, 1.355), (-0.078, 0.002, 1.355), 0.009, 0.009, "chest", seg=12, smooth=False)
    stick(p, 0, lambda x, z: JACKET_P.front_y(x, z), 0.0, 0.004, lift=0.012)
    return p


def suit_trousers(name, cuffed=False):
    p = Part(name, ["mat_suit_navy"])
    pelvis(p, SLACKS_PELVIS)
    trouser_legs(p, 0.10, 0.074, 0.06, 0.056)
    waistband(p, SLACKS_PELVIS, 0.895, 0.935)
    belt_loops(p, Profile(SLACKS_PELVIS), 0.915)
    for side in ("L", "R"):
        leg_seam(p, side, 0.86, 0.10, (0.10, 0.074, 0.06, 0.056), 8.0, width=0.0032, thick=0.0022)
        leg_seam(p, side, 0.86, 0.10, (0.10, 0.074, 0.06, 0.056), 90.0)
    if cuffed:
        for side in ("L", "R"):
            p.tube(leg_point(side, 0.145), leg_point(side, 0.095), 0.064, 0.064, f"shin_{side}", seg=12)
    return p


def oxfords(name):
    p = Part(name, ["mat_oxford_black"])
    for side in ("L", "R"):
        low_shoe(p, side, toe_seam=True, height=0.033)
    return p


def briefcase(name):
    p = Part(name, ["mat_briefcase"])
    p.box((-0.30, 0.0, 0.60), (0.09, 0.40, 0.29), "hand_L", bevel=0.01)
    p.torus((-0.27, 0.0, 0.77), 0.045, 0.008, "hand_L", seg=(14, 6), rot=ry(90) @ rz(90), scale=(1.0, 0.6, 1.0))
    return p


def build_d_suit():
    parts = [
        body_skin(),
        hair_d("HairSuitPart"),
        face("FaceNeutral"), face("FaceSmile", mouth_kind="smile"), face("FaceFrown", brows="frown"), face("FaceNeutralMole", mole=True),
        jacket("SuitJacket"), jacket("SuitJacketOpen", open_to_hem=True),
        shirt("ShirtWhite"),
        tie("TieBurgundy"), tie("TieStriped", striped=True),
        pocket_square("PocketSquare"),
        lapel_pin("PinLeft"), lapel_pin("PinLeft").mirrored("PinRight"),
        suit_trousers("SuitTrousers"), suit_trousers("SuitTrousersCuffed", cuffed=True),
        oxfords("Oxfords"),
        briefcase("BriefcaseLeft"), briefcase("BriefcaseLeft").mirrored("BriefcaseRight"),
    ]
    rb = Part("Remnant_Briefcase", ["mat_briefcase"])
    rb.box((0.0, 0.0, 0.046), (0.40, 0.29, 0.09), "_static", bevel=0.01)
    rt = Part("Remnant_Tie", ["mat_tie_burgundy"])
    rt.polygon_slab([(-0.014, 0.0), (0.014, 0.0), (0.038, -0.30), (0.0, -0.335), (-0.038, -0.30)], 0.007,
                    Matrix.Translation((0.0, 0.15, 0.006)) @ Matrix.Rotation(math.radians(-90), 4, "X"), "_static")
    scrap = Part("Remnant_JacketScrap", ["mat_suit_navy"])
    cloth_scrap(scrap, 0.17, 41)
    return parts, [rb, rt, scrap]


# ============================================================== 플레이어 (노란 바람막이, §4.2)

def build_player():
    parts = [body_skin(), hair_a("PlayerHair"), face("PlayerFace")]
    wb = Part("Windbreaker", ["mat_windbreaker", "mat_zip_dark"])
    rings = [(z, rx_ * 1.06, ry_ * 1.08, yo) for z, rx_, ry_, yo in HOODIE]
    wb.loft(rings, bone_by_height, seg=22, cap_bottom=True)
    wb.ellipsoid((0.0, -0.105, 1.45), (0.125, 0.072, 0.08), "chest", seg=(14, 8))
    wb.tube((0, -0.008, 1.43), (0, -0.008, 1.51), 0.09, 0.086, "neck", seg=18, caps=False)
    for side in ("L", "R"):
        sleeve(wb, side, 1.41, 0.92, 0.068, 0.056, cuff=0.03)
    prof = Profile(rings)
    start = wb.vert_count()
    wb.box((0.0, 0.0, 1.15), (0.012, 0.006, 0.58), "spine", 1)
    stick(wb, start, lambda x, z: prof.front_y(x, z), 0.0, 0.006, lift=0.002)
    pants = Part("PlayerPants", ["mat_player_pants"])
    pelvis(pants, JEANS_PELVIS)
    trouser_legs(pants, 0.12, 0.078, 0.062, 0.058)
    shoes = Part("PlayerShoes", ["mat_player_shoe", "mat_lace_white", "mat_stripe_gray"])
    for side in ("L", "R"):
        sneaker(shoes, side)
    parts += [wb, pants, shoes]
    return parts, []


TYPES = {
    "a_hoodie": build_a_hoodie,
    "b_coat": build_b_coat,
    "c_vest": build_c_vest,
    "d_suit": build_d_suit,
}
