class_name MatchView
extends Node3D
## 한 판의 3D 표시: 아레나, NPC 모델, 플레이어 모델, 카메라, 흔적, 정체 공개 연출(§8.4).
## MatchSim 상태를 읽고 이벤트를 받아 보여 주기만 한다. 카메라는 SimCamera를 그대로 따라간다(그려지는 범위 = 판정 범위).

const STEP_INTERVAL_S: float = 0.5   ## 발소리 박자. 이동 속도와 상관없이 같다(AudioDirector 참고).
const REVEAL_TURN_S: float = 1.4

var store: DataStore
var sim: MatchSim
var mats: MaterialCache
var settings: AppSettings
var audio: AudioDirector
var arena_visual: ArenaVisual
var npc_visuals: Array[NpcVisual] = []
var player_model: Node3D
var player_anim: AnimationPlayer
var cam: Camera3D
var debug_on: bool = false
var _trace_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _step_clock: Array[float] = []
var _last_player_pos: Vector2 = Vector2.ZERO
var _player_anim_name: String = ""
var _reveal_t: float = -1.0
var _reveal_outcome: String = ""
var _reveal_from_facing: Vector2 = Vector2.ZERO
var _reveal_overlay: StandardMaterial3D
var _lose_a_placed: bool = false


func build(p_store: DataStore, p_sim: MatchSim, p_mats: MaterialCache, p_settings: AppSettings, p_audio: AudioDirector) -> void:
	store = p_store
	sim = p_sim
	mats = p_mats
	settings = p_settings
	audio = p_audio
	arena_visual = ArenaVisual.new()
	add_child(arena_visual)
	arena_visual.build(sim.layout, store.maps[sim.setup.map_id])
	var vis_rng: RandomNumberGenerator = RngUtil.make(sim.match_seed, "visual_phase")
	for i: int in sim.npcs.size():
		var v: NpcVisual = NpcVisual.new()
		v.name = "Npc_%02d" % i
		v.npc_id = i
		add_child(v)
		v.build(sim.setup.appearances[i], store.type_scene(sim.setup.outfit_id, sim.npcs[i].type_id), mats, vis_rng.randf())
		npc_visuals.append(v)
		_step_clock.append(vis_rng.randf() * STEP_INTERVAL_S)
	player_model = Node3D.new()
	player_model.name = "Player"
	add_child(player_model)
	var ps: PackedScene = NpcModel.scene_for("res://assets/player/player.glb")
	if ps != null:
		var inst: Node = ps.instantiate()
		player_model.add_child(inst)
		player_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 150.0
	add_child(cam)
	cam.make_current()
	_trace_rng.seed = hash("%d:trace_visual" % sim.match_seed)
	_reveal_overlay = StandardMaterial3D.new()
	_reveal_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_reveal_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_reveal_overlay.albedo_color = Color(1.0, 0.85, 0.1, 0.6)
	_reveal_overlay.grow = true
	_reveal_overlay.grow_amount = 0.006
	_last_player_pos = sim.player_pos
	sync(0.0)


func on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"phase_changed":
			match String(e["to"]):
				"DROP":
					for v: NpcVisual in npc_visuals:
						v.play_once("land")
					if player_anim != null and player_anim.has_animation("land"):
						player_anim.play("land")
						_player_anim_name = "land"
				"HUNT":
					arena_visual.start_hunt_transition(settings.get_b("reduce_flashing"))
		"npc_called":
			var n: NpcState = sim.npcs[int(e["npc"])]
			audio.at("call_murmur", Vector3(n.pos.x, 1.5, n.pos.y), 12.0, -4.0)
		"accusation_resolved":
			if not bool(e["correct"]):
				npc_visuals[int(e["npc"])].play_once("wrong_accused")
		"npc_eliminated":
			var tv: TraceVisual = TraceVisual.new()
			add_child(tv)
			var trace: Dictionary = e["trace"]
			var tid: String = String(trace["type_id"])
			tv.build(trace, store.type_data(sim.setup.outfit_id, tid)["appearance"], store.type_scene(sim.setup.outfit_id, tid), mats, store.hunt["trace"], _trace_rng, settings.get_b("reduce_flashing"))
		"match_ended":
			_start_reveal(String(e["result"]["outcome"]))


