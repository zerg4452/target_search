class_name MatchSim
extends RefCounted
## 한 판의 규칙 시뮬레이션(§3·§5·§7·§8). 씬과 분리되어 헤드리스 검사에서 그대로 돌린다.
## 틱 순서(§13.4): 입력 → 플레이어·카메라 → 가시성 → NPC 두뇌·이동 → 지목 → 제거 → 패배 판정 → 시간·힌트.
## 규칙 상태는 이 객체만 바꾼다. 표시 쪽은 events와 공개 필드를 읽기만 한다.

enum Phase { BRIEFING, DROP, SEARCH, HUNT, REVEAL, RESULTS }
enum Hunter { DISGUISE, STALK, STRIKE, EXIT }

const DT: float = 1.0 / 60.0
const BRIEFING_S: float = 8.0
const BRIEFING_SKIP_AFTER_S: float = 3.0
const DROP_S: float = 3.0
const REVEAL_S: float = 3.5
const VIS_SLOTS: int = 6            ## 60 Hz / 10 Hz
const NPC_SEPARATION: float = 0.6   ## 두 NPC 중심 사이 최소 거리
const ARRIVE_EPS: float = 0.12
const PHASE_NAMES: Array[String] = ["BRIEFING", "DROP", "SEARCH", "HUNT", "REVEAL", "RESULTS"]
const HUNTER_NAMES: Array[String] = ["DISGUISE", "STALK", "STRIKE", "EXIT"]

var store: DataStore
var setup: MatchSetup
var layout: ArenaLayout
var preset: Dictionary
var match_seed: int = 0
var npc_t: Dictionary
var hunt_t: Dictionary
var player_t: Dictionary
var vis_t: Dictionary
var wrong_t: Dictionary
var hint_t: Dictionary

var phase: int = Phase.BRIEFING
var paused: bool = false
var phase_time: float = 0.0
var match_time: float = 0.0
var search_left: float = 0.0
var hunt_time: float = 0.0
var tick: int = 0

var npcs: Array[NpcState] = []
var target: NpcState

# 플레이어
var player_pos: Vector2 = Vector2.ZERO
var player_facing: Vector2 = Vector2(0.0, -1.0)
var player_speed_mult: float = 1.0
var player_move_speed: float = 0.0   ## 표시용: 직전 틱에 실제로 움직인 속도(m/s). 애니메이션만 읽는다
var player_radius: float = 0.35
var camera: SimCamera = SimCamera.new()
var yaw: float = 0.0
var pitch: float = deg_to_rad(-12.0)
var observe_blend: float = 0.0
var observing: bool = false

# 지목·상호작용
var accusations_left: int = 0
var wrongs: int = 0
var lock_until: float = -1.0
var hold_id: int = -1
var hold_time: float = 0.0
var aim_id: int = -1
var call_ready_at: float = 0.0

# 사냥
var kills: int = 0
var cooldown_ready_at: float = 0.0   ## hunt_time 기준
var next_hint_at: float = 0.0
var h_state: int = Hunter.DISGUISE
var victim_id: int = -1
var victim_track_start: float = 0.0
var reselect_left: float = 0.0
var strike_elapsed: float = 0.0
var exit_active: bool = false
var hunt_rng: RandomNumberGenerator
var traces: Array[Dictionary] = []
var drought_time: float = 0.0        ## 쿨다운이 끝났는데 제거하지 못한 누적 시간(§7.8)

# 계측(§14.4). 규칙에는 쓰지 않는다.
var hints_shown: int = 0
var kill_times: Array[float] = []    ## 제거 시각(HUNT 경과 초)
var observe_time: float = 0.0
var play_time: float = 0.0
var calls: int = 0
var fov_base: float = 65.0

# 군중 가속(§7.9): 2단계에서 남은 일반 NPC가 절반 이하가 되면, 한 명 줄 때마다 모든 NPC의 걷는 속도가 오른다.
var crowd_speed_mult: float = 1.0
var normals_start: int = 0
var preset_id: String = ""

var result: Dictionary = {}
var events: Array[Dictionary] = []


