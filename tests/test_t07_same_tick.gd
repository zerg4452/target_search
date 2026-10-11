extends TestCase
## T-07 (I-07): 같은 틱에서는 지목 → 제거 → 패배 순으로 판정한다.
## 실제 규칙에서는 타겟을 지목하려면 4 m 안(안전지대)에 있어야 하므로 같은 틱 충돌이 생기지 않는다.
## 여기서는 지목 사거리만 넓혀 순서 자체를 검사한다.


## 일반 NPC를 한 명만 남기고, 그 한 명을 제거하는 STRIKE가 다음 틱에 끝나도록 만든다.
func _prepare(seed_value: int) -> MatchSim:
	var sim: MatchSim = SimFixture.make(seed_value)
	SimFixture.run(sim, 2.0)   ## '1초 비관찰' 조건이 성립할 만큼 시간이 흐르게 한다
	sim.debug_force_hunt()
	sim.step(PlayerInput.new())
	var last: NpcState = null
	for n: NpcState in sim.npcs:
		if n.is_target:
			continue
		if last == null:
			last = n
		else:
			sim.debug_eliminate(n.id)
	var t: NpcState = sim.target
	t.pos = Vector2(-15.0, 9.0)
	last.pos = Vector2(-14.0, 9.0)
	for n2: NpcState in [t, last]:
		n2.mode = NpcState.Mode.IDLE
		n2.path = PackedVector2Array()
		n2.idle_left = 100.0
		n2.last_observed_time = -1000.0
	sim.player_pos = Vector2(15.0, -10.0)
	sim.yaw = deg_to_rad(-90.0)   ## 동쪽 벽을 본다
	sim._update_camera()
	sim.victim_id = last.id
	sim.victim_track_start = sim.match_time - 5.0
	sim.cooldown_ready_at = 0.0
	sim.h_state = MatchSim.Hunter.STRIKE
	sim.strike_elapsed = float(sim.hunt_t["strike_s"]) - MatchSim.DT * 0.5
	return sim


func test_strike_alone_kills_last_normal() -> bool:
	var sim: MatchSim = _prepare(31)
	sim.step(PlayerInput.new())
	eq(sim.kills, 1, "준비한 STRIKE가 이번 틱에 제거를 끝냄")
	eq(String(sim.result.get("outcome", "")), "LOSE_ALL_GONE", "마지막 일반 NPC가 사라지면 패배")
	return true


func test_accusation_resolves_before_elimination() -> bool:
	var sim: MatchSim = _prepare(31)
	sim.player_t = sim.player_t.duplicate(true)
	sim.player_t["interaction"]["accuse_range_m"] = 100.0
	sim.hold_id = sim.target.id
	sim.hold_time = float(sim.player_t["interaction"]["accuse_hold_s"]) - MatchSim.DT * 0.5
	var inp: PlayerInput = PlayerInput.new()
	inp.aim_override = sim.target.id
	inp.accuse_held = true
	sim.step(inp)
	eq(String(sim.result.get("outcome", "")), "WIN", "같은 틱이면 지목이 먼저")
	eq(sim.kills, 0, "승리가 확정된 틱에는 제거하지 않음")
	eq(sim.normals_alive(), 1, "마지막 일반 NPC가 살아 있음")
	return true
