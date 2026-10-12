extends Node3D
## 진입점. 메뉴 ↔ 판 흐름을 맡는다. 판 안에서는 MatchSim을 물리 틱(60 Hz)마다 한 번 돌리고,
## 그 상태를 MatchView(3D)·Hud·AudioDirector가 보여 주게 한다. 규칙 판정은 MatchSim만 한다.

const MOUSE_SENS: float = 0.0025
const PLAYTEST_LOG: String = "user://playtest_log.jsonl"

var store: DataStore
var sim: MatchSim
var args: DebugArgs
var settings: AppSettings
var records: Records
var audio: AudioDirector
var view: MatchView
var hud: Hud
var menu: MenuUi
var pause_settings: SettingsPanel
var mats: MaterialCache
var debug_on: bool = false
var _mouse_delta: Vector2 = Vector2.ZERO
var _since_start: float = 0.0
var _shot_taken: bool = false
var _observe_latched: bool = false
var _pause_request: bool = false
var _preset: String = "standard"
var _daily: bool = false
var _recorded: bool = true
var _result_applied: bool = false
var _record_note: String = ""
var _tips_shown: Dictionary = {}
var _data_ok: bool = false


func _ready() -> void:
	InputSetup.ensure_actions()
	args = DebugArgs.parse(OS.get_cmdline_user_args())
	debug_on = args.debug_overlay and OS.is_debug_build()
	settings = AppSettings.load_from()
	settings.apply_input()
	if args.quality != "":
		settings.values["graphics_quality"] = args.quality   ## 이번 실행만(설정을 저장하면 같이 저장된다)
	records = Records.load_from()
	store = DataStore.load_default()
	audio = AudioDirector.new()
	add_child(audio)
	audio.setup()
	audio.apply_volumes(settings)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.settings = settings
	layer.add_child(hud)
	hud.result_action.connect(_on_result_action)
	hud.pause_action.connect(_on_pause_action)
	pause_settings = SettingsPanel.new()
	pause_settings.theme = Hud.make_theme()
	pause_settings.setup(settings, store.graphics)
	pause_settings.visible = false
	pause_settings.closed.connect(func() -> void: pause_settings.visible = false)
	pause_settings.changed.connect(_on_settings_changed)
	layer.add_child(pause_settings)
	_apply_window_scale()
	var errs: PackedStringArray = store.validate()
	if not errs.is_empty():
		hud.center_panel.visible = true
		hud.center_text.text = "데이터 검사 실패\n" + "\n".join(errs)
		hud.call_deferred("_layout")
		for e: String in errs:
			push_error(e)
		return
	_data_ok = true
	if records.load_note != "":
		push_warning(records.load_note)
	var menu_layer: CanvasLayer = CanvasLayer.new()
	menu_layer.layer = 2
	add_child(menu_layer)
	menu = MenuUi.new()
	menu.theme = Hud.make_theme()
	menu.setup(store, records, settings)
	menu.start_requested.connect(_on_menu_start)
	menu.quit_requested.connect(func() -> void: get_tree().quit())
	menu.settings_changed.connect(_on_settings_changed)
	menu_layer.add_child(menu)
	if args.direct:
		_preset = args.difficulty
		_start_match(args.match_seed if args.has_seed else _fresh_seed(), false, not args.forces_match())
	else:
		_show_menu()
		if args.panel != "":
			menu.open_panel(args.panel)


func _exit_tree() -> void:
	NpcModel.clear_cache()
	MaterialCache.clear_textures()


func _fresh_seed() -> int:
	return absi(int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()) % 2147483647


func _apply_window_scale() -> void:
	get_window().content_scale_factor = settings.get_f("ui_scale")


func _on_settings_changed() -> void:
	audio.apply_volumes(settings)
	_apply_window_scale()
	if view != null and is_instance_valid(view) and view.arena_visual != null:
		view.arena_visual.apply_quality(store.graphics_level(String(settings.values.get("graphics_quality", ""))))


# ================================================================ 메뉴 ↔ 판

func _show_menu() -> void:
	_end_match_world()
	menu.refresh()
	menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_menu_start(preset: String, daily: bool) -> void:
	_preset = preset
	if daily:
		_start_match(Records.daily_seed(Records.today()), true, true)
	else:
		_start_match(_fresh_seed(), false, true)