func _init(p_store: DataStore, opts: Dictionary = {}) -> void:
	store = p_store
	preset_id = String(opts.get("preset", "standard"))
	var map_id: String = String(opts.get("map", "atrium"))
	match_seed = int(opts.get("seed", 1))
	preset = store.preset(preset_id)
	npc_t = store.npc
	hunt_t = store.hunt
	player_t = store.player
	vis_t = store.visibility
	wrong_t = store.difficulty["wrong_accusation"]
	hint_t = store.difficulty["hints"]
	layout = ArenaLayout.from_map(store.maps[map_id], npc_t["spawn"])
	setup = MatchSetup.build(store, layout, preset_id, map_id, match_seed, String(opts.get("variant", "")), opts.get("recent_variants", []) as Array)
	## FOV 옵션(§11.4). 관찰 판정도 이 값을 그대로 쓴다.
	fov_base = float(opts.get("fov_deg", player_t["camera"]["fov_deg"]))
	search_left = float(opts.get("search_time", -1.0))
	if search_left < 0.0:
		search_left = float(preset["search_time_s"])
	accusations_left = int(preset["accusations"])
	player_pos = layout.player_spawn
	player_radius = float(player_t["capsule"]["radius_m"])
	hunt_rng = RngUtil.make(match_seed, "hunt")
	var idle_range: Array = npc_t["idle_s"]
	for i: int in setup.npc_types.size():
		var n: NpcState = NpcState.new()
		n.id = i
		n.type_id = setup.npc_types[i]
		n.is_target = i == setup.target_index
		n.pos = setup.spawn_positions[i]
		n.rng = RngUtil.make(match_seed, "wander:%d" % i)
		n.facing = Vector2.from_angle(n.rng.randf() * TAU)
		n.idle_left = n.rng.randf_range(float(idle_range[0]), float(idle_range[1]))
		npcs.append(n)
		if not n.is_target:
			normals_start += 1
		if n.is_target:
			target = n
	_update_camera()


# ================================================================ 공개 API

func step(inp: PlayerInput) -> void:
	events.clear()
	if inp.pause_pressed and (phase == Phase.SEARCH or phase == Phase.HUNT):
		paused = not paused
		_emit({"type": "pause_changed", "paused": paused})
	if paused:
		return
	tick += 1
	match phase:
		Phase.BRIEFING:
			phase_time += DT
			_look(inp)
			if phase_time >= BRIEFING_S or (inp.skip_pressed and phase_time >= BRIEFING_SKIP_AFTER_S):
				_set_phase(Phase.DROP)
		Phase.DROP:
			phase_time += DT
			_look(inp)
			if phase_time >= DROP_S:
				_set_phase(Phase.SEARCH)
		Phase.SEARCH, Phase.HUNT:
			_play_tick(inp)
		Phase.REVEAL:
			phase_time += DT
			if phase_time >= REVEAL_S:
				_set_phase(Phase.RESULTS)
		Phase.RESULTS:
			pass


func skip_intro() -> void:
	if phase == Phase.BRIEFING or phase == Phase.DROP:
		_set_phase(Phase.SEARCH)


func is_observed(n: NpcState) -> bool:
	return match_time - n.last_observed_time < float(vis_t["memory_s"])


## 지금 모든 NPC(관찰되는 동안의 타겟 포함)가 쓰는 걷기 속도.
func crowd_walk_speed() -> float:
	return float(npc_t["walk_speed_mps"]) * crowd_speed_mult


## 군중 가속 배율(§7.9). 이 난이도에 기믹이 없거나 아직 절반보다 많이 남았으면 1.
func crowd_mult_for(remaining: int) -> float:
	var cfg: Dictionary = preset.get("crowd_speedup", {})
	if not bool(cfg.get("enabled", false)):
		return 1.0
	var half: int = int(floor(float(normals_start) * float(cfg.get("start_ratio", 0.5))))
	if remaining > half:
		return 1.0
	var steps: int = half - remaining + 1
	return minf(float(cfg.get("max_mult", 1.0)), 1.0 + float(cfg.get("per_step", 0.0)) * steps)


func _update_crowd_speed() -> void:
	if phase != Phase.HUNT:
		return
	var m: float = crowd_mult_for(normals_alive())
	if not is_equal_approx(m, crowd_speed_mult):
		var first: bool = is_equal_approx(crowd_speed_mult, 1.0)
		crowd_speed_mult = m
		_emit({"type": "crowd_speed_changed", "multiplier": m, "first": first, "remaining": normals_alive()})


func normals_alive() -> int:
	var c: int = 0
	for n: NpcState in npcs:
		if n.alive and not n.is_target:
			c += 1
	return c


func is_resolved() -> bool:
	return not result.is_empty()


func kill_interval(k: int) -> float:
	var ki: Dictionary = preset["kill_interval"]
	return maxf(float(ki["min_s"]), float(ki["start_s"]) - float(ki["step_s"]) * k)


func distance_band(dist: float) -> int:
	var edges: Array = hint_t["distance_band_edges_m"]
	for i: int in edges.size():
		if dist < float(edges[i]):
			return i
	return edges.size()


func phase_name() -> String:
	return PHASE_NAMES[phase]


func hunter_name() -> String:
	return HUNTER_NAMES[h_state]


# ---------------------------------------------------------------- 디버그·테스트 훅

func debug_force_hunt() -> void:
	if phase == Phase.SEARCH:
		search_left = 0.0


func debug_hint_now() -> void:
	if phase == Phase.HUNT:
		next_hint_at = hunt_time


## 판을 바로 끝낸다(디버그 스크린샷 전용). outcome: WIN | LOSE_ALL_GONE | LOSE_NO_CHANCES
func debug_end(outcome: String) -> void:
	if is_resolved() or (phase != Phase.SEARCH and phase != Phase.HUNT):
		return
	if outcome == "WIN":
		_emit({"type": "accusation_resolved", "npc": target.id, "correct": true})
	elif outcome == "LOSE_ALL_GONE":
		for n: NpcState in npcs:
			if not n.is_target:
				n.alive = false
	_end(outcome)


