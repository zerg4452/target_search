"""GAME_DESIGN.md의 자동 생성 구역을 data/*.json에서 다시 만든다. 데이터가 기준이고 문서는 그 사본이다.
  <!-- gen:catalog --> ... <!-- /gen:catalog -->   §6.5 변이 카탈로그(4타입)
  <!-- gen:appendix-b --> ... <!-- /gen:appendix-b -->   부록 B 예시 데이터(실제 파일 발췌)
사용: py -3 tools/sync_design_doc.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "GAME_DESIGN.md"
GROUP = {"hair": "머리", "face": "얼굴", "top": "상의", "lower": "하의·신발", "carry": "소지품"}
KIND = {"material": "재질", "shape": "형태", "print": "무늬·글자", "color": "명도", "mirror": "반전", "expression": "표정", "add_remove": "추가·제거"}
DIR = {"front": "앞", "back": "뒤", "left": "왼쪽", "right": "오른쪽", "top": "위", "any": "전방위"}
TYPES = [("a_hoodie", "A 후드 손님"), ("b_coat", "B 코트 손님"), ("c_vest", "C 패딩 조끼 손님"), ("d_suit", "D 정장 손님 (예비)")]


def load(rel):
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))


def catalog():
    out = []
    for tid, title in TYPES:
        vs = load(f"data/outfits/mall_guest/{tid}/variants.json")["variants"]
        out.append(f"**{title}** — `data/outfits/mall_guest/{tid}/variants.json`, {len(vs)}종\n")
        out.append("| ID | 변이 | 그룹 | 유형 | 등급 | 보이는 방향 | 식별 거리 | 단계 |")
        out.append("|---|---|---|---|---:|---|---:|---|")
        for v in vs:
            dirs = "·".join(DIR.get(d, d) for d in v["visible_from"])
            out.append(f"| {v['id']} | {v['name_ko']} | {GROUP[v['group']]} | {KIND[v['kind']]} | {v['difficulty']} | {dirs} | {v['identify_distance_m']:.1f} m | {v['milestone']} |")
        grades = {}
        for v in vs:
            grades[v["difficulty"]] = grades.get(v["difficulty"], 0) + 1
        out.append("")
        out.append("등급 분포: " + ", ".join(f"등급 {g} {grades[g]}개" for g in sorted(grades)) + "\n")
    return "\n".join(out)


def appendix_b():
    parts = []
    a_app = load("data/outfits/mall_guest/a_hoodie/appearance.json")
    a_var = load("data/outfits/mall_guest/a_hoodie/variants.json")
    excerpt = {"version": a_var["version"], "variants": a_var["variants"][:3]}
    for title, rel, data in [
        ("B.1", "data/outfits/mall_guest/a_hoodie/appearance.json", a_app),
        ("B.2", "data/outfits/mall_guest/a_hoodie/variants.json (앞의 3개)", excerpt),
        ("B.3", "data/difficulty_presets.json", load("data/difficulty_presets.json")),
        ("B.4", "data/npc_tuning.json", load("data/npc_tuning.json")),
        ("B.5", "data/hunt_tuning.json", load("data/hunt_tuning.json")),
        ("B.6", "data/player_tuning.json", load("data/player_tuning.json")),
        ("B.7", "data/visibility_tuning.json", load("data/visibility_tuning.json")),
        ("B.8", "data/scoring.json", load("data/scoring.json")),
    ]:
        parts.append(f"### {title} `{rel}`\n\n```json\n{json.dumps(data, ensure_ascii=False, indent=2)}\n```\n")
    m = load("data/maps/atrium.json")
    m_ex = dict(m)
    m_ex["layout"] = dict(m["layout"])
    m_ex["layout"]["obstacles"] = m["layout"]["obstacles"][:3] + ["… (모두 %d개)" % len(m["layout"]["obstacles"])]
    parts.append(f"### B.9 `data/maps/atrium.json` (장애물 일부)\n\n```json\n{json.dumps(m_ex, ensure_ascii=False, indent=2)}\n```\n")
    return "\n".join(parts)


def replace(doc, tag, body):
    pat = re.compile(rf"<!-- gen:{tag} -->.*?<!-- /gen:{tag} -->", re.S)
    if not pat.search(doc):
        raise SystemExit(f"표시 <!-- gen:{tag} --> 가 문서에 없음")
    return pat.sub(lambda m: f"<!-- gen:{tag} -->\n" + body.rstrip("\n") + f"\n<!-- /gen:{tag} -->", doc)


doc = DOC.read_text(encoding="utf-8")
doc = replace(doc, "catalog", catalog())
doc = replace(doc, "appendix-b", appendix_b())
DOC.write_text(doc, encoding="utf-8")
print("GAME_DESIGN.md 자동 생성 구역 갱신")
