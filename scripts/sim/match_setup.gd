class_name MatchSetup
extends RefCounted
## 한 판의 구성(§1.5, §5.6, §6.7). 같은 시드·프리셋·맵이면 결과가 같다(I-09).
## 1) 타입 선택 2) 타입별 인원(최소 인원 + 나머지 균등 배분)
## 3) 타겟 타입을 인원과 무관하게 균등 추첨 → 그 타입 안에서 타겟 1명
## 4) 스폰 배치 5) 타겟 타입 카탈로그에서 변이 선택

var match_seed: int = 0
var preset_id: String = ""
var map_id: String = ""
var outfit_id: String = ""
var types_used: Array[String] = []
var type_counts: Dictionary = {}
var npc_types: Array[String] = []
var target_index: int = -1
var target_type: String = ""
var variant_id: String = ""       ## "" = 차이 없음(--variant=NONE)
var variant: Dictionary = {}
var spawn_positions: Array[Vector2] = []
var appearances: Array[Dictionary] = []
var base_appearances: Dictionary = {}   ## type_id -> 외형
var warnings: PackedStringArray = []


static func build(store: DataStore, layout: ArenaLayout, p_preset_id: String, p_map_id: String, seed_value: int, variant_override: String = "", recent_variants: Array = []) -> MatchSetup:
	var s: MatchSetup = MatchSetup.new()
	s.match_seed = seed_value
	s.preset_id = p_preset_id
	s.map_id = p_map_id
	var preset: Dictionary = store.preset(p_preset_id)
	var map: Dictionary = store.maps[p_map_id]
	s.outfit_id = String(map["outfit"])
	var npc_count: int = int(preset["npc_count"])

	# 1) 타입 선택
	var pool: Array = []
	for t: Dictionary in map["types"]:
		pool.append(String(t["id"]))
	RngUtil.shuffle(pool, RngUtil.make(seed_value, "types"))
	var want: int = int(preset["types_per_match"])
	if want > pool.size():
		s.warnings.append("타입 %d개가 필요하지만 맵에는 %d개뿐이라 있는 타입만 쓴다" % [want, pool.size()])
		want = pool.size()
	for i: int in want:
		s.types_used.append(String(pool[i]))
	s.types_used.sort()

	# 강제 변이(디버그): 그 변이의 타입을 타겟 타입으로 쓴다.
	var forced: Dictionary = {}
	if variant_override != "" and variant_override != "NONE":
		forced = store.find_variant(s.outfit_id, variant_override)
		if forced.is_empty():
			s.warnings.append("변이 %s 없음. 무시한다" % variant_override)
		elif not s.types_used.has(String(forced["type"])):
			s.types_used[0] = String(forced["type"])
			s.types_used.sort()

	# 2) 타입별 인원
	var min_per: int = int(preset["min_per_type"])
	for t: String in s.types_used:
		s.type_counts[t] = min_per
	var rng_counts: RandomNumberGenerator = RngUtil.make(seed_value, "counts")
	for _i: int in npc_count - min_per * s.types_used.size():
		var t2: String = s.types_used[rng_counts.randi_range(0, s.types_used.size() - 1)]
		s.type_counts[t2] = int(s.type_counts[t2]) + 1

	# 3) 타겟 타입: 인원과 무관하게 균등 추첨(§11.2 인원으로 짐작 불가)
	var rng_target: RandomNumberGenerator = RngUtil.make(seed_value, "target")
	s.target_type = s.types_used[rng_target.randi_range(0, s.types_used.size() - 1)]
	if not forced.is_empty():
		s.target_type = String(forced["type"])

	# 4) 배치: 타입 목록을 섞고 스폰 후보를 섞어 앞에서부터 채운다
	var order: Array = []
	for t3: String in s.types_used:
		for _k: int in int(s.type_counts[t3]):
			order.append(t3)
	var rng_spawn: RandomNumberGenerator = RngUtil.make(seed_value, "spawn")
	RngUtil.shuffle(order, rng_spawn)
	var spots: Array = layout.spawn_candidates.duplicate()
	RngUtil.shuffle(spots, rng_spawn)
	for i: int in npc_count:
		s.npc_types.append(String(order[i]))
		s.spawn_positions.append(spots[i] as Vector2)
	var of_type: Array[int] = []
	for i: int in npc_count:
		if s.npc_types[i] == s.target_type:
			of_type.append(i)
	s.target_index = of_type[rng_target.randi_range(0, of_type.size() - 1)]

	# 5) 변이
	var catalog: Array = store.type_data(s.outfit_id, s.target_type).get("variants", [])
	if variant_override == "NONE":
		s.variant_id = ""
	elif not forced.is_empty():
		s.variant = forced["variant"]
	else:
		s.variant = _pick_variant(store, catalog, preset, s, recent_variants, RngUtil.make(seed_value, "variant"))
	if not s.variant.is_empty():
		s.variant_id = String(s.variant["id"])

	# 외형
	for t4: String in s.types_used:
		s.base_appearances[t4] = Appearance.base_from(store.type_data(s.outfit_id, t4)["appearance"]["slots"])
	for i: int in npc_count:
		var app: Dictionary = (s.base_appearances[s.npc_types[i]] as Dictionary).duplicate(true)
		if i == s.target_index and not s.variant.is_empty():
			app = Appearance.apply_op(app, s.variant["op"])
		s.appearances.append(app)
	return s


## §6.7: 그 타입 카탈로그에서 등급 범위·현재 단계에 드는 변이만, 직전 판들의 변이를 빼고 균등 추첨한다.
static func _pick_variant(store: DataStore, catalog: Array, preset: Dictionary, s: MatchSetup, recent: Array, rng: RandomNumberGenerator) -> Dictionary:
	if catalog.is_empty():
		s.warnings.append("타입 %s에 변이가 없음" % s.target_type)
		return {}
	var range_arr: Array = preset["variant_difficulty"]
	var lo: int = int(range_arr[0])
	var hi: int = int(range_arr[1])
	var cands: Array = store.variants_in_range(s.outfit_id, s.target_type, lo, hi)
	if cands.is_empty():
		s.warnings.append("등급 %d~%d 변이가 없어 가장 가까운 등급을 쓴다" % [lo, hi])
		var best_gap: int = 99
		for v2: Dictionary in catalog:
			if not store.milestone_ok(String(v2.get("milestone", "M0"))):
				continue
			var d2: int = int(v2["difficulty"])
			var gap: int = lo - d2 if d2 < lo else d2 - hi
			if gap < best_gap:
				best_gap = gap
				cands = [v2]
			elif gap == best_gap:
				cands.append(v2)
	if cands.is_empty():
		return {}
	var fresh: Array = []
	for v3: Dictionary in cands:
		if not recent.has(String(v3["id"])):
			fresh.append(v3)
	if not fresh.is_empty():
		cands = fresh
	return cands[rng.randi_range(0, cands.size() - 1)]


func signature_of(i: int) -> String:
	return Appearance.signature(npc_types[i], appearances[i])


func base_signature(type_id: String) -> String:
	return Appearance.signature(type_id, base_appearances[type_id])
