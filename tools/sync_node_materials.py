"""외형 데이터의 노드 재질 목록을 Blender 생성기의 노드 목록(manifest)에 맞춘다(D-35).

생성기가 노드에 재질 면을 덧붙이면(예: 청바지의 금색 스티치), appearance.json의 슬롯과 variants.json의
swap_mesh 연산이 가진 materials 목록이 짧아진다. 목록이 manifest 표면 목록의 앞부분과 같을 때만
뒷부분을 덧붙인다. 앞부분이 다르면(변이가 일부러 다른 재질을 쓰는 경우 등) 바꾸지 않고 보고한다.
swap_material 연산은 면 번호로 가리키므로 뒤에 면을 덧붙여도 영향이 없다.

사용: py -3 tools/sync_node_materials.py [--dry-run]
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sync_list(tag, node, mats, surfaces, changes, problems):
    if mats == surfaces:
        return mats
    if len(mats) < len(surfaces) and surfaces[:len(mats)] == mats:
        changes.append(f"{tag}: {node} {mats} → {surfaces}")
        return list(surfaces)
    problems.append(f"{tag}: {node} 재질 {mats}가 노드 표면 {surfaces}와 맞지 않음(손대지 않음)")
    return mats


def main():
    dry = "--dry-run" in sys.argv
    changes, problems = [], []
    for outfit_dir in sorted((ROOT / "data" / "outfits").iterdir()):
        if not outfit_dir.is_dir():
            continue
        outfit = json.loads((outfit_dir / "outfit.json").read_text(encoding="utf-8"))
        asset_dir = ROOT / outfit["asset_dir"].replace("res://", "")
        for type_dir in sorted(p for p in outfit_dir.iterdir() if p.is_dir()):
            man = json.loads((asset_dir / f"{type_dir.name}.manifest.json").read_text(encoding="utf-8"))
            nodes = man["nodes"]
            app_path = type_dir / "appearance.json"
            app = json.loads(app_path.read_text(encoding="utf-8"))
            for slot, d in app["slots"].items():
                node = d.get("node", "NONE")
                if node in nodes:
                    d["materials"] = sync_list(f"{type_dir.name}/{slot}", node, d.get("materials", []), nodes[node]["surfaces"], changes, problems)
            var_path = type_dir / "variants.json"
            var = json.loads(var_path.read_text(encoding="utf-8"))
            for v in var.get("variants", []):
                op = v.get("op", {})
                if op.get("type") == "swap_mesh" and op.get("node") in nodes:
                    op["materials"] = sync_list(f"{type_dir.name}/{v['id']}", op["node"], op.get("materials", []), nodes[op["node"]]["surfaces"], changes, problems)
            if not dry:
                for path, data in ((app_path, app), (var_path, var)):
                    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    for c in changes:
        print(c)
    for pr in problems:
        print("확인 필요:", pr)
    print(f"덧붙인 목록 {len(changes)}개, 확인 필요 {len(problems)}개" + (" (dry-run)" if dry else ""))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
