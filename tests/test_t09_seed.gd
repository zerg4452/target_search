extends TestCase
## T-09 (I-09): 시드와 프리셋이 같으면 변이·타겟·스폰이 같다.


func _key(s: MatchSetup) -> String:
	return "%s|%s|%s|%d|%s|%s" % [str(s.types_used), str(s.type_counts), str(s.npc_types), s.target_index, s.variant_id, str(s.spawn_positions)]


func test_same_seed_same_setup() -> bool:
	var store: DataStore = SimFixture.store()
	var layout: ArenaLayout = SimFixture.layout()
	for seed_value: int in [1, 77, 123456]:
		var a: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", seed_value)
		var b: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", seed_value)
		eq(_key(a), _key(b), "시드 %d 구성이 같아야 함" % seed_value)
	var c: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", 1)
	var d: MatchSetup = MatchSetup.build(store, layout, "standard", "atrium", 2)
	check(_key(c) != _key(d), "다른 시드는 구성이 달라야 함")
	return true


func test_same_seed_same_simulation() -> bool:
	var a: MatchSim = SimFixture.make(55)
	var b: MatchSim = SimFixture.make(55)
	SimFixture.run(a, 20.0)
	SimFixture.run(b, 20.0)
	var same: bool = true
	for i: int in a.npcs.size():
		if a.npcs[i].pos.distance_to(b.npcs[i].pos) > 0.000001:
			same = false
	check(same, "순수 시뮬레이션이므로 같은 입력·시드면 위치도 같음")
	return true
