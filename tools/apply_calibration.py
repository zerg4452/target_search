"""시각 보정 결과(test_reports/visual/calibration.json)로 변이 등급·식별 거리·보이는 방향을 다시 매긴다(§6.3, §14.3, R-01).

등급 규칙(§6.3, V-01과 같은 카메라·기준):
  기본 카메라(FOV 65°, 300 px)로 10 m 이상 → 1, 7 m 이상 → 2
  그 밖에 관찰 카메라(FOV 30°, 100 px)로 5 m 이상 → 3, 4 m 이상 → 4, 2.5 m 이상 → 5
  관찰 카메라로 2.5 m에서도 통과 못 하면 '부적합'으로 보고하고 바꾸지 않는다.
방향별로 등급을 매긴 뒤 가장 좋은 방향의 등급을 변이 등급으로 쓴다. 식별 거리는 그 등급의 방향들이 모두 통과하는
가장 먼 거리이며, 그 등급 범위의 상한을 넘지 않게 한다.
보이는 방향은 그 등급의 카메라로 식별 거리에서 통과하는 방향만 남긴다(앞·뒤·왼쪽·오른쪽 모두면 any).

사용: py -3 tools/apply_calibration.py [--dry-run]
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAL = ROOT / "test_reports" / "visual" / "calibration.json"
CAPS = {1: 14.0, 2: 9.5, 3: 7.0, 4: 4.5, 5: 3.5}


def grade_of(d_def, d_obs):
    if d_def >= 10.0:
        return 1, min(d_def, CAPS[1])
    if d_def >= 7.0:
        return 2, min(d_def, CAPS[2])
    if d_obs >= 5.0:
        return 3, min(d_obs, CAPS[3])
    if d_obs >= 4.0:
        return 4, min(d_obs, CAPS[4])
    if d_obs >= 2.5:
        return 5, min(d_obs, CAPS[5])
    return None, 0.0


def main():
    dry = "--dry-run" in sys.argv
    cal = json.loads(CAL.read_text(encoding="utf-8"))["results"]
    changes = []
    unfit = []
    for vfile in sorted((ROOT / "data" / "outfits" / "mall_guest").glob("*/variants.json")):
        data = json.loads(vfile.read_text(encoding="utf-8"))
        for v in data["variants"]:
            res = cal.get(v["id"])
            if not res:
                continue
            per = {}
            for view, r in res.items():
                g, dist = grade_of(r["default"], r["observe"])
                if g is not None:
                    per[view] = (g, dist)
            if not per:
                unfit.append(v["id"])
                continue
            g = min(p[0] for p in per.values())
            # 그 등급의 방향들이 모두 통과하는 가장 먼 거리(그 등급 범위 안).
            dist = min(p[1] for p in per.values() if p[0] == g)
            cam = "default" if g <= 2 else "observe"
            views = [view for view, r in res.items() if r[cam] >= dist - 1e-6]
            horiz = [x for x in ("front", "back", "left", "right") if x in views]
            vis = ["any"] if len(horiz) == 4 else horiz + (["top"] if "top" in views else [])
            old = (v["difficulty"], v["identify_distance_m"], list(v["visible_from"]))
            new = (g, round(dist, 1), vis)
            if old != new:
                changes.append((v["id"], old, new))
            v["difficulty"], v["identify_distance_m"], v["visible_from"] = new
            v["calibrated"] = "V-01"
        if not dry:
            vfile.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for vid, old, new in changes:
        print(f"{vid}: 등급 {old[0]}→{new[0]}, {old[1]}→{new[1]} m, {'/'.join(old[2])} → {'/'.join(new[2])}")
    print(f"바뀐 변이 {len(changes)}개" + (" (dry-run)" if dry else ""))
    if unfit:
        print("부적합(관찰 카메라 2.5 m에서도 기준 미달):", ", ".join(unfit))


main()