## 규칙 검사를 거치지 않는 즉시 제거. 테스트(T-07, T-08)와 디버그 전용.
func debug_eliminate(id: int) -> void:
	var n: NpcState = npcs[id]
	if n.alive and not n.is_target:
		n.alive = false


# ================================================================ 한 틱

func _play_tick(inp: PlayerInput) -> void:
	match_time += DT
	play_time += DT
	if observing:
		observe_time += DT
	# 2) 플레이어·카메라
	_look(inp)
	var before: Vector2 = player_pos
	_move_player(inp)
	player_move_speed = player_pos.distance_to(before) / DT
	_update_camera()
	# 3) 가시성(10 Hz 분할, 타겟은 매 틱)
	_update_visibility()
	# 4) NPC 두뇌·이동
	for n: NpcState in npcs:
		if not n.alive:
			continue
		if n.is_target and phase == Phase.HUNT:
			_hunter_brain(n)
		else:
			n.speed = crowd_walk_speed()
			_wander_brain(n)
	_integrate_npcs()
	# 5) 상호작용·지목
	aim_id = inp.aim_override if inp.aim_override >= 0 else _compute_aim()
	if inp.interact_pressed:
		_interact()
	_accusation(inp)
	# 6) 제거
	if not is_resolved():
		_hunt_elimination()
	# 7) 패배 판정
	if not is_resolved():
		if normals_alive() == 0:
			_end("LOSE_ALL_GONE")
		elif accusations_left <= 0:
			_end("LOSE_NO_CHANCES")
	# 8) 시간·힌트
	if is_resolved():
		return
	if phase == Phase.SEARCH:
		search_left -= DT
		if search_left <= 0.0:
			search_left = 0.0
			_enter_hunt()
	else:
		hunt_time += DT
		if hunt_time + 0.000001 >= next_hint_at:
			_show_hint()
			next_hint_at += float(hint_t["interval_s"])


func _set_phase(p: int) -> void:
	var old: int = phase
	phase = p
	phase_time = 0.0
	_emit({"type": "phase_changed", "from": PHASE_NAMES[old], "to": PHASE_NAMES[p]})


func _enter_hunt() -> void:
	_set_phase(Phase.HUNT)
	hunt_time = 0.0
	cooldown_ready_at = float(preset["first_kill_delay_s"])
	next_hint_at = float(hint_t["first_after_hunt_s"])
	h_state = Hunter.DISGUISE


func _emit(e: Dictionary) -> void:
	e["tick"] = tick
	e["match_time"] = match_time
	events.append(e)


# ================================================================ 플레이어·카메라

func _look(inp: PlayerInput) -> void:
	var cam: Dictionary = player_t["camera"]
	var pr: Array = cam["pitch_deg"]
	yaw = wrapf(yaw + inp.look_delta.x, -PI, PI)
	pitch = clampf(pitch + inp.look_delta.y, deg_to_rad(float(pr[0])), deg_to_rad(float(pr[1])))
	observing = inp.observe and (phase == Phase.SEARCH or phase == Phase.HUNT)
	var rate: float = DT / float(cam["observe"]["transition_s"])
	observe_blend = clampf(observe_blend + (rate if observing else -rate), 0.0, 1.0)


func ground_forward() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


func ground_right() -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))


func _move_player(inp: PlayerInput) -> void:
	var m: Vector2 = inp.move
	if m.length() > 1.0:
		m = m.normalized()
	if m == Vector2.ZERO:
		return
	var dir: Vector2 = ground_right() * m.x + ground_forward() * m.y
	var spd: float = float(player_t["walk_speed_mps"])
	if observing:
		spd = float(player_t["observe_speed_mps"])
	elif inp.run:
		spd = float(player_t["run_speed_mps"])
	var p: Vector2 = player_pos + dir * spd * player_speed_mult * DT
	# NPC를 밀지 않는다. 플레이어만 밀려난다.
	var min_d: float = player_radius + float(npc_t["capsule_radius_m"])
	for n: NpcState in npcs:
		if n.alive:
			var off: Vector2 = p - n.pos
			var d: float = off.length()
			if d < min_d and d > 0.0001:
				p = n.pos + off / d * min_d
	player_pos = layout.resolve_circle(p, player_radius)
	player_facing = dir.normalized()


func _update_camera() -> void:
	var cam: Dictionary = player_t["camera"]
	var obs: Dictionary = cam["observe"]
	var arm: float = lerpf(float(cam["arm_length_m"]), float(obs["arm_length_m"]), observe_blend)
	var shoulder: float = lerpf(float(cam["shoulder_offset_m"]), float(obs["shoulder_offset_m"]), observe_blend)
	var pivot: Vector3 = Vector3(player_pos.x, float(cam["pivot_height_m"]), player_pos.y)
	var b: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var desired: Vector3 = pivot + b * Vector3(shoulder, 0.0, arm)
	var length: float = pivot.distance_to(desired)
	var frac: float = layout.first_hit_fraction(pivot, desired)
	var keep: float = 1.0 if frac >= 1.0 else maxf(0.0, frac - 0.2 / length)
	camera.eye = pivot.lerp(desired, keep)
	camera.basis = b
	camera.fov_deg = lerpf(fov_base, float(obs["fov_deg"]), observe_blend)
	camera.body_pos = Vector3(player_pos.x, 0.0, player_pos.y)