func _end_match_world() -> void:
	if view != null:
		view.queue_free()
		view = null
	sim = null
	audio.stop_match()
	hud.hide_results()
	hud.visible = false


## recorded: 기록·도감에 남길지(같은 시드로 다시, 디버그로 강제한 판은 남기지 않는다).
func _start_match(seed_value: int, daily: bool, recorded: bool) -> void:
	_end_match_world()
	_daily = daily
	_recorded = recorded
	_result_applied = false
	_record_note = ""
	_tips_shown.clear()
	var recent: Array = [] if daily or args.variant != "" else records.recent_variants()
	sim = MatchSim.new(store, {
		"preset": _preset,
		"map": "atrium",
		"seed": seed_value,
		"variant": args.variant,
		"search_time": args.search_time,
		"recent_variants": recent,
		"fov_deg": settings.get_f("fov_deg"),
	})
	sim.yaw = deg_to_rad(args.yaw_deg)
	sim.pitch = deg_to_rad(args.pitch_deg)
	if args.skip_intro:
		sim.skip_intro()
	mats = MaterialCache.for_store(store, store.outfits[sim.setup.outfit_id]["palette"])
	view = MatchView.new()
	view.name = "MatchView"
	add_child(view)
	view.debug_on = debug_on
	view.build(store, sim, mats, settings, audio)
	audio.attach_world(view)
	audio.start_match()
	audio.ui("chime_announce", -8.0)
	hud.visible = true
	hud.set_type_names(store.maps["atrium"])
	hud.prepare_match(store, sim, mats)
	menu.visible = false
	_since_start = 0.0
	_shot_taken = false
	_observe_latched = false


func _on_result_action(action: String) -> void:
	if sim == null or sim.phase != MatchSim.Phase.RESULTS:
		return
	audio.ui("ui_click")
	match action:
		"restart":
			if _daily:
				_start_match(Records.daily_seed(Records.today()), true, true)
			else:
				_start_match(_fresh_seed(), false, true)
		"replay_same":
			_start_match(sim.match_seed, _daily, false)
		"menu":
			_show_menu()


func _on_pause_action(action: String) -> void:
	match action:
		"resume":
			_pause_request = true
		"settings":
			pause_settings.visible = true
			pause_settings.reset_size()
			pause_settings.position = (get_viewport().get_visible_rect().size - pause_settings.size) * 0.5
		"menu":
			pause_settings.visible = false
			_show_menu()


