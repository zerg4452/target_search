extends TestCase
## T-10 (I-10): 일시정지 중에는 타이머·이동·제거·쿨다운이 멈춘다.


func _state(sim: MatchSim) -> String:
	var parts: PackedStringArray = ["%.6f|%.6f|%.6f|%.6f|%d|%d" % [sim.match_time, sim.search_left, sim.hunt_time, sim.cooldown_ready_at, sim.kills, sim.tick]]
	for n: NpcState in sim.npcs:
		parts.append("%.5f,%.5f,%d" % [n.pos.x, n.pos.y, 1 if n.alive else 0])
	return ";".join(parts)


func _toggle(sim: MatchSim) -> void:
	var inp: PlayerInput = PlayerInput.new()
	inp.pause_pressed = true
	sim.step(inp)


func test_pause_freezes_search_and_hunt() -> bool:
	var sim: MatchSim = SimFixture.make(17, {"search_time": 3.0})
	SimFixture.run(sim, 1.0)
	_toggle(sim)
	check(sim.paused, "일시정지 진입")
	var before: String = _state(sim)
	SimFixture.run(sim, 5.0)
	eq(_state(sim), before, "1단계 일시정지 중 상태 변화 없음")
	_toggle(sim)
	SimFixture.run(sim, 10.0)
	eq(sim.phase, MatchSim.Phase.HUNT, "재개 후 2단계 진입")
	SimFixture.face_corner(sim)
	SimFixture.run(sim, 8.0)
	_toggle(sim)
	var before2: String = _state(sim)
	SimFixture.run(sim, 30.0)
	eq(_state(sim), before2, "2단계 일시정지 중 상태 변화 없음(제거·쿨다운 포함)")
	_toggle(sim)
	check(not sim.paused, "재개")
	return true
