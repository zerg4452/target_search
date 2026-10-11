extends SceneTree
## 봇 플레이테스트(§14.4 보조 계측). 사람 플레이테스트를 대신하지 않는다. 한 판 길이(5분 상한)와 규칙 흐름을 수치로 확인한다.
##   roamer  : 찾지 못하는 플레이어. 아레나를 돌아다니며 무작위로 둘러본다(관찰 모드 30%). 패배까지의 판 길이 상한을 잰다.
##   searcher: 핵심 루프를 흉내 낸다. 가까운 손님에게 가서 호출하고, 둘레를 돌며 관찰 모드로 본 뒤 다음 손님으로 간다.
##             타겟을 변이가 보이는 방향·거리에서 (1 + 0.8 × 등급)초 이상 보면 알아채고 지목한다. 확인할 때마다 4% 확률로 오답 지목.
##             사람의 인지를 단순화한 모델이라 승률·발견 시간은 참고값이다.
## 사용: godot_console --headless --path . --script res://tools/bot_playtest.gd -- [--bot=roamer|searcher|both] [--seeds=8] [--presets=standard,practice,hard]

const OUT_JSON: String = "res://test_reports/m2/bot_playtest.json"
const OUT_MD: String = "res://test_reports/m2/bot_playtest.md"
const MAX_S: float = 420.0
const P_FALSE: float = 0.04

var _done: bool = false


func _process(_d: float) -> bool:
	if _done:
		return false
	_done = true
	var bots: PackedStringArray = ["roamer", "searcher"]
	var seeds: int = 8
	var presets: PackedStringArray = ["standard", "practice", "hard"]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--bot=") and a != "--bot=both":
			bots = [a.trim_prefix("--bot=")]
		elif a.begins_with("--seeds="):
			seeds = int(a.trim_prefix("--seeds="))
		elif a.begins_with("--presets="):
			presets = a.trim_prefix("--presets=").split(",")
	var rows: Array[Dictionary] = []
	var store: DataStore = DataStore.load_default()
	## 실험용 덮어쓰기: --set=hunt.unobserved_speed_mps=4.5 (데이터 파일은 바꾸지 않는다)
	for a2: String in OS.get_cmdline_user_args():
		if a2.begins_with("--set="):
			var kv: PackedStringArray = a2.trim_prefix("--set=").split("=")
			var path: PackedStringArray = kv[0].split(".")
			var d: Dictionary = store.get(path[0]) if path[0] != "preset" else store.preset(path[1])
			var start: int = 1 if path[0] != "preset" else 2
			for i2: int in range(start, path.size() - 1):
				d = d[path[i2]]
			d[path[path.size() - 1]] = float(kv[1])
			print("set %s = %s" % [kv[0], kv[1]])
	for bot: String in bots:
		for preset: String in presets:
			for i: int in seeds:
				var seed_value: int = 1000 + i * 37
				var r: Dictionary = _play(store, bot, preset, seed_value)
				rows.append(r)
				print("%-8s %-8s seed %5d  %-16s 길이 %5.0f초  남은 %2d  오답 %d  변이 %s(등급 %d)  기회 공백 %.0f초" % [bot, preset, seed_value, r["outcome"], r["total_s"], r["remaining"], r["wrongs"], r["variant_id"], r["grade"], r["drought_s"]])
	_write(rows)
	quit(0)
	return false


func _play(store: DataStore, bot: String, preset: String, seed_value: int) -> Dictionary:
	var sim: MatchSim = MatchSim.new(store, {"preset": preset, "seed": seed_value})
	sim.skip_intro()
	var rng: RandomNumberGenerator = RngUtil.make(seed_value, "bot:" + bot)
	var st: Dictionary = {"mode": "choose", "npc": -1, "until": 0.0, "goal": sim.player_pos, "next_turn": 0.0, "yaw": 0.0, "observe": false, "recog": 0.0, "visited": {}, "accuse": false, "orbit_dir": 1.0}
	var need_recog: float = 1.0 + 0.8 * float(sim.setup.variant.get("difficulty", 3))
	while not sim.is_resolved() and sim.match_time < MAX_S:
		var inp: PlayerInput = PlayerInput.new()
		if bot == "roamer":
			_roam(sim, rng, st, inp)
		else:
			_search(sim, rng, st, inp, need_recog)
		sim.step(inp)
	var total: float = DataStore.BRIEFING_AND_DROP_S + sim.match_time
	return {
		"bot": bot, "preset": preset, "seed": seed_value, "outcome": String(sim.result.get("outcome", "TIMEOUT")),
		"total_s": total, "match_s": sim.match_time, "hunt_s": sim.hunt_time, "remaining": sim.normals_alive(), "wrongs": sim.wrongs,
		"found_in": String(sim.result.get("found_in", "")), "variant_id": sim.setup.variant_id, "grade": int(sim.setup.variant.get("difficulty", 0)),
		"kills": sim.kills, "drought_s": sim.drought_time, "hints": sim.hints_shown, "observe_ratio": sim.observe_time / maxf(sim.play_time, 0.001), "calls": sim.calls,
	}