# ================================================================ 가시성

func _update_visibility() -> void:
	var slot: int = tick % VIS_SLOTS
	for n: NpcState in npcs:
		if n.alive and (n.is_target or n.id == victim_id or n.id % VIS_SLOTS == slot):
			_refresh_obs(n)


func _refresh_obs(n: NpcState) -> void:
	n.observed_now = Visibility.observed_now(n.pos, camera, layout, vis_t)
	if n.observed_now:
		n.last_observed_time = match_time


# ================================================================ 배회(§5.3) — 타겟도 1단계에서 같은 코드

func _wander_brain(n: NpcState) -> void:
	match n.mode:
		NpcState.Mode.CALLED:
			_called(n)
		NpcState.Mode.IDLE:
			n.idle_left -= DT
			n.stat_idle_time += DT
			if n.idle_left <= 0.0:
				_pick_wander(n)


func _pick_wander(n: NpcState) -> void:
	var dist_range: Array = npc_t["wander_distance_m"]
	for _try: int in 8:
		var ang: float = n.rng.randf() * TAU
		var dist: float = n.rng.randf_range(float(dist_range[0]), float(dist_range[1]))
		var p: Vector2 = n.pos + Vector2.from_angle(ang) * dist
		p.x = clampf(p.x, layout.min_x + 1.0, layout.max_x - 1.0)
		p.y = clampf(p.y, layout.min_z + 1.0, layout.max_z - 1.0)
		var path: PackedVector2Array = layout.find_path(n.pos, layout.nearest_walkable(p))
		if not path.is_empty() and n.pos.distance_to(path[path.size() - 1]) > 1.0:
			_set_path(n, path)
			n.stat_legs += 1
			n.stat_leg_distance += layout.path_length(n.pos, path)
			return
	_start_idle(n)


func _set_path(n: NpcState, path: PackedVector2Array) -> void:
	n.path = path
	n.path_index = 0
	n.mode = NpcState.Mode.MOVING
	n.stuck_time = 0.0


func _start_idle(n: NpcState) -> void:
	var idle_range: Array = npc_t["idle_s"]
	n.mode = NpcState.Mode.IDLE
	n.path = PackedVector2Array()
	n.idle_left = n.rng.randf_range(float(idle_range[0]), float(idle_range[1]))
	n.look_around = n.rng.randf() < float(npc_t["look_around_chance"])


func _called(n: NpcState) -> void:
	var call_cfg: Dictionary = npc_t["call"]
	var turn_s: float = float(call_cfg["turn_s"])
	n.call_elapsed += DT
	var t: float = clampf(n.call_elapsed / turn_s, 0.0, 1.0)
	n.facing = n.call_from.slerp(n.call_to, t).normalized()
	if n.call_elapsed >= turn_s + float(call_cfg["hold_s"]):
		n.mode = NpcState.Mode.IDLE
		n.idle_left = 0.0   ## 다음 틱에 배회를 다시 시작한다


func _call_npc(n: NpcState) -> void:
	n.mode = NpcState.Mode.CALLED
	n.path = PackedVector2Array()
	n.call_elapsed = 0.0
	n.call_from = n.facing
	var to_player: Vector2 = player_pos - n.pos
	n.call_to = to_player.normalized() if to_player.length() > 0.001 else n.facing
	if n.is_target and h_state == Hunter.STRIKE:
		h_state = Hunter.DISGUISE
		strike_elapsed = 0.0


# ================================================================ 사냥(§7.2)

func _hunter_brain(n: NpcState) -> void:
	if n.mode == NpcState.Mode.CALLED:
		_called(n)
		n.speed = 0.0
		return
	if is_observed(n):
		## 위장: 일반 NPC와 같은 배회. 이미 정한 목적지(고정점)는 그대로 걸어간다.
		if h_state == Hunter.STRIKE:
			strike_elapsed = 0.0
		h_state = Hunter.DISGUISE
		n.speed = crowd_walk_speed()
		if n.mode == NpcState.Mode.IDLE:
			n.idle_left -= DT
			n.stat_idle_time += DT
			if n.idle_left <= 0.0:
				_pick_hunter_wander(n)
		return
	var fast: float = maxf(float(hunt_t["unobserved_speed_mps"]), crowd_walk_speed())
	if h_state == Hunter.STRIKE:
		## 피해자 곁에 붙어 따라간다.
		var v: NpcState = npcs[victim_id]
		n.speed = fast
		if n.pos.distance_to(v.pos) > 0.5:
			_set_path(n, PackedVector2Array([v.pos]))
		else:
			n.path = PackedVector2Array()
			n.mode = NpcState.Mode.IDLE
			n.idle_left = 1.0
		return
	if exit_active:
		h_state = Hunter.EXIT
		n.speed = fast
		if n.mode != NpcState.Mode.MOVING:
			exit_active = false
		return
	h_state = Hunter.STALK
	n.speed = fast
	reselect_left -= DT
	if reselect_left <= 0.0:
		reselect_left = float(hunt_t["victim_reselect_s"])
		_select_victim(n)
		if victim_id >= 0:
			var path: PackedVector2Array = layout.find_path(n.pos, npcs[victim_id].pos)
			if not path.is_empty():
				_set_path(n, path)
		elif n.mode != NpcState.Mode.MOVING and not layout.hide_points.is_empty():
			var hp: Vector2 = layout.hide_points[hunt_rng.randi_range(0, layout.hide_points.size() - 1)]
			var path2: PackedVector2Array = layout.find_path(n.pos, hp)
			if not path2.is_empty():
				_set_path(n, path2)


