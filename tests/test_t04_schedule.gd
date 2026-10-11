extends TestCase
## T-04 (I-04): 제거는 HUNT에서 타겟만 한다. 첫 제거 지연과 간격 I(k)를 지킨다.
## 힌트는 HUNT 10초 뒤부터 10초마다, 출력 틱의 실제 거리 구간으로만 나온다.


func test_schedule_and_hints_in_corner_scenario() -> bool:
	var sim: MatchSim = SimFixture.make(42)
	SimFixture.face_corner(sim)
	var kill_times: Array[float] = []
	var hint_times: Array[float] = []
	var first_delay: float = float(sim.preset["first_kill_delay_s"])
	var max_ticks: int = int(round(400.0 / MatchSim.DT))
	for _i: int in max_ticks:
		var phase_before: int = sim.phase
		sim.step(PlayerInput.new())
		for e: Dictionary in sim.events:
			match String(e["type"]):
				"npc_eliminated":
					check(phase_before == MatchSim.Phase.HUNT, "HUNT 밖에서 제거")
					eq(int(e["by"]), sim.target.id, "제거 주체는 타겟")
					kill_times.append(float(e["hunt_time"]))
				"hint_shown":
					check(sim.phase == MatchSim.Phase.HUNT, "HUNT 밖에서 힌트")
					var d: float = sim.player_pos.distance_to(sim.target.pos)
					check(absf(d - float(e["distance"])) < 0.001, "힌트 거리는 출력 틱의 실제 거리")
					eq(int(e["band"]), sim.distance_band(d), "힌트 구간")
					eq(float(e["duration_s"]), 3.0, "힌트 표시 시간")
					hint_times.append(float(e["hunt_time"]))
		if sim.is_resolved():
			break
	check(not kill_times.is_empty(), "제거가 없음")
	if not kill_times.is_empty():
		check(kill_times[0] + 0.0001 >= first_delay, "첫 제거 %.3f초 < 지연 %.1f초" % [kill_times[0], first_delay])
	for k: int in range(1, kill_times.size()):
		var gap: float = kill_times[k] - kill_times[k - 1]
		check(gap + 0.0001 >= sim.kill_interval(k), "제거 %d→%d 간격 %.3f초 < I(%d)=%.2f초" % [k, k + 1, gap, k, sim.kill_interval(k)])
	for i: int in hint_times.size():
		var expected: float = 10.0 * (i + 1)
		check(absf(hint_times[i] - expected) <= MatchSim.DT * 1.5, "힌트 %d 시점 %.3f초 (기대 %.1f초)" % [i + 1, hint_times[i], expected])
	check(hint_times.size() >= 5, "힌트가 너무 적음 (%d회)" % hint_times.size())
	var total: float = MatchSim.BRIEFING_S + MatchSim.DROP_S + float(sim.preset["search_time_s"]) + sim.hunt_time
	note("구석 시나리오: 결과 %s · 제거 %d회 · 마지막 제거 HUNT %.1f초 · 기회 공백 %.1f초 · 브리핑 포함 한 판 %.0f초" % [
		sim.result.get("outcome", "-"), kill_times.size(), kill_times[-1] if not kill_times.is_empty() else 0.0, sim.drought_time, total])
	eq(String(sim.result.get("outcome", "")), "LOSE_ALL_GONE", "구석에서 아무것도 안 하면 전멸 패배")
	## 5분은 플레이테스트 지표(§14.4)다. 여기서는 회귀 방지선으로 5분 30초를 둔다.
	## 여러 시드 측정은 tools/measure_match_length.gd.
	check(total <= 330.0, "한 판 %.0f초가 회귀 방지선 330초를 넘음" % total)
	return true
