extends TestCase
## T-01 (I-01): 같은 타입의 일반 NPC는 외형 서명이 같다. 타입 수·최소 인원을 지킨다.
## 타겟 타입의 인원은 다른 타입과 같은 분포여야 한다(인원으로 타겟 타입을 짐작할 수 없음, §11.2).


func test_same_type_signatures_equal() -> bool:
	var store: DataStore = SimFixture.store()
	var layout: ArenaLayout = SimFixture.layout()
	var preset: Dictionary = store.preset("standard")
	for seed_value: int in range(1, 51):
		var s: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", seed_value)
		eq(s.types_used.size(), int(preset["types_per_match"]), "시드 %d 타입 수" % seed_value)
		var total: int = 0
		for t: String in s.types_used:
			check(int(s.type_counts[t]) >= int(preset["min_per_type"]), "시드 %d 타입 %s 인원 %d < 최소" % [seed_value, t, s.type_counts[t]])
			total += int(s.type_counts[t])
		eq(total, int(preset["npc_count"]), "시드 %d 총 인원" % seed_value)
		for i: int in s.npc_types.size():
			if i == s.target_index:
				continue
			eq(s.signature_of(i), s.base_signature(s.npc_types[i]), "시드 %d NPC %d 서명이 타입 기준과 다름" % [seed_value, i])
	return true


func test_target_type_count_unbiased() -> bool:
	var store: DataStore = SimFixture.store()
	var layout: ArenaLayout = SimFixture.layout()
	var n: int = 1000
	var sum_target: float = 0.0
	var largest: int = 0
	var smallest: int = 0
	for seed_value: int in range(1000, 1000 + n):
		var s: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", seed_value)
		var c: int = int(s.type_counts[s.target_type])
		sum_target += c
		var mx: int = 0
		var mn: int = 999
		for t: String in s.types_used:
			mx = maxi(mx, int(s.type_counts[t]))
			mn = mini(mn, int(s.type_counts[t]))
		if c == mx:
			largest += 1
		if c == mn:
			smallest += 1
	var mean_target: float = sum_target / n
	var expected: float = 30.0 / 3.0
	note("타겟 타입 평균 인원 %.3f (전체 평균 %.1f) · 가장 많은 타입 %d회 · 가장 적은 타입 %d회 / %d판" % [mean_target, expected, largest, smallest, n])
	check(absf(mean_target - expected) < 0.15, "타겟 타입 평균 인원 %.3f가 전체 평균 %.1f에서 벗어남(인원 편향)" % [mean_target, expected])
	check(absi(largest - smallest) < n / 10, "가장 많은/적은 타입이 될 비율이 한쪽으로 치우침 (%d vs %d)" % [largest, smallest])
	return true