## 2단계에서 관찰되는 동안의 타겟: 걷는 속도·멈춤은 일반 배회와 같고, 목적지만 화면 밖 차폐 구역 쪽에서 고른다.
func _pick_hunter_wander(n: NpcState) -> void:
	var dist_range: Array = npc_t["wander_distance_m"]
	var best: Vector2 = Vector2.INF
	var best_d: float = INF
	for hp: Vector2 in layout.hide_points:
		var d: float = hp.distance_to(n.pos)
		if d < float(dist_range[0]) or d > float(dist_range[1]) * 1.5:
			continue
		if Visibility.observed_now(hp, camera, layout, vis_t):
			continue
		if d < best_d:
			best_d = d
			best = hp
	if best == Vector2.INF:
		_pick_wander(n)
		return
	var path: PackedVector2Array = layout.find_path(n.pos, best)
	if path.is_empty():
		_pick_wander(n)
		return
	_set_path(n, path)
	n.stat_legs += 1
	n.stat_leg_distance += layout.path_length(n.pos, path)


## 피해자는 유효한 동안(살아 있고 비관찰) 바꾸지 않는다. 자주 바꾸면 '1초 비관찰' 추적이 계속 초기화된다.
## 새로 고를 때는 경로 거리 15 m 안에서 가장 가까운 NPC를 우선하고, 없으면 거리와 관계없이 가장 가까운 NPC를 쫓는다.
func _select_victim(t: NpcState) -> void:
	if victim_id >= 0 and npcs[victim_id].alive and not is_observed(npcs[victim_id]):
		return
	var radius: float = float(hunt_t["victim_search_radius_m"])
	var cands: Array[NpcState] = []
	for n: NpcState in npcs:
		if n.alive and not n.is_target and not is_observed(n):
			cands.append(n)
	cands.sort_custom(func(a: NpcState, b: NpcState) -> bool: return a.pos.distance_squared_to(t.pos) < b.pos.distance_squared_to(t.pos))
	var best_id: int = -1
	var best_score: float = INF
	var best_len: float = INF
	for i: int in mini(cands.size(), 6):
		var len_i: float = layout.path_length(t.pos, layout.find_path(t.pos, cands[i].pos))
		## 계속 안 보일 것 같은 후보(플레이어 등 뒤, 차폐물 뒤)를 우선한다(§7.2 제안 보강, D-25).
		var score: float = len_i - _hidden_bonus(cands[i].pos)
		if score < best_score:
			best_score = score
			best_len = len_i
			best_id = cands[i].id
	if best_len > radius and not cands.is_empty():
		best_id = cands[0].id   ## 15 m 안에 없으면 직선상 가장 가까운 NPC
	if best_id != victim_id:
		victim_id = best_id
		victim_track_start = match_time


## 앞으로도 안 보일 가능성: 카메라 등 뒤면 +, 차폐물에 가리면 +. 단위는 경로 거리(m)로 환산한 가산점.
func _hidden_bonus(p: Vector2) -> float:
	var bonus: float = 0.0
	var to: Vector3 = Vector3(p.x, 1.2, p.y) - camera.eye
	var fwd: Vector3 = camera.forward()
	if Vector2(to.x, to.z).normalized().dot(Vector2(fwd.x, fwd.z).normalized()) < -0.2:
		bonus += float(hunt_t.get("victim_behind_bonus_m", 0.0))
	if layout.segment_blocked(camera.eye, Vector3(p.x, 1.2, p.y)):
		bonus += float(hunt_t.get("victim_occluded_bonus_m", 0.0))
	return bonus