func _process(delta: float) -> void:
	if sim == null:
		return
	sync(delta)


func sync(delta: float) -> void:
	var frozen: bool = sim.paused or sim.phase == MatchSim.Phase.BRIEFING or sim.phase == MatchSim.Phase.REVEAL or sim.phase == MatchSim.Phase.RESULTS
	var walk: float = float(store.npc["walk_speed_mps"])
	for v: NpcVisual in npc_visuals:
		var n: NpcState = sim.npcs[v.npc_id]
		v.visible = n.alive
		if not n.alive:
			continue
		if _reveal_t >= 0.0 and n.is_target:
			continue   ## 정체 공개 중 타겟은 연출이 움직인다
		v.sync_state(n, walk, frozen and not (sim.phase == MatchSim.Phase.BRIEFING))
		v.set_debug(debug_on, sim.is_observed(n), n.is_target)
		if not frozen and n.mode == NpcState.Mode.MOVING and delta > 0.0:
			_step_clock[v.npc_id] += delta * sim.crowd_speed_mult   ## 군중 가속(§7.9)은 모두에게 같게 박자를 당긴다
			if _step_clock[v.npc_id] >= STEP_INTERVAL_S:
				_step_clock[v.npc_id] -= STEP_INTERVAL_S
				var p3: Vector3 = Vector3(n.pos.x, 0.05, n.pos.y)
				if p3.distance_to(cam.global_position) < AudioDirector.FOOTSTEP_RANGE_M:
					audio.footstep(p3, v.npc_id)
	_sync_player(delta, frozen)
	if _reveal_t >= 0.0:
		_reveal_step(delta)
	else:
		cam.global_transform = Transform3D(sim.camera.basis, sim.camera.eye)
		cam.fov = sim.camera.fov_deg


func _sync_player(delta: float, frozen: bool) -> void:
	player_model.position = Vector3(sim.player_pos.x, 0.0, sim.player_pos.y)
	player_model.rotation.y = atan2(-sim.player_facing.x, -sim.player_facing.y)
	var close: bool = sim.camera.eye.distance_to(Vector3(sim.player_pos.x, 1.2, sim.player_pos.y)) < float(store.player["camera"]["fade_model_within_m"]) + 0.6
	player_model.visible = not close
	if player_anim == null or delta <= 0.0:
		return
	var spd: float = sim.player_pos.distance_to(_last_player_pos) / delta
	_last_player_pos = sim.player_pos
	if frozen:
		player_anim.speed_scale = 0.0
		return
	if _player_anim_name == "land" and player_anim.is_playing():
		return
	var want: String = "idle"
	var scale: float = 1.0
	if spd > 3.2:
		want = "run"
		scale = spd / 4.5
	elif spd > 0.2:
		want = "walk"
		scale = spd / 1.25
	player_anim.speed_scale = scale
	if want != _player_anim_name:
		_player_anim_name = want
		player_anim.play(want, 0.15)


# ================================================================ 정체 공개(§8.4)

func _start_reveal(outcome: String) -> void:
	_reveal_outcome = outcome
	_reveal_t = 0.0
	_lose_a_placed = false
	var tv: NpcVisual = npc_visuals[sim.target.id]
	_reveal_from_facing = sim.target.facing
	if outcome == "LOSE_ALL_GONE":
		arena_visual.blackout(1.0, settings.get_b("reduce_flashing"))
	else:
		_highlight_target(true)
	tv.model.play_once("reveal")


func _highlight_target(on: bool) -> void:
	var v: Dictionary = sim.setup.variant
	if v.is_empty():
		return
	var mi: MeshInstance3D = npc_visuals[sim.target.id].model.slot_nodes.get(String(v["op"]["slot"])) as MeshInstance3D
	if mi != null:
		mi.material_overlay = _reveal_overlay if on else null


