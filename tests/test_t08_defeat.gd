extends TestCase
## T-08 (I-08): 일반 NPC가 0명이 되면 즉시 패배한다. 타겟은 세지 않는다.


func test_all_normals_gone_is_defeat() -> bool:
	var sim: MatchSim = SimFixture.make(12)
	eq(sim.normals_alive(), 29, "일반 NPC 29명(타겟 제외)")
	for n: NpcState in sim.npcs:
		if not n.is_target:
			sim.debug_eliminate(n.id)
	check(sim.target.alive, "타겟은 살아 있음")
	sim.step(PlayerInput.new())
	eq(String(sim.result.get("outcome", "")), "LOSE_ALL_GONE", "즉시 패배")
	eq(int(sim.result.get("remaining", -1)), 0, "구한 사람 0명")
	return true


func test_one_normal_left_is_not_defeat() -> bool:
	var sim: MatchSim = SimFixture.make(13)
	var kept: bool = false
	for n: NpcState in sim.npcs:
		if n.is_target:
			continue
		if not kept:
			kept = true
			continue
		sim.debug_eliminate(n.id)
	sim.step(PlayerInput.new())
	check(not sim.is_resolved(), "일반 NPC가 1명이라도 남으면 계속")
	return true