func _hunt_elimination() -> void:
	if phase != Phase.HUNT:
		return
	var t: NpcState = target
	## 이동 뒤 위치로 타겟·피해자 관찰 상태를 다시 계산한다(검사 T-03과 같은 기준).
	_refresh_obs(t)
	var ready: bool = hunt_time + 0.000001 >= cooldown_ready_at
	if victim_id < 0 or not npcs[victim_id].alive:
		victim_id = -1
		if h_state == Hunter.STRIKE:
			h_state = Hunter.STALK
		if ready:
			drought_time += DT
		return
	var v: NpcState = npcs[victim_id]
	_refresh_obs(v)
	var need: float = float(hunt_t["unobserved_before_kill_s"])
	var close: bool = t.pos.distance_to(v.pos) <= float(hunt_t["kill_range_m"])
	if h_state == Hunter.STRIKE:
		if is_observed(t) or is_observed(v) or not close or t.mode == NpcState.Mode.CALLED or v.mode == NpcState.Mode.CALLED:
			h_state = Hunter.STALK
			strike_elapsed = 0.0
			return
		strike_elapsed += DT
		if strike_elapsed + 0.000001 >= float(hunt_t["strike_s"]):
			apply_elimination(v.id)
		return
	if h_state == Hunter.STALK and ready and close and _unobserved_for(t, 0.0) >= need and _unobserved_for(v, victim_track_start) >= need:
		h_state = Hunter.STRIKE
		strike_elapsed = DT
		return
	if ready:
		drought_time += DT


func _unobserved_for(n: NpcState, track_start: float) -> float:
	return match_time - maxf(n.last_observed_time, track_start)


## 제거 확정. 실행 직전에 모든 조건을 다시 검사한다(§7.3). 성공하면 true.
func apply_elimination(id: int) -> bool:
	if phase != Phase.HUNT or is_resolved():
		return false
	var v: NpcState = npcs[id]
	var t: NpcState = target
	if not v.alive or v.is_target or id != victim_id:
		return false
	if Visibility.observed_now(v.pos, camera, layout, vis_t) or Visibility.observed_now(t.pos, camera, layout, vis_t):
		return false
	var need: float = float(hunt_t["unobserved_before_kill_s"]) - 0.000001
	if _unobserved_for(v, victim_track_start) < need or _unobserved_for(t, 0.0) < need:
		return false
	if hunt_time + 0.000001 < cooldown_ready_at:
		return false
	if t.pos.distance_to(v.pos) > float(hunt_t["kill_range_m"]) + 0.05:
		return false
	v.alive = false
	kills += 1
	kill_times.append(hunt_time)
	cooldown_ready_at = hunt_time + kill_interval(kills)
	var exit_path: PackedVector2Array = _plan_exit(t)
	var trace: Dictionary = {
		"victim": v.id,
		"type_id": v.type_id,
		"pos": v.pos,
		"time": match_time,
		"footprints": _footprints(v.pos, exit_path),
	}
	traces.append(trace)
	_emit({"type": "npc_eliminated", "victim": v.id, "by": t.id, "pos": v.pos, "hunt_time": hunt_time, "kills": kills, "trace": trace})
	_update_crowd_speed()
	victim_id = -1
	h_state = Hunter.EXIT
	strike_elapsed = 0.0
	if not exit_path.is_empty():
		_set_path(t, exit_path)
		exit_active = true
	return true


func _plan_exit(t: NpcState) -> PackedVector2Array:
	var cr: float = float(hunt_t["cluster_radius_m"])
	var need: int = int(hunt_t["cluster_min_npcs"])
	var best: Vector2 = Vector2.INF
	var best_d: float = INF
	for a: NpcState in npcs:
		if not a.alive or a.is_target:
			continue
		var cnt: int = 0
		for b: NpcState in npcs:
			if b != a and b.alive and not b.is_target and a.pos.distance_to(b.pos) <= cr:
				cnt += 1
		if cnt >= need - 1:
			var d: float = a.pos.distance_to(t.pos)
			if d < best_d and d > 0.5:
				best_d = d
				best = a.pos
	var dir: Vector2 = (best - t.pos).normalized() if best_d < INF else Vector2.from_angle(hunt_rng.randf() * TAU)
	var er: Array = hunt_t["exit_distance_m"]
	var dist: float = hunt_rng.randf_range(float(er[0]), float(er[1]))
	var goal: Vector2 = t.pos + dir * dist
	goal.x = clampf(goal.x, layout.min_x + 1.0, layout.max_x - 1.0)
	goal.y = clampf(goal.y, layout.min_z + 1.0, layout.max_z - 1.0)
	return layout.find_path(t.pos, layout.nearest_walkable(goal))


func _footprints(start: Vector2, path: PackedVector2Array) -> Array[Vector2]:
	var tr: Dictionary = hunt_t["trace"]
	var spacing: float = float(tr["footprint_spacing_m"])
	var count: int = int(tr["footprints"])
	var out: Array[Vector2] = []
	var prev: Vector2 = start
	var walked: float = 0.0
	var next_at: float = spacing
	for p: Vector2 in path:
		var seg: float = prev.distance_to(p)
		while seg > 0.0001 and walked + seg >= next_at and out.size() < count:
			out.append(prev.lerp(p, (next_at - walked) / seg))
			next_at += spacing
		walked += seg
		prev = p
		if out.size() >= count:
			break
	return out


