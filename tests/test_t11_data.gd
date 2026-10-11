extends TestCase
## T-11 (I-11): 데이터 스키마·참조 검사. 잘못된 데이터는 실제로 걸러져야 한다.


func _clone() -> DataStore:
	var src: DataStore = SimFixture.store()
	var s: DataStore = DataStore.new()
	s.difficulty = src.difficulty.duplicate(true)
	s.npc = src.npc.duplicate(true)
	s.hunt = src.hunt.duplicate(true)
	s.player = src.player.duplicate(true)
	s.visibility = src.visibility.duplicate(true)
	s.scoring = src.scoring.duplicate(true)
	s.maps = src.maps.duplicate(true)
	s.outfits = src.outfits.duplicate(true)
	s.types = src.types.duplicate(true)
	s.manifests = src.manifests.duplicate(true)
	return s


func _has(errs: PackedStringArray, needle: String) -> bool:
	for e: String in errs:
		if e.contains(needle):
			return true
	return false


func test_shipped_data_is_valid() -> bool:
	var errs: PackedStringArray = SimFixture.store().validate()
	for e: String in errs:
		failures.append("데이터 오류: %s" % e)
	for p: Dictionary in SimFixture.store().difficulty["presets"]:
		note("%s: 이론상 최단 패배 %.1f초" % [p["id"], DataStore.theoretical_wipe_s(p)])
	return true


func test_color_variant_needs_luminance_contrast() -> bool:
	var s: DataStore = _clone()
	var v: Dictionary = _variant(s, "a_hoodie", "VA10_LACES_BLACK")
	eq(String(v["kind"]), "color", "준비: VA10은 color")
	check(not _has(s.validate(), "ΔL*"), "흰 끈 → 검정 끈은 통과해야 함")
	v["op"]["material"] = "mat_sneaker_white"   ## 흰 끈 → 흰 신발색: 명도 차가 거의 없다
	check(_has(s.validate(), "ΔL*"), "ΔL* 15 미만 color 변이를 잡아야 함")
	return true


func test_cross_type_confusion_is_rejected() -> bool:
	var s: DataStore = _clone()
	## 타입 A의 이어폰 변이를 타입 C의 기준 이어폰(검정 양쪽)과 같게 만든다.
	var v: Dictionary = _variant(s, "a_hoodie", "VA18_EARBUD_ONE")
	v["op"] = {"type": "swap_mesh", "slot": "ears", "node": "EarbudsBlack", "materials": ["mat_earbud_black"]}
	check(_has(s.validate(), "교차 혼동"), "다른 타입의 기준 부품과 같아지는 변이를 잡아야 함")
	return true


func test_bad_references_are_rejected() -> bool:
	var s: DataStore = _clone()
	var v: Dictionary = _variant(s, "b_coat", "VB03_COAT_BELT")
	v["op"]["node"] = "NoSuchPart"
	v["difficulty"] = 9
	var dup: Dictionary = _variant(s, "c_vest", "VC01_BACKPACK_ONE_STRAP").duplicate(true)
	dup["id"] = "VB01_TOTE_MIRROR"
	(s.types["mall_guest"]["c_vest"]["variants"] as Array).append(dup)
	var w: Dictionary = _variant(s, "d_suit", "VD02_TIE_MISSING")
	w["op"] = {"type": "swap_mesh", "slot": "tie", "node": "TieStriped", "materials": ["mat_tie_burgundy"]}
	var errs: PackedStringArray = s.validate()
	check(_has(errs, "NoSuchPart"), "없는 노드 참조")
	check(_has(errs, "등급은 1~5"), "등급 범위")
	check(_has(errs, "중복"), "ID 중복")
	check(_has(errs, "표면 2개 ≠ 머티리얼 1개"), "표면 수와 머티리얼 수 불일치")
	return true


func test_missing_manifest_is_reported() -> bool:
	var s: DataStore = _clone()
	(s.manifests["mall_guest"] as Dictionary)["b_coat"] = {}
	check(_has(s.validate(), "manifest"), "노드 목록이 없으면 잡아야 함")
	return true


func test_every_preset_has_variants_for_every_type() -> bool:
	var s: DataStore = _clone()
	for v: Dictionary in s.types["mall_guest"]["d_suit"]["variants"]:
		if int(v["difficulty"]) <= 2:
			v["difficulty"] = 3
	check(_has(s.validate(), "practice 난이도"), "연습 등급(1~2) 변이가 없는 타입을 잡아야 함")
	return true


func _variant(s: DataStore, type_id: String, vid: String) -> Dictionary:
	for v: Dictionary in s.types["mall_guest"][type_id]["variants"]:
		if String(v["id"]) == vid:
			return v
	failures.append("변이 %s 없음" % vid)
	return {}


func test_match_length_limit_is_enforced() -> bool:
	var s: DataStore = _clone()
	(s.difficulty["presets"][1] as Dictionary)["search_time_s"] = 400
	check(_has(s.validate(), "상한"), "5분 상한을 넘는 프리셋을 잡아야 함")
	return true
