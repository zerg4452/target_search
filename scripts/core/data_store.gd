class_name DataStore
extends RefCounted
## data/*.json 정의 데이터를 읽고 검사한다(§13.6, I-11). 읽은 뒤에는 바꾸지 않는다.
## 외형 타입의 노드·표면 목록은 Blender 생성기가 만든 manifest(assets/npc/<세트>/<타입>.manifest.json)로 검사한다.

const DATA_ROOT: String = "res://data"
const GROUPS: Array[String] = ["hair", "face", "top", "lower", "carry"]
const KINDS: Array[String] = ["material", "shape", "print", "color", "mirror", "expression", "add_remove"]
const DIRECTIONS: Array[String] = ["front", "back", "left", "right", "top", "any"]
const OPS: Array[String] = ["swap_mesh", "swap_material", "set_blend_shape", "hide"]
const MILESTONES: Array[String] = ["M0", "M1", "M2", "M3"]
const MIN_DELTA_L: float = 15.0
const BRIEFING_AND_DROP_S: float = 11.0

var difficulty: Dictionary = {}
var npc: Dictionary = {}
var hunt: Dictionary = {}
var player: Dictionary = {}
var visibility: Dictionary = {}
var scoring: Dictionary = {}
var maps: Dictionary = {}       ## map_id -> Dictionary
var outfits: Dictionary = {}    ## outfit_id -> Dictionary (outfit.json)
var types: Dictionary = {}      ## outfit_id -> { type_id -> { "appearance": Dictionary, "variants": Array } }
var manifests: Dictionary = {}  ## outfit_id -> { type_id -> manifest(노드·표면·잔해 목록) }
var load_errors: PackedStringArray = []


static func load_default() -> DataStore:
	var s: DataStore = DataStore.new()
	s.load_from(DATA_ROOT)
	return s


