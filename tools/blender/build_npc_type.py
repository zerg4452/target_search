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


def build(outfit_id, type_id, player=False):
    nc.reset_scene()
    outfit = nc.read_json(os.path.join(ROOT, "data", "outfits", outfit_id, "outfit.json"))
    palette = dict(outfit["palette"])
    mod = OUTFITS[outfit_id]
    if player:
        palette.update(mod.PLAYER_PALETTE)
    mats = nc.make_materials(palette)
    arm = nc.build_armature()
    anims = nc.build_animations(arm, player=player)
    parts, remnants = mod.build_player() if player else mod.TYPES[type_id]()
    col = bpy.context.scene.collection
    nodes = {}
    for p in parts:
        if p.name in nodes:
            raise RuntimeError(f"노드 이름 중복: {p.name}")
        surfaces = list(p.materials)
        bones = list(p.bone_names)
        _, tris = p.build(arm, mats, col)
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
    nc.export_glb(glb)
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
