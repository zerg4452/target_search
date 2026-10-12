"""외형 타입 하나(또는 플레이어)를 만들어 glb·blend·노드 목록(manifest)으로 내보낸다(§12.5).

사용(저장소 루트에서):
  blender --background --factory-startup --python tools/blender/build_npc_type.py -- --outfit mall_guest --type a_hoodie
  blender --background --factory-startup --python tools/blender/build_npc_type.py -- --player
  blender --background --factory-startup --python tools/blender/build_npc_type.py -- --all
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))

import bpy  # noqa: E402

import mall_guest  # noqa: E402
import npc_common as nc  # noqa: E402

OUTFITS = {"mall_guest": mall_guest}
SEG_SCALE = 1.4   # 원통형 조각의 둘레 분할 배율(D-33). 삼각형 예산은 §12.2
CLOTH_DETAILS = {"knit", "twill", "wool", "suiting", "cotton", "nylon"}   # 옷 주름을 넣을 재질(D-35)


AO_DISTANCE_M = 0.12   # 미리 굽는 주변광 차폐의 거리(D-35)
AO_SAMPLES = 48
AO_FLOOR = 0.45        # 가장 가려진 곳의 밝기 배율(0~1). 너무 어두우면 변이 가시성을 해친다


def bake_contexts(outfit_id, type_id, objs, player):
    """노드마다 주변광 차폐를 구울 때 함께 보일 노드 집합. 기준 인물의 노드에 그 노드를 넣고,
    같은 슬롯의 기준 노드는 뺀다(변이 노드는 자기가 들어갈 자리에서 굽는다).
    같은 노드는 누가 입어도 같은 값이라 일반 NPC끼리 차이가 생기지 않는다(V-02)."""
    if player:
        every = set(objs)
        return {n: every for n in objs}
    base_dir = os.path.join(ROOT, "data", "outfits", outfit_id, type_id)
    slots = nc.read_json(os.path.join(base_dir, "appearance.json"))["slots"]
    base = {sl: d["node"] for sl, d in slots.items() if d.get("node", "NONE") != "NONE" and d.get("visible", True)}
    slot_of = {node: sl for sl, node in base.items()}
    for v in nc.read_json(os.path.join(base_dir, "variants.json")).get("variants", []):
        op = v.get("op", {})
        if op.get("type") == "swap_mesh" and op.get("node", "NONE") != "NONE":
            slot_of.setdefault(op["node"], op["slot"])
    base_set = set(base.values())
    out = {}
    for n in objs:
        sl = slot_of.get(n)
        ctx = set(base_set)
        if sl is not None and base.get(sl) and base[sl] != n:
            ctx.discard(base[sl])
        ctx.add(n)
        out[n] = ctx
    return out


def bake_ao(objs, contexts):
    """Cycles로 노드마다 주변광 차폐를 꼭짓점 색(AO)에 굽는다. 게임은 이 색을 알베도에 곱한다(모든 NPC 재질 공통)."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = AO_SAMPLES
    if scene.world is None:
        scene.world = bpy.data.worlds.new("BakeWorld")
    scene.world.light_settings.distance = AO_DISTANCE_M
    meshes = [o for o in scene.objects if o.type == "MESH"]
    for name, ob in objs.items():
        ctx = contexts[name]
        for o in meshes:
            o.hide_render = o.name not in ctx
        me = ob.data
        attr = me.color_attributes.new("AO", "FLOAT_COLOR", "POINT")
        me.color_attributes.active_color = attr
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
        for d in attr.data:
            v = d.color[0]
            m = AO_FLOOR + (1.0 - AO_FLOOR) * v
            d.color = (m, m, m, 1.0)
    for o in meshes:
        o.hide_render = False


def build(outfit_id, type_id, player=False):
    nc.reset_scene()
    nc.SEG_SCALE = SEG_SCALE
    nc.LENGTH_STEP = 0.03
    nc.RING_STEP = 0.03
    nc.HEAD_SCULPT = True
    nc.SHOULDER_YOKE = True
    mall_guest.HQ_FACE = True
    outfit = nc.read_json(os.path.join(ROOT, "data", "outfits", outfit_id, "outfit.json"))
    palette = dict(outfit["palette"])
    mod = OUTFITS[outfit_id]
    if player:
        palette.update(nc.read_json(os.path.join(ROOT, "data", "player_tuning.json"))["palette"])
    nc.CLOTH_MATERIALS = {k for k, v in palette.items() if v.get("detail") in CLOTH_DETAILS}
    mats = nc.make_materials(palette)
    arm = nc.build_armature()
    anims = nc.build_animations(arm, player=player)
    parts, remnants = mod.build_player() if player else mod.TYPES[type_id]()
    col = bpy.context.scene.collection
    nodes = {}
    objs = {}
    for p in parts:
        if p.name in nodes:
            raise RuntimeError(f"노드 이름 중복: {p.name}")
        surfaces = list(p.materials)
        bones = list(p.bone_names)
        ob, tris = p.build(arm, mats, col)
        objs[p.name] = ob
        nodes[p.name] = {"surfaces": surfaces, "tris": tris, "bones": bones}
    rem = {}
    for p in remnants:
        surfaces = list(p.materials)
        _, tris = p.build(None, mats, col)
        rem[p.name] = {"surfaces": surfaces, "tris": tris}
    if player:
        glb = os.path.join(ROOT, "assets", "player", "player.glb")
        blend = os.path.join(ROOT, "art_source", "player.blend")
        manifest = os.path.join(ROOT, "assets", "player", "player.manifest.json")
    else:
        glb = os.path.join(ROOT, "assets", "npc", outfit_id, f"{type_id}.glb")
        blend = os.path.join(ROOT, "art_source", outfit_id, f"{type_id}.blend")
        manifest = os.path.join(ROOT, "assets", "npc", outfit_id, f"{type_id}.manifest.json")
    rem_objs = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith("Remnant_")]
    for o in rem_objs:
        o.hide_render = True
    bake_ao(objs, bake_contexts(outfit_id, type_id, objs, player))
    for o in rem_objs:
        o.hide_render = False
    nc.export_glb(glb, vertex_color="AO")
    nc.save_blend(blend)
    nc.write_json(manifest, {
        "version": 1,
        "generator": "tools/blender/build_npc_type.py",
        "outfit": outfit_id,
        "type": "player" if player else type_id,
        "skeleton": "NpcSkeleton",
        "bones": list(nc.BONES.keys()),
        "animations": anims,
        "nodes": nodes,
        "remnants": rem,
    })
    total = sum(n["tris"] for n in nodes.values())
    print(f"BUILT {outfit_id}/{'player' if player else type_id}: nodes {len(nodes)}, remnants {len(rem)}, tris(all nodes) {total} -> {glb}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--outfit", default="mall_guest")
    ap.add_argument("--type", default="")
    ap.add_argument("--player", action="store_true")
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args(argv)
    if a.all:
        for tid in OUTFITS[a.outfit].TYPES:
            build(a.outfit, tid)
        build(a.outfit, "", player=True)
    elif a.player:
        build(a.outfit, "", player=True)
    else:
        build(a.outfit, a.type)


main()