## 카메라를 목표 방향으로 돌리고, 목표 지점 쪽으로 걷는 입력.
func _steer(sim: MatchSim, inp: PlayerInput, goal: Vector2, look_at: Vector2, pitch_deg: float = -8.0) -> void:
	var d: Vector2 = look_at - sim.player_pos
	if d.length() > 0.05:
		var want_yaw: float = atan2(-d.x, -d.y)
		inp.look_delta = Vector2(clampf(angle_difference(sim.yaw, want_yaw), -0.12, 0.12), clampf(deg_to_rad(pitch_deg) - sim.pitch, -0.05, 0.05))
	var m: Vector2 = goal - sim.player_pos
	if m.length() > 0.3:
		m = m.normalized()
		inp.move = Vector2(m.dot(sim.ground_right()), m.dot(sim.ground_forward()))


func _roam(sim: MatchSim, rng: RandomNumberGenerator, st: Dictionary, inp: PlayerInput) -> void:
	if sim.player_pos.distance_to(st["goal"] as Vector2) < 1.0 or sim.match_time >= float(st["until"]):
		st["goal"] = sim.layout.nearest_walkable(Vector2(rng.randf_range(sim.layout.min_x + 2.0, sim.layout.max_x - 2.0), rng.randf_range(sim.layout.min_z + 2.0, sim.layout.max_z - 2.0)))
		st["until"] = sim.match_time + 12.0
	if sim.match_time >= float(st["next_turn"]):
		st["next_turn"] = sim.match_time + rng.randf_range(0.5, 2.0)
		st["yaw"] = rng.randf_range(-PI, PI)
		st["observe"] = rng.randf() < 0.3
	var g: Vector2 = st["goal"]
	var look: Vector2 = sim.player_pos + Vector2(-sin(float(st["yaw"])), -cos(float(st["yaw"]))) * 5.0
	_steer(sim, inp, g, look)
	inp.observe = bool(st["observe"])


## 변이가 보이는 방향인지(§6.5 visible_from). 타겟이 바라보는 방향과 타겟→플레이어 방향의 각도로 정한다.
static func _direction_ok(sim: MatchSim) -> bool:
	var v: Dictionary = sim.setup.variant
	if v.is_empty():
		return false
	var dirs: Array = v["visible_from"]
	if dirs.has("any"):
		return true
	var t: NpcState = sim.target
	var d: Vector2 = (sim.player_pos - t.pos).normalized()
	var f: Vector2 = t.facing.normalized()
	var right: Vector2 = Vector2(-f.y, f.x)
	var c: float = d.dot(f)
	if c > 0.5 and dirs.has("front"):
		return true
	if c < -0.5 and dirs.has("back"):
		return true
	if absf(c) <= 0.87:
		if d.dot(right) > 0.0 and dirs.has("right"):
			return true
		if d.dot(right) < 0.0 and dirs.has("left"):
			return true
	return dirs.has("top") and c > 0.3