func _reveal_step(delta: float) -> void:
	_reveal_t += delta
	var tv: NpcVisual = npc_visuals[sim.target.id]
	var t: NpcState = sim.target
	var to_player: Vector2 = (sim.player_pos - t.pos)
	match _reveal_outcome:
		"LOSE_ALL_GONE":
			## 조명이 꺼졌다 켜지면 타겟 혼자 플레이어 6 m 앞에 서서 이쪽을 보고 있다.
			if _reveal_t >= 0.9 and not _lose_a_placed:
				_lose_a_placed = true
				var fwd: Vector2 = sim.ground_forward()
				var p: Vector2 = sim.layout.nearest_walkable(sim.player_pos + fwd * 6.0)
				tv.position = Vector3(p.x, 0.0, p.y)
				var d: Vector2 = sim.player_pos - p
				tv.rotation.y = atan2(-d.x, -d.y)
				tv.model.play_once("reveal")
				_highlight_target(true)
			cam.global_transform = Transform3D(sim.camera.basis, sim.camera.eye)
		"LOSE_NO_CHANCES":
			## 카메라가 타겟을 비춘다.
			var tp: Vector3 = Vector3(t.pos.x, 1.35, t.pos.y)
			var face: Vector2 = Vector2.from_angle(lerp_angle(_reveal_from_facing.angle(), to_player.angle(), clampf(_reveal_t / REVEAL_TURN_S, 0.0, 1.0)))
			tv.position = Vector3(t.pos.x, 0.0, t.pos.y)
			tv.rotation.y = atan2(-face.x, -face.y)
			var eye: Vector3 = tp + Vector3(face.x, 0.15, face.y) * 2.4
			var k: float = clampf(_reveal_t / 0.8, 0.0, 1.0)
			var from: Transform3D = Transform3D(sim.camera.basis, sim.camera.eye)
			var to_t: Transform3D = Transform3D.IDENTITY.translated(eye).looking_at(tp, Vector3.UP)
			cam.global_transform = from.interpolate_with(to_t, k * k * (3.0 - 2.0 * k))
			cam.fov = lerpf(sim.camera.fov_deg, 40.0, k)
		_:
			## 승리: 타겟이 천천히 플레이어 쪽으로 돌아서고, 카메라가 타겟을 향한다.
			var face2: Vector2 = Vector2.from_angle(lerp_angle(_reveal_from_facing.angle(), to_player.angle(), clampf(_reveal_t / REVEAL_TURN_S, 0.0, 1.0)))
			tv.position = Vector3(t.pos.x, 0.0, t.pos.y)
			tv.rotation.y = atan2(-face2.x, -face2.y)
			var k2: float = clampf(_reveal_t / 0.6, 0.0, 1.0)
			var from2: Transform3D = Transform3D(sim.camera.basis, sim.camera.eye)
			var to2: Transform3D = Transform3D.IDENTITY.translated(sim.camera.eye).looking_at(Vector3(t.pos.x, 1.35, t.pos.y), Vector3.UP)
			cam.global_transform = from2.interpolate_with(to2, k2)
			## 멀리 있으면 확대해서 타겟이 화면에서 잘 보이게 한다.
			var far: float = sim.camera.eye.distance_to(Vector3(t.pos.x, 1.35, t.pos.y))
			cam.fov = lerpf(sim.camera.fov_deg, clampf(rad_to_deg(2.0 * atan(1.6 / maxf(far, 0.1))), 12.0, sim.camera.fov_deg), k2)
	if _reveal_overlay != null:
		_reveal_overlay.albedo_color.a = 0.3 + 0.4 * (0.5 + 0.5 * sin(_reveal_t * 7.0))


## 시드 고정 스크린샷 등에서 쓰는 디버그 보조.
func face_latest_trace() -> void:
	if sim.traces.is_empty():
		return
	var tp: Vector2 = sim.traces[-1]["pos"]
	sim.player_pos = sim.layout.resolve_circle(tp + Vector2(0.0, 4.0), 0.35)
	sim.yaw = 0.0
	sim.pitch = deg_to_rad(-35.0)
	sim._update_camera()
