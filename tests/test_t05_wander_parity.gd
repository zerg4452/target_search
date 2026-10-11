extends TestCase
## T-05 (I-05): 1단계에서 타겟과 일반 NPC의 이동 통계가 같다(행동으로 타겟을 찾을 수 없음).
## 지표: 이동 시간 비율, 이동 중 평균 속도, 구간당 평균 거리. 타겟이 일반 NPC 분포의 max(3σ, 평균의 10%) 안에 있어야 한다.

const SECONDS: float = 600.0


func _metrics(n: NpcState) -> Array[float]:
	var total: float = n.stat_moving_time + n.stat_idle_time
	return [
		n.stat_moving_time / maxf(total, 0.001),
		n.stat_distance / maxf(n.stat_moving_time, 0.001),
		n.stat_leg_distance / maxf(float(n.stat_legs), 1.0),
	]


func test_target_moves_like_everyone_else() -> bool:
	var names: Array[String] = ["이동 비율", "평균 속도", "구간 거리"]
	for seed_value: int in [3, 4]:
		var sim: MatchSim = SimFixture.make(seed_value, {"search_time": SECONDS + 10.0})
		SimFixture.run(sim, SECONDS)
		eq(sim.phase, MatchSim.Phase.SEARCH, "시드 %d 검사 중 단계" % seed_value)
		var target_m: Array[float] = _metrics(sim.target)
		for k: int in names.size():
			var vals: Array[float] = []
			for n: NpcState in sim.npcs:
				if not n.is_target:
					vals.append(_metrics(n)[k])
			var mean: float = 0.0
			for v: float in vals:
				mean += v
			mean /= vals.size()
			var var_sum: float = 0.0
			for v2: float in vals:
				var_sum += (v2 - mean) * (v2 - mean)
			var sd: float = sqrt(var_sum / vals.size())
			var tol: float = maxf(3.0 * sd, absf(mean) * 0.1)
			note("시드 %d %s: 타겟 %.3f · 일반 %.3f±%.3f" % [seed_value, names[k], target_m[k], mean, sd])
			check(absf(target_m[k] - mean) <= tol, "시드 %d %s: 타겟 %.3f가 일반 평균 %.3f±%.3f 밖" % [seed_value, names[k], target_m[k], mean, tol])
	return true