func _search(sim: MatchSim, rng: RandomNumberGenerator, st: Dictionary, inp: PlayerInput, need_recog: float) -> void:
	var inter: Dictionary = sim.player_t["interaction"]
	var mode: String = st["mode"]
	var id: int = int(st["npc"])
	if id >= 0 and not sim.npcs[id].alive:
		mode = "choose"
	# 후보가 몇 명 안 남으면 사람은 알아채지 못해도 차례로 찍어 본다(남은 기회 안에서).
	var alive_all: Array[int] = []
	for n0: NpcState in sim.npcs:
		if n0.alive:
			alive_all.append(n0.id)
	if mode == "choose" and alive_all.size() <= 4 and sim.match_time >= sim.lock_until:
		var tried: Dictionary = st.get("tried", {})
		var pick: int = -1
		var pick_d: float = INF
		for aid: int in alive_all:
			if not tried.has(aid) and sim.npcs[aid].pos.distance_to(sim.player_pos) < pick_d:
				pick_d = sim.npcs[aid].pos.distance_to(sim.player_pos)
				pick = aid
		if pick >= 0:
			tried[pick] = true
			st["tried"] = tried
			st["npc"] = pick
			st["mode"] = "accuse"
			return
	if mode == "choose":
		var best: int = -1
		var best_d: float = INF
		for n: NpcState in sim.npcs:
			if not n.alive or (st["visited"] as Dictionary).has(n.id):
				continue
			var dd: float = n.pos.distance_to(sim.player_pos)
			if dd < best_d:
				best_d = dd
				best = n.id
		if best < 0:
			st["visited"] = {}   ## 한 바퀴 다 봤으면 기억을 비우고 다시 본다
			return
		st["npc"] = best
		st["recog"] = 0.0
		st["until"] = sim.match_time + 25.0
		st["orbit_dir"] = 1.0 if rng.randf() < 0.5 else -1.0
		mode = "approach"
		id = best
	var n2: NpcState = sim.npcs[id]
	var dist: float = n2.pos.distance_to(sim.player_pos)
	# 알아채기: 지금 보고 있는 손님이 타겟이고, 변이가 보이는 방향·거리 안에 있으면 시간이 쌓인다.
	if n2.is_target and sim.setup.variant.size() > 0:
		var arm: float = 1.8 if sim.observe_blend > 0.5 else 3.2
		var in_view: bool = sim.camera.is_in_expanded_view(Vector3(n2.pos.x, 1.2, n2.pos.y), 0.0)
		var grade: int = int(sim.setup.variant["difficulty"])
		var obs_ok: bool = grade <= 2 or sim.observe_blend > 0.5
		if in_view and obs_ok and dist + arm <= float(sim.setup.variant["identify_distance_m"]) and _direction_ok(sim):
			st["recog"] = float(st["recog"]) + MatchSim.DT
	match mode:
		"approach":
			_steer(sim, inp, n2.pos, n2.pos)
			if dist <= float(inter["call_range_m"]) - 0.4:
				inp.aim_override = id
				inp.interact_pressed = true
				mode = "orbit"
				st["until"] = sim.match_time + 3.2
			elif sim.match_time > float(st["until"]):
				(st["visited"] as Dictionary)[id] = true
				mode = "choose"
		"orbit":
			var ang: float = (sim.player_pos - n2.pos).angle() + float(st["orbit_dir"]) * 1.4 * MatchSim.DT * 2.0
			var goal: Vector2 = n2.pos + Vector2.from_angle(ang) * 2.0
			_steer(sim, inp, goal, n2.pos, -12.0)
			inp.observe = true
			inp.aim_override = id
			if float(st["recog"]) >= need_recog and n2.is_target:
				mode = "accuse"
			elif sim.match_time >= float(st["until"]):
				(st["visited"] as Dictionary)[id] = true
				if rng.randf() < P_FALSE and sim.match_time >= sim.lock_until:
					mode = "accuse"
				else:
					mode = "choose"
		"accuse":
			_steer(sim, inp, n2.pos, n2.pos)
			if dist <= float(inter["accuse_range_m"]) - 0.5:
				inp.aim_override = id
				inp.accuse_held = true
				if sim.hold_time + MatchSim.DT >= float(inter["accuse_hold_s"]):
					mode = "choose"
	st["mode"] = mode


func _write(rows: Array[Dictionary]) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_reports/m2"))
	var f: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT_JSON), FileAccess.WRITE)
	f.store_string(JSON.stringify({"generated": Time.get_datetime_string_from_system(), "rows": rows}, "  "))
	f.close()
	var groups: Dictionary = {}
	for r: Dictionary in rows:
		var key: String = "%s/%s" % [r["bot"], r["preset"]]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(r)
	var lines: PackedStringArray = ["# 봇 플레이테스트 요약", "", "생성 %s. 사람 플레이테스트가 아니다(§14.4 지표의 참고값)." % Time.get_datetime_string_from_system(), ""]
	lines.append("| 봇/난이도 | 판 | 승 | 1단계 발견 | 평균 길이 | 최장 | 5분 초과 | 평균 남은 사람(승) | 평균 오답 |")
	lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
	for key: String in groups:
		var g: Array = groups[key]
		var wins: int = 0
		var search_finds: int = 0
		var sum_len: float = 0.0
		var longest: float = 0.0
		var over: int = 0
		var rem: int = 0
		var wr: int = 0
		for r: Dictionary in g:
			sum_len += float(r["total_s"])
			longest = maxf(longest, float(r["total_s"]))
			if float(r["total_s"]) > 300.0:
				over += 1
			if String(r["outcome"]) == "WIN":
				wins += 1
				rem += int(r["remaining"])
				if String(r["found_in"]) == "SEARCH":
					search_finds += 1
			wr += int(r["wrongs"])
		lines.append("| %s | %d | %d | %d | %d:%02d | %d:%02d | %d | %s | %.1f |" % [key, g.size(), wins, search_finds, int(sum_len / g.size()) / 60, int(sum_len / g.size()) % 60, int(longest) / 60, int(longest) % 60, over, ("%.1f" % (float(rem) / wins)) if wins > 0 else "-", float(wr) / g.size()])
	var f2: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT_MD), FileAccess.WRITE)
	f2.store_string("\n".join(lines) + "\n")
	f2.close()
	print("\n".join(lines))
