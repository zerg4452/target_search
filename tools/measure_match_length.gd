extends SceneTree
## 한 판 길이 측정(§3.2, §14.4). 구석 시나리오(플레이어가 벽만 봄 = 제거가 가장 쉬운 경우)에서
## 난이도·시드별 전멸 시간을 출력한다. 사용: godot_console --headless --path . --script res://tools/measure_match_length.gd

var _done: bool = false


func _process(_d: float) -> bool:
	if _done:
		return false
	_done = true
	for combo: Array in [["standard", 42], ["standard", 1], ["standard", 2], ["standard", 3], ["practice", 1], ["practice", 2], ["hard", 1], ["hard", 2]]:
		var seed_value: int = combo[1]
		var sim: MatchSim = SimFixture.make(seed_value, {"preset": combo[0]})
		SimFixture.face_corner(sim)
		for _i: int in int(500.0 / MatchSim.DT):
			sim.step(PlayerInput.new())
			if sim.is_resolved():
				break
		var total: float = 11.0 + float(sim.preset["search_time_s"]) + sim.hunt_time
		print(combo[0] + " seed %d: %s kills=%d hunt=%.1f total=%.0f drought=%.1f" % [seed_value, sim.result.get("outcome", "-"), sim.kills, sim.hunt_time, total, sim.drought_time])
	quit(0)
	return false


