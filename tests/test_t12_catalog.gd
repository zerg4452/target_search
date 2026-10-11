extends TestCase
## T-12: 변이 카탈로그 규모(§15 M1·M2)와 판마다 변이 고르기(§6.7: 등급 범위, 현재 단계, 직전 판 제외).


func _count(store: DataStore, type_id: String, milestone: String) -> int:
	var c: int = 0
	for v: Dictionary in store.type_data("mall_guest", type_id)["variants"]:
		if DataStore.MILESTONES.find(String(v["milestone"])) <= DataStore.MILESTONES.find(milestone):
			c += 1
	return c


func test_catalog_sizes_meet_milestones() -> bool:
	var store: DataStore = SimFixture.store()
	eq(String(store.difficulty["milestone"]), "M2", "현재 단계")
	check(_count(store, "a_hoodie", "M1") >= 12, "M1: 타입 A 변이 12종 이상")
	check(_count(store, "b_coat", "M1") >= 6, "M1: 타입 B 변이 6종 이상")
	check(_count(store, "c_vest", "M1") >= 6, "M1: 타입 C 변이 6종 이상")
	check(_count(store, "a_hoodie", "M2") >= 24, "M2: 타입 A 변이 24종 이상")
	check(_count(store, "b_coat", "M2") >= 12, "M2: 타입 B 변이 12종 이상")
	check(_count(store, "c_vest", "M2") >= 12, "M2: 타입 C 변이 12종 이상")
	check(_count(store, "d_suit", "M2") >= 6, "M2: 예비 타입 D 변이 6종 이상")
	for t: String in ["a_hoodie", "b_coat", "c_vest", "d_suit"]:
		var grades: Dictionary = {}
		for v: Dictionary in store.type_data("mall_guest", t)["variants"]:
			grades[int(v["difficulty"])] = true
		note("%s: 변이 %d종, 등급 %s" % [t, store.type_data("mall_guest", t)["variants"].size(), str(grades.keys())])
	return true


func test_original_examples_are_in_catalog() -> bool:
	## 원안 예시 5종(§0.4): 머리 재질, 표정, 로고·글자, 가방 반대, 신발 종류.
	var store: DataStore = SimFixture.store()
	for vid: String in ["VA11_HAIR_GLOSS", "VA08_FACE_SMILE", "VA04_LOGO_TRIANGLE", "VA12_BACK_TEXT_ECH0", "VA01_BAG_MIRROR", "VA02_SHOES_LOAFER"]:
		check(not store.find_variant("mall_guest", vid).is_empty(), "원안 예시 변이 %s" % vid)
	return true


func test_hard_uses_four_types() -> bool:
	var store: DataStore = SimFixture.store()
	var layout: ArenaLayout = SimFixture.layout()
	for seed_value: int in range(1, 21):
		var s: MatchSetup = MatchSetup.build(store, layout, "hard", "atrium", seed_value)
		eq(s.types_used.size(), 4, "시드 %d 어려움 타입 수" % seed_value)
		check(s.warnings.is_empty(), "시드 %d 경고: %s" % [seed_value, ", ".join(s.warnings)])
	return true


func test_variant_respects_grade_range() -> bool:
	var store: DataStore = SimFixture.store()
	var layout: ArenaLayout = SimFixture.layout()
	for pid: String in ["practice", "standard", "hard"]:
		var r: Array = store.preset(pid)["variant_difficulty"]
		for seed_value: int in range(1, 101):
			var s: MatchSetup = MatchSetup.build(store, layout, pid, "atrium", seed_value)
			var d: int = int(s.variant["difficulty"])
			check(d >= int(r[0]) and d <= int(r[1]), "%s 시드 %d 변이 %s 등급 %d" % [pid, seed_value, s.variant_id, d])
	return true


func test_recent_variants_are_excluded() -> bool:
	var store: DataStore = SimFixture.store()
	var layout: ArenaLayout = SimFixture.layout()
	var base: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", 42)
	var cands: Array = store.variants_in_range("mall_guest", base.target_type, 1, 4)
	check(cands.size() >= 2, "후보가 2개 이상이어야 검사할 수 있음")
	## 후보 하나만 남기고 모두 '직전 판'으로 넣으면 남은 하나가 뽑혀야 한다.
	var keep: String = String(cands[0]["id"])
	var recent: Array = []
	for v: Dictionary in cands:
		if String(v["id"]) != keep:
			recent.append(String(v["id"]))
	var s: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", 42, "", recent)
	eq(s.target_type, base.target_type, "직전 판 목록은 타겟 타입에 영향이 없음")
	eq(s.variant_id, keep, "직전 판 변이를 뺀 나머지에서 뽑아야 함")
	## 모두 직전 판이면 조건을 푼다.
	recent.append(keep)
	var s2: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", 42, "", recent)
	check(s2.variant_id != "", "후보가 모두 빠지면 조건을 풀어야 함")
	## 직전 3판만 쓴다(기록 쪽 규칙). 같은 입력이면 결과가 같다(I-09).
	var s3: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", 42, "", recent)
	eq(s3.variant_id, s2.variant_id, "같은 입력이면 같은 변이")
	return true
