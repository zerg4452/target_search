extends TestCase
## T-02 (I-02): 변이 정의의 연산은 1개이고 정확히 한 슬롯만 바꾼다. 타겟은 자기 타입 기준과 한 슬롯만 다르다.


func test_each_variant_changes_one_slot() -> bool:
	var store: DataStore = SimFixture.store()
	var count: int = 0
	for outfit_id: String in store.types:
		for type_id: String in store.types[outfit_id]:
			var slots: Dictionary = store.types[outfit_id][type_id]["appearance"]["slots"]
			var base: Dictionary = Appearance.base_from(slots)
			for v: Dictionary in store.types[outfit_id][type_id]["variants"]:
				check(typeof(v.get("op")) == TYPE_DICTIONARY, "%s: op는 사전 하나여야 함" % v["id"])
				var after: Dictionary = Appearance.apply_op(base, v["op"])
				var diff: PackedStringArray = Appearance.diff_slots(base, after)
				eq(diff.size(), 1, "%s: 바뀐 슬롯 수" % v["id"])
				count += 1
	note("검사한 변이 %d개" % count)
	check(count > 0, "변이가 하나도 없음")
	return true


func test_target_differs_in_exactly_one_slot() -> bool:
	var store: DataStore = SimFixture.store()
	var layout: ArenaLayout = SimFixture.layout()
	for seed_value: int in range(1, 201):
		var s: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", seed_value)
		var diff: PackedStringArray = Appearance.diff_slots(s.appearances[s.target_index], s.base_appearances[s.target_type])
		eq(diff.size(), 1, "시드 %d 타겟이 기준과 다른 슬롯 수" % seed_value)
	var none_setup: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", 7, "NONE")
	eq(none_setup.signature_of(none_setup.target_index), none_setup.base_signature(none_setup.target_type), "--variant=NONE이면 타겟도 기준과 같아야 함")
	var forced: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", 7, "VB03_COAT_BELT")
	eq(forced.variant_id, "VB03_COAT_BELT", "강제 변이")
	eq(forced.target_type, "b_coat", "강제 변이의 타입이 타겟 타입")
	return true