# ================================================================ 입력

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += (event as InputEventMouseMotion).relative
	if sim == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if Input.is_action_pressed("reference") and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			hud.cycle_reference(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		elif _playing():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("observe") and settings.get_b("observe_toggle"):
		_observe_latched = not _observe_latched
	if event.is_action_pressed("debug_overlay") and OS.is_debug_build():
		debug_on = not debug_on
		view.debug_on = debug_on
	elif event.is_action_pressed("debug_hunt") and OS.is_debug_build():
		sim.debug_force_hunt()
	elif event.is_action_pressed("debug_hint") and OS.is_debug_build():
		sim.debug_hint_now()
	elif sim.phase == MatchSim.Phase.RESULTS:
		if event.is_action_pressed("restart"):
			_on_result_action("restart")
		elif event.is_action_pressed("replay_same"):
			_on_result_action("replay_same")
		elif event.is_action_pressed("to_menu"):
			_on_result_action("menu")


func _playing() -> bool:
	return sim != null and (sim.phase == MatchSim.Phase.SEARCH or sim.phase == MatchSim.Phase.HUNT) and not sim.paused


func _physics_process(_delta: float) -> void:
	if sim == null:
		return
	var inp: PlayerInput = PlayerInput.new()
	inp.move = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
	inp.run = Input.is_action_pressed("run")
	inp.observe = _observe_latched if settings.get_b("observe_toggle") else Input.is_action_pressed("observe")
	var sens: float = MOUSE_SENS * settings.get_f("mouse_sensitivity") * (float(store.player["camera"]["observe"]["sensitivity_scale"]) if sim.observe_blend > 0.5 else 1.0)
	var dy: float = -_mouse_delta.y * (-1.0 if settings.get_b("invert_y") else 1.0)
	inp.look_delta = Vector2(-_mouse_delta.x, dy) * sens
	_mouse_delta = Vector2.ZERO
	inp.interact_pressed = Input.is_action_just_pressed("interact")
	inp.accuse_held = Input.is_action_pressed("accuse")
	inp.pause_pressed = Input.is_action_just_pressed("pause") or _pause_request
	_pause_request = false
	if pause_settings.visible and inp.pause_pressed:
		pause_settings.visible = false
		inp.pause_pressed = false
	inp.skip_pressed = Input.is_action_just_pressed("skip")
	sim.camera.aspect = _aspect()
	sim.step(inp)
	if args.force_hunt and sim.phase == MatchSim.Phase.SEARCH:
		sim.debug_force_hunt()
	if OS.is_debug_build() and args.end_as != "" and sim.match_time >= 1.0 and not sim.is_resolved():
		sim.debug_end({"win": "WIN", "lose_all": "LOSE_ALL_GONE", "lose_chances": "LOSE_NO_CHANCES"}.get(args.end_as, "WIN"))
	if OS.is_debug_build() and args.pause_at >= 0.0 and sim.match_time >= args.pause_at and not sim.paused:
		args.pause_at = -1.0
		_pause_request = true
	for e: Dictionary in sim.events:
		_on_event(e)
	if sim == null:
		return
	_update_tips()
	var want: Input.MouseMode = Input.MOUSE_MODE_CAPTURED if _playing() and args.screenshot == "" else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want


func _aspect() -> float:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return size.x / maxf(size.y, 1.0)


# ================================================================ 이벤트 → 표시·소리·기록

func _on_event(e: Dictionary) -> void:
	hud.on_event(e, sim)
	view.on_event(e)
	match String(e["type"]):
		"phase_changed":
			match String(e["to"]):
				"HUNT":
					audio.ui("chime_announce", -2.0)
					if not settings.get_b("reduce_flashing"):
						audio.ui("lights_flicker", -6.0)
					audio.set_hunt(true)
				"RESULTS":
					hud.show_results(store, sim, mats, _record_note, true)
		"npc_eliminated":
			var p: Vector2 = e["pos"]
			var p3: Vector3 = Vector3(p.x, 0.4, p.y)
			audio.at("elimination", p3, AudioDirector.ELIM_RANGE_M)
			audio.at("puddle", p3, AudioDirector.ELIM_RANGE_M, -6.0)
			audio.ui("counter_tick", -6.0)
			if settings.get_b("sound_direction") and sim.player_pos.distance_to(p) <= AudioDirector.ELIM_RANGE_M:
				var d: Vector2 = (p - sim.player_pos).normalized()
				hud.add_sound_arc(atan2(d.dot(sim.ground_right()), d.dot(sim.ground_forward())))
		"hint_shown":
			audio.ui("chime_hint", -4.0)
		"accusation_resolved":
			audio.ui("correct" if bool(e["correct"]) else "buzzer", -2.0)
		"match_ended":
			_apply_result(e["result"])


func _apply_result(result: Dictionary) -> void:
	if _result_applied:
		return
	_result_applied = true
	var meta: Dictionary = {
		"preset": _preset,
		"date": Records.today(),
		"daily": _daily,
		"recorded": _recorded,
		"fov_deg": settings.get_f("fov_deg"),
		"exclusion": int(store.difficulty["recent_variant_exclusion"]),
	}
	var out: Dictionary = records.apply_result(result, meta)
	var notes: PackedStringArray = []
	if not _recorded:
		notes.append("이 판은 기록에 남지 않습니다")
	else:
		var err: Error = records.save()
		if err != OK:
			notes.append("기록 저장 실패 (%s)" % error_string(err))
		if bool(out["new_best"]):
			notes.append("최고 점수 갱신!")
		if bool(out["hard_unlocked_now"]):
			notes.append("어려움 난이도가 열렸습니다")
		if String(out["codex_new"]) != "":
			notes.append("변이 도감에 새 항목")
		if _daily:
			notes.append("오늘의 도전 기록 완료" if bool(out["daily_counted"]) else "오늘의 도전은 처음 결과만 기록됩니다")
	_record_note = " · ".join(notes)
	if OS.is_debug_build() or args.playtest_log:
		_write_playtest_log(result, meta)


## 플레이테스트 계측(§14.4). 판 요약 한 줄.
func _write_playtest_log(result: Dictionary, meta: Dictionary) -> void:
	var line: Dictionary = result.duplicate(true)
	line.erase("variant")
	line["meta"] = meta
	line["logged_at"] = Time.get_datetime_string_from_system()
	line["build"] = "debug" if OS.is_debug_build() else "release"
	var f: FileAccess = FileAccess.open(PLAYTEST_LOG, FileAccess.READ_WRITE if FileAccess.file_exists(PLAYTEST_LOG) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(line))
	f.close()


# ================================================================ 연습 안내(§10.1)

func _tip(key: String, text: String, force: bool = false) -> void:
	if _tips_shown.has(key) or (hud.tip_panel.visible and not force):
		return
	_tips_shown[key] = sim.match_time
	hud.show_tip(text, 8.0)


func _update_tips() -> void:
	if sim.preset_id != "practice" or sim.paused or sim.is_resolved():
		return
	var inter: Dictionary = store.player["interaction"]
	if sim.phase == MatchSim.Phase.SEARCH:
		_tip("move", "WASD로 걷고 Shift로 달린다. 마우스 우클릭을 누르고 있으면 관찰 모드(확대)가 된다.\n손님은 종류별로 모두 똑같다. 같은 종류끼리 비교해 한 군데 다른 사람을 찾자.")
		if sim.match_time > 8.0 and sim.aim_id >= 0 and sim.aim_distance() <= float(inter["call_range_m"]):
			_tip("call", "%s: 호출 — 손님이 잠시 멈춰 이쪽을 본다. 그 사이 둘레를 돌며 앞·뒤·옆을 비교하자." % hud._key("interact"))
		if sim.calls > 0:
			_tip("reference", "%s를 누르고 있으면 오른쪽에 기준 외형이 나온다. 마우스 휠로 종류를 넘긴다." % hud._key("reference"))
		if sim.calls > 0 and sim.match_time > 25.0 and sim.aim_id >= 0 and sim.aim_distance() <= float(inter["accuse_range_m"]):
			_tip("accuse", "확신이 들면 %s를 0.8초 누르고 있어 지목한다. 틀리면 이동속도가 줄고 5초 동안 지목할 수 없다." % hud._key("accuse"))
	elif sim.phase == MatchSim.Phase.HUNT:
		_tip("hunt", "이제 타겟이 보이지 않는 곳에서 사람을 지운다. 화면에 보이는 사람과 4 m 안의 사람은 안전하다.", true)
		for tr: Dictionary in sim.traces:
			if sim.player_pos.distance_to(tr["pos"] as Vector2) < 8.0:
				_tip("trace", "흔적 가까이에서 %s: 얼마나 지났는지 조사한다. 젖은 발자국은 타겟이 떠난 방향이다." % hud._key("interact"))
				break
		if sim.hints_shown > 0:
			_tip("hint", "10초마다 그 순간 타겟까지의 대략적 거리가 3초 동안 나온다. 다음 힌트와 비교해 가까워졌는지 판단하자.")


# ================================================================ 매 프레임

func _process(delta: float) -> void:
	_since_start += delta
	if sim != null:
		var ref_allowed: bool = String(sim.preset.get("reference_viewer", "always")) == "always"
		hud.refresh(sim, delta, debug_on, Input.is_action_pressed("reference") or (args.show_reference and OS.is_debug_build()), ref_allowed)
		if args.face_trace and args.screenshot != "" and _since_start >= args.screenshot_at - 1.0:
			view.face_latest_trace()
	if args.screenshot != "" and not _shot_taken and _since_start >= args.screenshot_at:
		_shot_taken = true
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(args.screenshot)
		print("screenshot saved: ", args.screenshot)
		## 성능 확인(§13.12): 마지막 프레임의 그리기 호출·삼각형 수와 평균 FPS.
		print("perf: fps %.0f · draw calls %d · primitives %d · nodes %d" % [Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		get_tree().quit()
