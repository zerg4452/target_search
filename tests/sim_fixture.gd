class_name SimFixture
extends RefCounted
## 테스트 공용 도우미. 데이터는 한 번만 읽는다.

static var _store: DataStore


static func store() -> DataStore:
	if _store == null:
		_store = DataStore.load_default()
	return _store


static func make(seed_value: int, opts: Dictionary = {}) -> MatchSim:
	var o: Dictionary = opts.duplicate()
	o["seed"] = seed_value
	var sim: MatchSim = MatchSim.new(store(), o)
	sim.skip_intro()
	return sim


static func layout() -> ArenaLayout:
	return ArenaLayout.from_map(store().maps["atrium"], store().npc["spawn"])


static func idle_input() -> PlayerInput:
	return PlayerInput.new()


## 플레이어를 북서쪽 구석에 두고 벽을 보게 한다. 대부분의 NPC가 비관찰 상태가 된다.
static func face_corner(sim: MatchSim) -> void:
	sim.player_pos = Vector2(-21.0, -15.0)
	sim.yaw = deg_to_rad(45.0)   ## 북서쪽(-x, -z)
	sim.pitch = 0.0
	sim._update_camera()


## 시뮬레이션을 seconds초 돌린다. 매 틱 on_tick(sim)을 부른다(선택).
static func run(sim: MatchSim, seconds: float, on_tick: Callable = Callable()) -> void:
	var ticks: int = int(round(seconds / MatchSim.DT))
	for _i: int in ticks:
		var inp: PlayerInput = PlayerInput.new()
		sim.step(inp)
		if on_tick.is_valid():
			on_tick.call(sim)
		if sim.is_resolved():
			return
