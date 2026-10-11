extends TestCase
## T-03 (I-03): 제거되는 순간과 그 전 1.0초 동안 피해자와 타겟이 모두 비관찰이었다.
## 매 틱 카메라와 위치를 따로 기록해 두고, 제거가 일어나면 지난 60틱을 독립적으로 다시 판정한다.

const WINDOW: int = 60


class Snapshot:
	var cam: SimCamera
	var pos: PackedVector2Array


func _snapshot(sim: MatchSim) -> Snapshot:
	var s: Snapshot = Snapshot.new()
	s.cam = SimCamera.new()
	s.cam.copy_from(sim.camera)
	for n: NpcState in sim.npcs:
		s.pos.append(n.pos)
	return s


func _run_bot(seed_value: int, hunt_seconds: float) -> Dictionary:
	var sim: MatchSim = SimFixture.make(seed_value, {"search_time": 1.0})
	var rng: RandomNumberGenerator = RngUtil.make(seed_value, "bot")
	var ring: Array[Snapshot] = []
	var next_turn: float = 0.0
	var desired_yaw: float = 0.0
	var observe: bool = false
	var kills: int = 0
	var violations: int = 0
	var ticks: int = int(round((hunt_seconds + 1.0) / MatchSim.DT))
	for _i: int in ticks:
		var inp: PlayerInput = PlayerInput.new()
		if sim.match_time >= next_turn:
			next_turn = sim.match_time + rng.randf_range(0.5, 2.0)
			desired_yaw = rng.randf_range(-PI, PI)
			observe = rng.randf() < 0.3
		inp.look_delta = Vector2(angle_difference(sim.yaw, desired_yaw), 0.0)
		inp.observe = observe
		sim.step(inp)
		ring.append(_snapshot(sim))
		if ring.size() > WINDOW:
			ring.pop_front()
		for e: Dictionary in sim.events:
			if String(e["type"]) != "npc_eliminated":
				continue
			kills += 1
			var v: int = int(e["victim"])
			var t: int = int(e["by"])
			for snap: Snapshot in ring:
				if Visibility.observed_now(snap.pos[v], snap.cam, sim.layout, sim.vis_t) or Visibility.observed_now(snap.pos[t], snap.cam, sim.layout, sim.vis_t):
					violations += 1
		if sim.is_resolved():
			break
	return {"kills": kills, "violations": violations}


func test_bot_camera_never_sees_elimination() -> bool:
	var total_kills: int = 0
	for seed_value: int in [11, 22, 33]:
		var r: Dictionary = _run_bot(seed_value, 150.0)
		total_kills += int(r["kills"])
		eq(int(r["violations"]), 0, "시드 %d: 관찰 중 제거 위반 틱 수" % seed_value)
	note("무작위 회전 봇 3판 제거 합계 %d회" % total_kills)
	check(total_kills >= 10, "제거가 너무 적어 검사가 의미 없음 (%d회)" % total_kills)
	return true


func test_following_target_prevents_all_eliminations() -> bool:
	var sim: MatchSim = SimFixture.make(5, {"search_time": 1.0})
	var kills: int = 0
	for _i: int in int(round(61.0 / MatchSim.DT)):
		sim.player_pos = sim.layout.resolve_circle(sim.target.pos + Vector2(1.5, 0.0), 0.35)
		sim.step(PlayerInput.new())
		for e: Dictionary in sim.events:
			if String(e["type"]) == "npc_eliminated":
				kills += 1
	eq(kills, 0, "타겟 곁(안전지대)에 계속 붙어 있으면 제거 0회")
	return true