func _show_hint() -> void:
	var dist: float = player_pos.distance_to(target.pos)
	hints_shown += 1
	_emit({"type": "hint_shown", "distance": dist, "band": distance_band(dist), "duration_s": float(hint_t["display_s"]), "hunt_time": hunt_time})


# ================================================================ 이동 적분

func _integrate_npcs() -> void:
	var r: float = float(npc_t["capsule_radius_m"])
	var turn: float = deg_to_rad(float(npc_t["turn_speed_dps"])) * DT
	var starts: PackedVector2Array = []
	for n0: NpcState in npcs:
		starts.append(n0.pos)
	for n: NpcState in npcs:
		if not n.alive or n.mode != NpcState.Mode.MOVING:
			continue
		if n.path_index >= n.path.size():
			_arrive(n)
			continue
		var goal: Vector2 = n.path[n.path_index]
		var to: Vector2 = goal - n.pos
		var d: float = to.length()
		if d < ARRIVE_EPS:
			n.path_index += 1
			if n.path_index >= n.path.size():
				_arrive(n)
			continue
		var vel: Vector2 = to / d * n.speed
		var step_len: float = minf(n.speed * DT, d)
		var before: Vector2 = n.pos
		var p: Vector2 = n.pos + vel.normalized() * step_len
		n.pos = layout.resolve_circle(p, r)
		var moved: float = before.distance_to(n.pos)
		n.stat_moving_time += DT
		n.stat_distance += moved
		# 바라보는 방향: 초당 240°로 진행 방향을 따라간다.
		var want: float = vel.angle()
		var cur: float = n.facing.angle()
		n.facing = Vector2.from_angle(cur + clampf(angle_difference(cur, want), -turn, turn))
	_separate()
	_check_stuck(starts)


## 끼임: 밀어내기까지 끝난 뒤의 실제 이동량이 기대치의 30% 미만인 상태가 1.5초 이어지면 다시 정한다.
func _check_stuck(starts: PackedVector2Array) -> void:
	var repath_s: float = float(npc_t["stuck"]["repath_s"])
	for n: NpcState in npcs:
		if not n.alive or n.mode != NpcState.Mode.MOVING:
			n.stuck_time = 0.0
			continue
		if n.pos.distance_to(starts[n.id]) >= 0.3 * n.speed * DT:
			n.stuck_time = 0.0
			continue
		n.stuck_time += DT
		if n.stuck_time < repath_s:
			continue
		n.stuck_time = 0.0
		if n.is_target and phase == Phase.HUNT:
			reselect_left = 0.0
			_start_idle(n)
			n.idle_left = 0.0
		else:
			_pick_wander(n)


func _arrive(n: NpcState) -> void:
	_start_idle(n)


## 겹친 NPC를 서로 밀어내고, 플레이어와 겹친 NPC는 NPC만 밀어낸다.
func _separate() -> void:
	var r: float = float(npc_t["capsule_radius_m"])
	var min_pl: float = r + player_radius
	for i: int in npcs.size():
		var a: NpcState = npcs[i]
		if not a.alive:
			continue
		for j: int in range(i + 1, npcs.size()):
			var b: NpcState = npcs[j]
			if not b.alive:
				continue
			var off: Vector2 = b.pos - a.pos
			var d: float = off.length()
			if d < NPC_SEPARATION:
				var dir: Vector2 = off / d if d > 0.0001 else Vector2.RIGHT
				var push: float = (NPC_SEPARATION - d) * 0.5
				a.pos = layout.resolve_circle(a.pos - dir * push, r)
				b.pos = layout.resolve_circle(b.pos + dir * push, r)
		var offp: Vector2 = a.pos - player_pos
		var dp: float = offp.length()
		if dp < min_pl:
			var dirp: Vector2 = offp / dp if dp > 0.0001 else Vector2.RIGHT
			a.pos = layout.resolve_circle(player_pos + dirp * min_pl, r)


# ================================================================ 조준·상호작용·지목(§4.4, §8)

## 화면 중앙 광선(반지름 0.25 m 구체)에 처음 맞는 살아 있는 NPC. 구조물에 가리면 없음.
func _compute_aim() -> int:
	var inter: Dictionary = player_t["interaction"]
	var rad: float = float(npc_t["capsule_radius_m"]) + float(inter["aim_sphere_radius_m"])
	var height: float = float(npc_t["height_m"]) + float(inter["aim_sphere_radius_m"])
	var origin: Vector3 = camera.eye
	var dir: Vector3 = camera.forward()
	var best_t: float = INF
	var best_id: int = -1
	for n: NpcState in npcs:
		if not n.alive:
			continue
		var t_hit: float = _ray_cylinder(origin, dir, n.pos, rad, height)
		if t_hit >= 0.0 and t_hit < best_t:
			best_t = t_hit
			best_id = n.id
	if best_id < 0:
		return -1
	var hit_point: Vector3 = origin + dir * best_t
	for o: ArenaObstacle in layout.obstacles:
		if o.segment_fraction(origin, hit_point) >= 0.0:
			return -1
	return best_id


