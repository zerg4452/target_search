extends TestCase
## T-06 (I-06): 정답이면 승리. 오답은 기회 −1, 이동속도 −10%(최대 −30%), 5초 지목 불가, NPC 표시 없음. 기회 0이면 패배.


## 플레이어를 대상 곁에 두고 대상을 조준한 채 seconds초 동안 지목 키를 누른다.
func _hold_on(sim: MatchSim, npc_id: int, seconds: float) -> void:
	for _i: int in int(round(seconds / MatchSim.DT)):
		sim.player_pos = sim.layout.resolve_circle(sim.npcs[npc_id].pos + Vector2(1.2, 0.0), 0.35)
		var inp: PlayerInput = PlayerInput.new()
		inp.aim_override = npc_id
		inp.accuse_held = true
		sim.step(inp)
		if sim.is_resolved():
			return


func _release(sim: MatchSim, seconds: float) -> void:
	SimFixture.run(sim, seconds)


func _a_normal(sim: MatchSim) -> int:
	for n: NpcState in sim.npcs:
		if not n.is_target:
			return n.id
	return -1


func test_correct_accusation_wins() -> bool:
	var sim: MatchSim = SimFixture.make(8)
	_hold_on(sim, sim.target.id, 0.5)
	check(not sim.is_resolved(), "0.8초 전에는 확정되지 않음")
	_hold_on(sim, sim.target.id, 0.4)
	eq(String(sim.result.get("outcome", "")), "WIN", "정답 지목은 승리")
	eq(String(sim.result.get("found_in", "")), "SEARCH", "1단계 발견")
	eq(String(sim.result.get("grade", "")), "S", "1단계·오답 0회는 S")
	var expected: int = 29 * 100 + int(floor(sim.search_left)) * 10 + 500
	eq(int(sim.result.get("score", -1)), expected, "점수 공식")
	eq(sim.phase, MatchSim.Phase.REVEAL, "정체 공개로 넘어감")
	return true


func test_wrong_accusation_penalties() -> bool:
	var sim: MatchSim = SimFixture.make(9)
	var wrong_id: int = _a_normal(sim)
	var sig_before: String = sim.setup.signature_of(wrong_id)
	var search_before: float = sim.search_left
	_hold_on(sim, wrong_id, 0.9)
	eq(sim.accusations_left, 2, "오답 1회 후 남은 기회")
	check(absf(sim.player_speed_mult - 0.9) < 0.0001, "이동속도 0.9배")
	check(sim.lock_until - sim.match_time > 4.8, "5초 지목 불가 시작")
	eq(sim.setup.signature_of(wrong_id), sig_before, "오답 NPC에 표시가 붙지 않음")
	check(absf(search_before - sim.search_left - sim.match_time) < 0.001, "오답이 탐색 시간을 줄이지 않음")
	# 지목 불가 중에는 계속 눌러도 확정되지 않는다.
	_hold_on(sim, wrong_id, 3.0)
	eq(sim.accusations_left, 2, "지목 불가 중 확정 없음")
	_release(sim, 2.2)
	# 같은 NPC를 다시 지목할 수 있다.
	_hold_on(sim, wrong_id, 0.9)
	eq(sim.accusations_left, 1, "같은 NPC 재지목 허용")
	check(absf(sim.player_speed_mult - 0.8) < 0.0001, "이동속도 0.8배")
	_release(sim, 5.1)
	_hold_on(sim, wrong_id, 0.9)
	eq(String(sim.result.get("outcome", "")), "LOSE_NO_CHANCES", "기회를 모두 쓰면 패배")
	return true


func test_speed_penalty_caps_at_30_percent() -> bool:
	var sim: MatchSim = SimFixture.make(10, {"preset": "practice"})
	var wrong_id: int = _a_normal(sim)
	for k: int in 4:
		_hold_on(sim, wrong_id, 0.9)
		_release(sim, 5.1)
	eq(sim.wrongs, 4, "오답 4회")
	check(absf(sim.player_speed_mult - 0.7) < 0.0001, "이동속도 감소는 최대 30%% (실제 %.2f)" % sim.player_speed_mult)
	return true
