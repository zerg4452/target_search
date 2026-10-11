extends TestCase
## T-16: 군중 가속(§7.9, 6차 결정). 2단계에서 남은 일반 NPC가 절반 이하가 되면 한 명 줄 때마다 모든 NPC의 걷는 속도가 오른다.
## 연습 난이도에는 없다. 관찰되는 타겟도 일반 NPC와 같은 속도로 걷는다(행동 누설 없음).


func _hunt_sim(preset_id: String) -> MatchSim:
	var sim: MatchSim = SimFixture.make(31, {"preset": preset_id})
	sim.debug_force_hunt()
	SimFixture.run(sim, 0.1)
	return sim


func _kill_down_to(sim: MatchSim, remaining: int) -> void:
	for n: NpcState in sim.npcs:
		if sim.normals_alive() <= remaining:
			break
		if not n.is_target and n.alive:
			sim.debug_eliminate(n.id)
	sim._update_crowd_speed()


func test_multiplier_schedule() -> bool:
	var sim: MatchSim = _hunt_sim("standard")
	var cfg: Dictionary = sim.preset["crowd_speedup"]
	eq(sim.normals_start, 29, "표준 일반 NPC 29명")
	var half: int = int(floor(29 * float(cfg["start_ratio"])))
	check(is_equal_approx(sim.crowd_mult_for(29), 1.0), "처음에는 1배")
	check(is_equal_approx(sim.crowd_mult_for(half + 1), 1.0), "절반보다 많으면 1배")
	check(is_equal_approx(sim.crowd_mult_for(half), 1.0 + float(cfg["per_step"])), "절반이 되는 순간 첫 단계")
	check(is_equal_approx(sim.crowd_mult_for(half - 1), 1.0 + 2.0 * float(cfg["per_step"])), "한 명 더 줄면 한 단계 더")
	check(sim.crowd_mult_for(1) <= float(cfg["max_mult"]) + 0.0001, "최대 배율을 넘지 않음")
	var prev: float = 1.0
	for r: int in range(29, 0, -1):
		var m: float = sim.crowd_mult_for(r)
		check(m >= prev - 0.0001, "남은 사람이 줄수록 배율은 줄지 않음 (%d명)" % r)
		prev = m
	note("표준: 절반 %d명부터, 1명 남았을 때 ×%.2f / 어려움 1명 남았을 때 ×%.2f" % [half, sim.crowd_mult_for(1), _hunt_sim("hard").crowd_mult_for(1)])
	return true


func test_practice_has_no_speedup() -> bool:
	var sim: MatchSim = _hunt_sim("practice")
	_kill_down_to(sim, 1)
	check(is_equal_approx(sim.crowd_speed_mult, 1.0), "연습 난이도는 군중 가속 없음")
	return true


func test_search_phase_never_speeds_up() -> bool:
	var sim: MatchSim = SimFixture.make(31, {"preset": "standard"})
	_kill_down_to(sim, 5)
	check(is_equal_approx(sim.crowd_speed_mult, 1.0), "1단계에서는 적용하지 않음")
	return true


func test_everyone_walks_at_crowd_speed_including_observed_target() -> bool:
	var sim: MatchSim = _hunt_sim("standard")
	_kill_down_to(sim, 6)
	var want: float = float(sim.npc_t["walk_speed_mps"]) * sim.crowd_speed_mult
	check(sim.crowd_speed_mult > 1.0, "6명 남으면 가속 중")
	## 플레이어를 타겟 옆(안전지대)에 붙여 타겟을 계속 관찰한다.
	var seen_target: int = 0
	for _i: int in 240:
		sim.player_pos = sim.layout.resolve_circle(sim.target.pos + Vector2(1.5, 0.0), 0.35)
		sim.step(PlayerInput.new())
		if sim.is_observed(sim.target) and sim.target.mode == NpcState.Mode.MOVING:
			seen_target += 1
			check(is_equal_approx(sim.target.speed, want), "관찰되는 타겟 속도 %.3f = 군중 속도 %.3f" % [sim.target.speed, want])
		for n: NpcState in sim.npcs:
			if n.alive and not n.is_target and n.mode == NpcState.Mode.MOVING:
				check(is_equal_approx(n.speed, want), "일반 NPC 속도 = 군중 속도")
	note("관찰 중 걷는 타겟 표본 %d틱" % seen_target)
	return true


func test_event_emitted_once_per_change() -> bool:
	var sim: MatchSim = _hunt_sim("hard")
	sim.events.clear()
	_kill_down_to(sim, 14)
	var evs: Array[Dictionary] = []
	for e: Dictionary in sim.events:
		if String(e["type"]) == "crowd_speed_changed":
			evs.append(e)
	eq(evs.size(), 1, "배율이 바뀔 때 한 번")
	if not evs.is_empty():
		check(bool(evs[0]["first"]), "첫 가속 표시")
	return true