static func _ray_cylinder(o: Vector3, d: Vector3, c: Vector2, r: float, h: float) -> float:
	var d2: Vector2 = Vector2(d.x, d.z)
	var f: Vector2 = Vector2(o.x - c.x, o.z - c.y)
	var a: float = d2.dot(d2)
	if a < 0.000001:
		return -1.0
	var b: float = 2.0 * f.dot(d2)
	var cc: float = f.dot(f) - r * r
	var disc: float = b * b - 4.0 * a * cc
	if disc < 0.0:
		return -1.0
	var s: float = sqrt(disc)
	for t: float in [(-b - s) / (2.0 * a), (-b + s) / (2.0 * a)]:
		if t >= 0.0 and t <= 60.0:
			var y: float = o.y + d.y * t
			if y >= 0.0 and y <= h:
				return t
	return -1.0


func aim_distance() -> float:
	return player_pos.distance_to(npcs[aim_id].pos) if aim_id >= 0 else INF


func _interact() -> void:
	var inter: Dictionary = player_t["interaction"]
	if aim_id >= 0 and aim_distance() <= float(inter["call_range_m"]):
		if match_time >= call_ready_at:
			call_ready_at = match_time + float(inter["call_cooldown_s"])
			_call_npc(npcs[aim_id])
			calls += 1
			_emit({"type": "npc_called", "npc": aim_id})
		return
	var best: Dictionary = {}
	var best_d: float = float(inter["trace_inspect_range_m"])
	for tr: Dictionary in traces:
		var d: float = player_pos.distance_to(tr["pos"] as Vector2)
		if d <= best_d:
			best_d = d
			best = tr
	if not best.is_empty():
		var age: float = match_time - float(best["time"])
		var step_s: float = float(hunt_t["trace"]["inspect_round_s"])
		_emit({"type": "trace_inspected", "age_s": age, "rounded_s": int(round(age / step_s) * step_s), "over_minute": age > 60.0})


func _accusation(inp: PlayerInput) -> void:
	var inter: Dictionary = player_t["interaction"]
	var locked: bool = match_time < lock_until
	var valid: bool = inp.accuse_held and not locked and aim_id >= 0 and aim_distance() <= float(inter["accuse_range_m"])
	if not valid:
		hold_id = -1
		hold_time = 0.0
		return
	if aim_id != hold_id:
		hold_id = aim_id
		hold_time = 0.0
	hold_time += DT
	if hold_time + 0.000001 < float(inter["accuse_hold_s"]):
		return
	var npc_id: int = hold_id
	hold_id = -1
	hold_time = 0.0
	if npcs[npc_id].is_target:
		_emit({"type": "accusation_resolved", "npc": npc_id, "correct": true})
		_end("WIN")
		return
	wrongs += 1
	accusations_left -= 1
	lock_until = match_time + float(wrong_t["lock_s"])
	player_speed_mult = 1.0 - minf(float(wrong_t["speed_penalty_max"]), float(wrong_t["speed_penalty_ratio"]) * wrongs)
	_emit({"type": "accusation_resolved", "npc": npc_id, "correct": false, "left": accusations_left})
	_emit({"type": "accusation_locked", "seconds": float(wrong_t["lock_s"])})
	_emit({"type": "player_speed_changed", "multiplier": player_speed_mult})


# ================================================================ 종료·점수(§8.3)

func _end(outcome: String) -> void:
	var found_in: String = PHASE_NAMES[phase]
	result = {
		"outcome": outcome,
		"win": outcome == "WIN",
		"found_in": found_in,
		"remaining": normals_alive(),
		"wrongs": wrongs,
		"match_time": match_time,
		"search_left": search_left,
		"seed": match_seed,
		"target": target.id,
		"target_type": target.type_id,
		"variant_id": setup.variant_id,
		"variant": setup.variant,
		"kills": kills,
		"drought_s": drought_time,
		"preset": preset_id,
		"fov_deg": fov_base,
		"hints_shown": hints_shown,
		"kill_times": kill_times.duplicate(),
		"observe_ratio": observe_time / maxf(play_time, 0.001),
		"calls": calls,
		"hunt_time": hunt_time,
		"crowd_speed_mult": crowd_speed_mult,
	}
	if outcome == "WIN":
		_score()
	_set_phase(Phase.REVEAL)
	_emit({"type": "match_ended", "result": result})


func _score() -> void:
	var sc: Dictionary = store.scoring
	var score: int = int(result["remaining"]) * int(sc["rescue_per_npc"])
	if result["found_in"] == "SEARCH":
		score += int(floor(search_left)) * int(sc["search_time_bonus_per_s"])
	var acc: Dictionary = sc["accuracy_bonus_by_wrong"]
	score += int(acc.get(str(wrongs), 0))
	result["score"] = score
	for g: Dictionary in sc["grades"]:
		if g.has("found_in") and (result["found_in"] != String(g["found_in"]) or wrongs > int(g.get("max_wrong", 99))):
			continue
		if int(result["remaining"]) >= int(g.get("min_remaining", 0)):
			result["grade"] = String(g["grade"])
			return
	result["grade"] = "C"