func load_from(root: String) -> void:
	difficulty = _read(root + "/difficulty_presets.json")
	npc = _read(root + "/npc_tuning.json")
	hunt = _read(root + "/hunt_tuning.json")
	player = _read(root + "/player_tuning.json")
	visibility = _read(root + "/visibility_tuning.json")
	scoring = _read(root + "/scoring.json")
	for f: String in DirAccess.get_files_at(root + "/maps"):
		if f.ends_with(".json"):
			var m: Dictionary = _read("%s/maps/%s" % [root, f])
			if m.has("id"):
				maps[String(m["id"])] = m
	for outfit_id: String in DirAccess.get_directories_at(root + "/outfits"):
		var base: String = "%s/outfits/%s" % [root, outfit_id]
		outfits[outfit_id] = _read(base + "/outfit.json")
		var asset_dir: String = String((outfits[outfit_id] as Dictionary).get("asset_dir", ""))
		var by_type: Dictionary = {}
		var by_type_man: Dictionary = {}
		for type_id: String in DirAccess.get_directories_at(base):
			var app: Dictionary = _read("%s/%s/appearance.json" % [base, type_id])
			var var_file: Dictionary = _read("%s/%s/variants.json" % [base, type_id])
			by_type[type_id] = {"appearance": app, "variants": var_file.get("variants", [])}
			if asset_dir != "":
				by_type_man[type_id] = _read("%s/%s.manifest.json" % [asset_dir, type_id])
		types[outfit_id] = by_type
		manifests[outfit_id] = by_type_man


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		load_errors.append("파일 없음: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		load_errors.append("JSON 파싱 실패: %s" % path)
		return {}
	return parsed


func preset(preset_id: String) -> Dictionary:
	for p: Dictionary in difficulty.get("presets", []):
		if String(p["id"]) == preset_id:
			return p
	return {}


func type_data(outfit_id: String, type_id: String) -> Dictionary:
	return types.get(outfit_id, {}).get(type_id, {})


## 외형 타입의 glb 경로(§6.8: assets/npc/<세트 ID>/<타입 ID>.glb).
func type_scene(outfit_id: String, type_id: String) -> String:
	return "%s/%s.glb" % [String(outfits[outfit_id].get("asset_dir", "")), type_id]


func find_variant(outfit_id: String, variant_id: String) -> Dictionary:
	## 반환: {"type": type_id, "variant": Dictionary} 또는 빈 사전.
	for type_id: String in types.get(outfit_id, {}):
		for v: Dictionary in types[outfit_id][type_id]["variants"]:
			if String(v["id"]) == variant_id:
				return {"type": type_id, "variant": v}
	return {}


## 이번 단계(milestone)까지 구현된 변이 중 등급 범위 [lo, hi]에 드는 것(§6.7 1번).
func variants_in_range(outfit_id: String, type_id: String, lo: int, hi: int) -> Array:
	var out: Array = []
	for v: Dictionary in type_data(outfit_id, type_id).get("variants", []):
		var d: int = int(v["difficulty"])
		if d >= lo and d <= hi and milestone_ok(String(v.get("milestone", "M0"))):
			out.append(v)
	return out


func milestone_ok(ms: String) -> bool:
	return MILESTONES.find(ms) <= MILESTONES.find(String(difficulty.get("milestone", "M0")))


## 판 길이 상한 검사용(§3.2). 일반 NPC가 모두 제거될 때까지의 이론상 최단 시간(브리핑 포함).
static func theoretical_wipe_s(p: Dictionary) -> float:
	var ki: Dictionary = p["kill_interval"]
	var total: float = BRIEFING_AND_DROP_S + float(p["search_time_s"]) + float(p["first_kill_delay_s"])
	var normals: int = int(p["npc_count"]) - 1
	for k: int in range(1, normals):
		total += maxf(float(ki["min_s"]), float(ki["start_s"]) - float(ki["step_s"]) * k)
	return total


## CIELAB 명도 L*(0~100). sRGB 색을 선형으로 바꾼 뒤 상대 휘도로 계산한다(§6.6 규칙 1).
static func lightness(c: Array) -> float:
	var lin: Array[float] = []
	for i: int in 3:
		var v: float = float(c[i])
		lin.append(v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	var y: float = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
	var f: float = pow(y, 1.0 / 3.0) if y > 0.008856 else 7.787 * y + 16.0 / 116.0
	return 116.0 * f - 16.0


## 모든 검사 오류를 모아 돌려준다. 비어 있으면 통과.
func validate() -> PackedStringArray:
	var errs: PackedStringArray = load_errors.duplicate()
	_validate_presets(errs)
	for map_id: String in maps:
		_validate_map(maps[map_id], errs)
	for outfit_id: String in types:
		_validate_outfit(outfit_id, errs)
	return errs


func _validate_presets(errs: PackedStringArray) -> void:
	var max_s: float = float(difficulty.get("max_match_s", 0))
	if max_s <= 0.0:
		errs.append("difficulty: max_match_s 없음")
	for key: String in ["wrong_accusation", "hints", "milestone", "recent_variant_exclusion"]:
		if not difficulty.has(key):
			errs.append("difficulty: %s 없음" % key)
	if not MILESTONES.has(String(difficulty.get("milestone", ""))):
		errs.append("difficulty: milestone 값 오류")
	var edges: Array = difficulty.get("hints", {}).get("distance_band_edges_m", [])
	for i: int in range(1, edges.size()):
		if float(edges[i]) <= float(edges[i - 1]):
			errs.append("hints: 거리 구간 경계는 오름차순이어야 함")
	var presets: Array = difficulty.get("presets", [])
	if presets.is_empty():
		errs.append("difficulty: presets 없음")
	for p: Dictionary in presets:
		var pid: String = String(p.get("id", "?"))
		for key: String in ["npc_count", "types_per_match", "min_per_type", "variant_difficulty", "search_time_s", "first_kill_delay_s", "kill_interval", "accusations", "reference_viewer"]:
			if not p.has(key):
				errs.append("preset %s: %s 없음" % [pid, key])
				return
		if int(p["types_per_match"]) * int(p["min_per_type"]) > int(p["npc_count"]):
			errs.append("preset %s: 타입 수 × 최소 인원이 NPC 수보다 많음" % pid)
		if int(p["accusations"]) < 1:
			errs.append("preset %s: 지목 기회는 1 이상" % pid)
		var cs: Dictionary = p.get("crowd_speedup", {})
		if bool(cs.get("enabled", false)):
			var ratio: float = float(cs.get("start_ratio", -1.0))
			if ratio <= 0.0 or ratio > 1.0:
				errs.append("preset %s: crowd_speedup.start_ratio는 0~1" % pid)
			if float(cs.get("per_step", -1.0)) <= 0.0 or float(cs.get("max_mult", 0.0)) < 1.0:
				errs.append("preset %s: crowd_speedup.per_step > 0, max_mult ≥ 1이어야 함" % pid)
		if not ["always", "briefing_only"].has(String(p["reference_viewer"])):
			errs.append("preset %s: reference_viewer 값 오류" % pid)
		var wipe: float = theoretical_wipe_s(p)
		if max_s > 0.0 and wipe > max_s:
			errs.append("preset %s: 이론상 최단 패배 %.1f초가 상한 %.0f초를 넘음" % [pid, wipe, max_s])


func _validate_map(m: Dictionary, errs: PackedStringArray) -> void:
	var mid: String = String(m.get("id", "?"))
	var outfit_id: String = String(m.get("outfit", ""))
	if not types.has(outfit_id):
		errs.append("map %s: 외형 세트 %s 없음" % [mid, outfit_id])
		return
	var map_types: Array = m.get("types", [])
	for t: Dictionary in map_types:
		var tid: String = String(t["id"])
		if not types[outfit_id].has(tid):
			errs.append("map %s: 타입 %s 없음" % [mid, tid])
			continue
		## 표준 난이도에서는 어느 타입이 타겟이 될지 모르므로 프리셋마다 쓸 수 있는 변이가 있어야 한다(§6.5).
		for p: Dictionary in difficulty.get("presets", []):
			var r: Array = p.get("variant_difficulty", [1, 5])
			if variants_in_range(outfit_id, tid, int(r[0]), int(r[1])).is_empty():
				errs.append("map %s: 타입 %s에 %s 난이도(등급 %d~%d) 변이가 없음" % [mid, tid, p["id"], int(r[0]), int(r[1])])
	for p2: Dictionary in difficulty.get("presets", []):
		if int(p2.get("types_per_match", 0)) > map_types.size():
			errs.append("map %s: %s 난이도는 타입 %d개가 필요하지만 맵에는 %d개" % [mid, p2["id"], int(p2["types_per_match"]), map_types.size()])
	if not m.has("layout"):
		errs.append("map %s: layout 없음" % mid)


func _validate_outfit(outfit_id: String, errs: PackedStringArray) -> void:
	var outfit: Dictionary = outfits.get(outfit_id, {})
	var palette: Dictionary = outfit.get("palette", {})
	for mid: String in palette:
		var pd: Variant = palette[mid]
		if typeof(pd) != TYPE_DICTIONARY or not (pd as Dictionary).has("color"):
			errs.append("%s: 팔레트 %s 형식 오류" % [outfit_id, mid])
	var seen_ids: Dictionary = {}
	var by_type: Dictionary = types[outfit_id]
	for type_id: String in by_type:
		var tag: String = "%s/%s" % [outfit_id, type_id]
		var man: Dictionary = manifests.get(outfit_id, {}).get(type_id, {})
		var nodes: Dictionary = man.get("nodes", {})
		if nodes.is_empty():
			errs.append("%s: 노드 목록(manifest) 없음 — tools/blender/build_npc_type.py로 만든다" % tag)
			continue
		var app: Dictionary = by_type[type_id]["appearance"]
		var slots: Dictionary = app.get("slots", {})
		if slots.is_empty():
			errs.append("%s: slots 없음" % tag)
			continue
		for slot: String in slots:
			_check_node_mats(tag + " 슬롯 " + slot, String(slots[slot].get("node", "")), slots[slot].get("materials", []), nodes, palette, errs)
		var rem_nodes: Dictionary = man.get("remnants", {})
		for r: Dictionary in app.get("trace", {}).get("remnants", []):
			_check_node_mats(tag + " 잔해", String(r.get("node", "")), r.get("materials", []), rem_nodes, palette, errs)
		for v: Dictionary in by_type[type_id]["variants"]:
			_validate_variant(outfit_id, type_id, v, slots, nodes, palette, seen_ids, errs)


## 노드가 목록에 있고 표면 수와 머티리얼 수가 같으며 머티리얼이 팔레트에 있는지.
func _check_node_mats(tag: String, node: String, mats: Array, nodes: Dictionary, palette: Dictionary, errs: PackedStringArray) -> void:
	if node == "NONE":
		if not mats.is_empty():
			errs.append("%s: NONE 노드에는 머티리얼이 없어야 함" % tag)
		return
	if not nodes.has(node):
		errs.append("%s: 노드 %s 없음" % [tag, node])
		return
	var surfaces: Array = nodes[node].get("surfaces", [])
	if surfaces.size() != mats.size():
		errs.append("%s: 노드 %s 표면 %d개 ≠ 머티리얼 %d개" % [tag, node, surfaces.size(), mats.size()])
	for mat: String in mats:
		if not palette.has(mat):
			errs.append("%s: 머티리얼 %s 없음" % [tag, mat])


func _validate_variant(outfit_id: String, type_id: String, v: Dictionary, slots: Dictionary, nodes: Dictionary, palette: Dictionary, seen_ids: Dictionary, errs: PackedStringArray) -> void:
	var vid: String = String(v.get("id", ""))
	var tag: String = "%s/%s/%s" % [outfit_id, type_id, vid]
	if vid == "" or seen_ids.has(vid):
		errs.append("%s: ID가 비었거나 중복" % tag)
	seen_ids[vid] = true
	var diff: int = int(v.get("difficulty", 0))
	if diff < 1 or diff > 5:
		errs.append("%s: 등급은 1~5" % tag)
	if not GROUPS.has(String(v.get("group", ""))):
		errs.append("%s: group 값 오류" % tag)
	var kind: String = String(v.get("kind", ""))
	if not KINDS.has(kind):
		errs.append("%s: kind 값 오류" % tag)
	if not MILESTONES.has(String(v.get("milestone", ""))):
		errs.append("%s: milestone 값 오류" % tag)
	var dirs: Array = v.get("visible_from", [])
	if dirs.is_empty():
		errs.append("%s: visible_from 비어 있음" % tag)
	for d: String in dirs:
		if not DIRECTIONS.has(d):
			errs.append("%s: 방향 %s 오류" % [tag, d])
	if float(v.get("identify_distance_m", 0.0)) <= 0.0:
		errs.append("%s: identify_distance_m 오류" % tag)
	var op: Dictionary = v.get("op", {})
	var op_type: String = String(op.get("type", ""))
	if not OPS.has(op_type):
		errs.append("%s: op.type 오류" % tag)
		return
	var slot: String = String(op.get("slot", ""))
	if not slots.has(slot):
		errs.append("%s: op.slot %s가 타입에 없음" % [tag, slot])
		return
	match op_type:
		"swap_mesh":
			_check_node_mats(tag, String(op.get("node", "")), op.get("materials", []), nodes, palette, errs)
		"swap_material":
			var surf: int = int(op.get("surface", -1))
			var base_mats: Array = slots[slot].get("materials", [])
			if surf < 0 or surf >= base_mats.size():
				errs.append("%s: surface 번호 오류" % tag)
			elif not palette.has(String(op.get("material", ""))):
				errs.append("%s: 머티리얼 %s 없음" % [tag, op.get("material", "")])
			elif kind == "color":
				## 색만 다른 변이는 명도 차 ΔL* 15 이상(§6.6 규칙 1). 팔레트 색으로 직접 계산한다.
				var dl: float = absf(lightness(palette[String(base_mats[surf])]["color"]) - lightness(palette[String(op["material"])]["color"]))
				if dl < MIN_DELTA_L:
					errs.append("%s: color 변이의 ΔL* %.1f < %.0f" % [tag, dl, MIN_DELTA_L])
		"hide":
			if String(slots[slot].get("node", "")) == "NONE":
				errs.append("%s: 이미 없는 슬롯을 숨김" % tag)
	if kind == "color" and op_type != "swap_material":
		errs.append("%s: color 변이는 swap_material만 쓴다" % tag)
	## 교차 혼동 금지(§6.6 규칙 7): 변이 결과 슬롯이 다른 타입의 기준 슬롯과 같으면 안 된다.
	var result: Dictionary = Appearance.apply_op(Appearance.base_from(slots), op)
	var after: String = Appearance.slot_key(result[slot])
	if after.begins_with("NONE|") or after.ends_with("|0"):
		return
	for other_id: String in types[outfit_id]:
		if other_id == type_id:
			continue
		var other_slots: Dictionary = types[outfit_id][other_id]["appearance"].get("slots", {})
		var other_base: Dictionary = Appearance.base_from(other_slots)
		for oslot: String in other_base:
			if Appearance.slot_key(other_base[oslot]) == after:
				errs.append("%s: 변이 결과가 타입 %s의 기준 %s 슬롯과 같음(교차 혼동)" % [tag, other_id, oslot])
