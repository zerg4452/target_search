class_name Hud
extends Control
## HUD(§11.1)와 판 안의 화면(브리핑, 기준 외형 보기, 연습 안내, 일시정지, 결과).
## MatchSim을 읽고 이벤트를 받아 보여 주기만 한다. 규칙을 판단하지 않는다.

signal result_action(action: String)   ## "restart" | "replay_same" | "menu"
signal pause_action(action: String)    ## "resume" | "settings" | "menu"

const BAND_TEXT: Array[String] = [
	"타겟이 아주 가까이 있다 (5 m 이내)",
	"타겟이 가까이 있다 (약 5~10 m)",
	"타겟이 조금 떨어져 있다 (약 10~20 m)",
	"타겟이 멀리 있다 (약 20~30 m)",
	"타겟이 아주 멀리 있다 (30 m 이상)",
]
const GROUP_KO: Dictionary = {"hair": "머리", "face": "얼굴", "top": "상의", "lower": "하의·신발", "carry": "소지품"}
const DIR_KO: Dictionary = {"front": "앞", "back": "뒤", "left": "왼쪽", "right": "오른쪽", "top": "위", "any": "어느 방향"}
const OUTCOME_KO: Dictionary = {"WIN": "찾았다!", "LOSE_ALL_GONE": "실패 — 모두 사라졌다", "LOSE_NO_CHANCES": "실패 — 지목 기회를 모두 썼다"}
const ARC_LIFE_S: float = 2.5

var top_label: Label
var hint_label: Label
var right_label: Label
var crosshair: Label
var prompt_label: Label
var message_label: Label
var subtitle_label: Label
var debug_label: Label
var tip_panel: PanelContainer
var tip_label: Label
var center_panel: PanelContainer
var center_text: Label
var briefing_box: VBoxContainer
var briefing_table: Turntable
var briefing_text: Label
var reference_box: PanelContainer
var reference_table: Turntable
var reference_label: Label
var pause_dim: ColorRect
var pause_box: VBoxContainer
var results_box: PanelContainer
var results_text: Label
var results_table: Turntable
var results_buttons: HBoxContainer
var replay_button: Button

var settings: AppSettings
var _hint_left: float = 0.0
var _hint_fade: float = 0.3
var _message_left: float = 0.0
var _subtitle_left: float = 0.0
var _tip_left: float = 0.0
var _type_names: Dictionary = {}
var _arcs: Array[Dictionary] = []   ## {"angle": 라디안(화면 기준, 0=위), "age": 초}
var _ref_index: int = 0
var _ref_types: Array[String] = []
var _ref_entries: Array = []
var _ref_mats: MaterialCache
var _font: SystemFont


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = make_theme()
	_font = theme.default_font as SystemFont
	pause_dim = ColorRect.new()
	pause_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh: Shader = Shader.new()
	sh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;\nvoid fragment() {\n\tvec3 c = textureLod(screen_tex, SCREEN_UV, 4.5).rgb;\n\tCOLOR = vec4(c * 0.45, 1.0);\n}\n"
	var smat: ShaderMaterial = ShaderMaterial.new()
	smat.shader = sh
	pause_dim.material = smat
	pause_dim.visible = false
	add_child(pause_dim)
	top_label = _label(28, HORIZONTAL_ALIGNMENT_CENTER)
	hint_label = _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	right_label = _label(20, HORIZONTAL_ALIGNMENT_RIGHT)
	crosshair = _label(26, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_label = _label(18, HORIZONTAL_ALIGNMENT_CENTER)
	message_label = _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	subtitle_label = _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	debug_label = _label(15, HORIZONTAL_ALIGNMENT_LEFT)
	tip_panel = PanelContainer.new()
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_label = Label.new()
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(420, 0)
	tip_label.add_theme_font_size_override("font_size", 18)
	tip_panel.add_child(_margin(tip_label, 14))
	tip_panel.visible = false
	add_child(tip_panel)
	# 브리핑: 이번 판 타입들의 기준 인물 턴테이블 + 안내문
	briefing_box = VBoxContainer.new()
	briefing_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	briefing_box.add_theme_constant_override("separation", 10)
	briefing_table = Turntable.new()
	briefing_table.setup(Vector2i(900, 420))
	briefing_box.add_child(briefing_table)
	briefing_text = Label.new()
	briefing_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	briefing_text.add_theme_font_size_override("font_size", 20)
	briefing_box.add_child(briefing_text)
	var bp: PanelContainer = PanelContainer.new()
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bp.add_child(_margin(briefing_box, 18))
	bp.visible = false
	briefing_box.set_meta("panel", bp)
	add_child(bp)
	# 기준 외형 보기(Tab): 오른쪽 턴테이블
	reference_box = PanelContainer.new()
	reference_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rv: VBoxContainer = VBoxContainer.new()
	reference_label = Label.new()
	reference_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reference_label.add_theme_font_size_override("font_size", 18)
	rv.add_child(reference_label)
	reference_table = Turntable.new()
	reference_table.setup(Vector2i(320, 460))
	rv.add_child(reference_table)
	var hint2: Label = Label.new()
	hint2.text = "마우스 휠: 타입 넘기기"
	hint2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint2.add_theme_font_size_override("font_size", 14)
	rv.add_child(hint2)
	reference_box.add_child(_margin(rv, 10))
	reference_box.visible = false
	add_child(reference_box)
	# 가운데 안내(데이터 오류·착지 등)
	center_panel = PanelContainer.new()
	center_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_text = Label.new()
	center_text.add_theme_font_size_override("font_size", 22)
	center_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_panel.add_child(_margin(center_text, 28))
	center_panel.visible = false
	add_child(center_panel)
	# 일시정지 메뉴
	pause_box = VBoxContainer.new()
	pause_box.add_theme_constant_override("separation", 12)
	var pt: Label = Label.new()
	pt.text = "일시정지"
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pt.add_theme_font_size_override("font_size", 34)
	pause_box.add_child(pt)
	for pair: Array in [["계속 (Esc)", "resume"], ["설정", "settings"], ["메뉴로 나가기", "menu"]]:
		var b: Button = Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(280, 46)
		var act: String = pair[1]
		b.pressed.connect(func() -> void: pause_action.emit(act))
		pause_box.add_child(b)
	pause_box.visible = false
	add_child(pause_box)
	# 결과
	results_box = PanelContainer.new()
	var rh: HBoxContainer = HBoxContainer.new()
	rh.add_theme_constant_override("separation", 24)
	var rl: VBoxContainer = VBoxContainer.new()
	rl.add_theme_constant_override("separation", 14)
	results_text = Label.new()
	results_text.add_theme_font_size_override("font_size", 20)
	results_text.custom_minimum_size = Vector2(520, 0)
	results_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.add_child(results_text)
	results_buttons = HBoxContainer.new()
	results_buttons.add_theme_constant_override("separation", 10)
	for pair2: Array in [["다시 하기 (R)", "restart"], ["같은 시드로 (T)", "replay_same"], ["메뉴 (M)", "menu"]]:
		var b2: Button = Button.new()
		b2.text = pair2[0]
		b2.custom_minimum_size = Vector2(160, 44)
		var act2: String = pair2[1]
		b2.pressed.connect(func() -> void: result_action.emit(act2))
		results_buttons.add_child(b2)
		if act2 == "replay_same":
			replay_button = b2
	rl.add_child(results_buttons)
	rh.add_child(rl)
	results_table = Turntable.new()
	results_table.setup(Vector2i(460, 520))
	rh.add_child(results_table)
	results_box.add_child(_margin(rh, 22))
	results_box.visible = false
	add_child(results_box)


static func make_theme() -> Theme:
	## 기본 글꼴에는 한글이 없다. 시스템 한글 글꼴을 지정한다.
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Noto Sans KR", "Noto Sans CJK KR", "Apple SD Gothic Neo", "sans-serif"])
	var th: Theme = Theme.new()
	th.default_font = font
	th.default_font_size = 18
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Color(0.1, 0.1, 0.12, 0.94)
	panel.set_corner_radius_all(6)
	panel.set_border_width_all(1)
	panel.border_color = Color(1, 1, 1, 0.08)
	th.set_stylebox("panel", "PanelContainer", panel)
	return th


func _margin(c: Control, m: int) -> MarginContainer:
	var mc: MarginContainer = MarginContainer.new()
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, m)
	mc.add_child(c)
	return mc


func _label(size: int, align: HorizontalAlignment) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6 if size >= 20 else 3)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## 화면 크기에서 위치를 직접 계산한다. 글자 길이가 바뀌어도 가운데 정렬이 유지된다.
func _layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	size = vp
	var bp: PanelContainer = briefing_box.get_meta("panel")
	for l: Control in [top_label, hint_label, right_label, crosshair, prompt_label, message_label, subtitle_label, debug_label, center_panel, tip_panel, bp, reference_box, pause_box, results_box]:
		l.reset_size()
	top_label.position = Vector2((vp.x - top_label.size.x) * 0.5, 16.0)
	hint_label.position = Vector2((vp.x - hint_label.size.x) * 0.5, 64.0)
	right_label.position = Vector2(vp.x - right_label.size.x - 20.0, 16.0)
	crosshair.position = (vp - crosshair.size) * 0.5
	prompt_label.position = Vector2((vp.x - prompt_label.size.x) * 0.5, vp.y * 0.5 + 26.0)
	message_label.position = Vector2((vp.x - message_label.size.x) * 0.5, vp.y - 170.0)
	subtitle_label.position = Vector2((vp.x - subtitle_label.size.x) * 0.5, vp.y - 120.0)
	debug_label.position = Vector2(14.0, vp.y - debug_label.size.y - 14.0)
	center_panel.position = (vp - center_panel.size) * 0.5
	tip_panel.position = Vector2(24.0, vp.y * 0.30)
	bp.position = (vp - bp.size) * 0.5
	reference_box.position = Vector2(vp.x - reference_box.size.x - 20.0, (vp.y - reference_box.size.y) * 0.5)
	pause_box.position = (vp - pause_box.size) * 0.5
	results_box.position = (vp - results_box.size) * 0.5
	pause_dim.position = Vector2.ZERO
	pause_dim.size = vp


func set_type_names(map: Dictionary) -> void:
	for t: Dictionary in map.get("types", []):
		_type_names[String(t["id"])] = String(t["name_ko"])


func type_name(type_id: String) -> String:
	return String(_type_names.get(type_id, type_id))


## 판이 시작될 때: 브리핑·기준 외형 보기에 이번 판 타입들의 기준 인물을 세운다.
func prepare_match(store: DataStore, sim: MatchSim, mats: MaterialCache) -> void:
	_ref_types.clear()
	var entries: Array = []
	for t: String in sim.setup.types_used:
		_ref_types.append(t)
		entries.append({"app": sim.setup.base_appearances[t], "scene": store.type_scene(sim.setup.outfit_id, t), "label": type_name(t)})
	briefing_table.show_models(entries, mats)
	_ref_index = 0
	_ref_entries = entries
	_show_ref(mats)
	results_box.visible = false
	pause_box.visible = false
	pause_dim.visible = false
	tip_panel.visible = false
	_arcs.clear()
	hint_label.modulate.a = 0.0
	message_label.text = ""
	subtitle_label.text = ""


func _show_ref(mats: MaterialCache) -> void:
	_ref_mats = mats
	if _ref_entries.is_empty():
		return
	var e: Dictionary = _ref_entries[_ref_index % _ref_entries.size()]
	reference_table.show_models([{"app": e["app"], "scene": e["scene"], "label": ""}], mats)
	reference_label.text = "기준 외형: %s (%d/%d)" % [e["label"], _ref_index % _ref_entries.size() + 1, _ref_entries.size()]


func cycle_reference(step: int) -> void:
	if _ref_entries.is_empty():
		return
	_ref_index = posmod(_ref_index + step, _ref_entries.size())
	_show_ref(_ref_mats)


func on_event(e: Dictionary, sim: MatchSim) -> void:
	match String(e["type"]):
		"hint_shown":
			hint_label.text = BAND_TEXT[clampi(int(e["band"]), 0, BAND_TEXT.size() - 1)]
			_hint_left = float(e["duration_s"])
			_hint_fade = float(sim.hint_t["fade_out_s"])
			hint_label.modulate.a = 1.0
		"accusation_resolved":
			if not bool(e["correct"]):
				_message("틀렸다. 남은 지목 %d회 · 이동속도 감소 · 5초간 지목 불가" % int(e["left"]))
		"trace_inspected":
			if bool(e["over_minute"]):
				_message("흔적: 1분 넘게 지났다")
			else:
				_message("흔적: 약 %d초 전" % maxi(int(e["rounded_s"]), 0))
		"phase_changed":
			if String(e["to"]) == "HUNT":
				subtitle("[안내 방송] 탐색 시간이 끝났습니다.", 4.0)
			elif String(e["to"]) == "SEARCH":
				subtitle("[안내 방송] 손님 여러분, 오늘도 에코 몰을 찾아 주셔서 감사합니다.", 3.5)


func _message(text: String) -> void:
	message_label.text = text
	_message_left = 3.0


## 안내 방송 자막(§11.4 옵션).
func subtitle(text: String, seconds: float) -> void:
	if settings != null and not settings.get_b("subtitles"):
		return
	subtitle_label.text = text
	_subtitle_left = seconds


func show_tip(text: String, seconds: float = 7.0) -> void:
	tip_label.text = text
	tip_panel.visible = true
	_tip_left = seconds


## 소리 방향 표시(§7.6): 화면 기준 각도(0 = 정면 위쪽, 시계 방향 +).
func add_sound_arc(screen_angle: float) -> void:
	_arcs.append({"angle": screen_angle, "age": 0.0})


func refresh(sim: MatchSim, delta: float, debug_on: bool, reference_held: bool, reference_allowed: bool) -> void:
	if _hint_left > 0.0:
		_hint_left -= delta
		hint_label.modulate.a = 1.0
	elif hint_label.modulate.a > 0.0:
		hint_label.modulate.a = maxf(0.0, hint_label.modulate.a - delta / maxf(_hint_fade, 0.01))
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			message_label.text = ""
	if _subtitle_left > 0.0:
		_subtitle_left -= delta
		if _subtitle_left <= 0.0:
			subtitle_label.text = ""
	if _tip_left > 0.0:
		_tip_left -= delta
		if _tip_left <= 0.0:
			tip_panel.visible = false
	for a: Dictionary in _arcs:
		a["age"] = float(a["age"]) + delta
	_arcs = _arcs.filter(func(a: Dictionary) -> bool: return float(a["age"]) < ARC_LIFE_S)
	var playing: bool = sim.phase == MatchSim.Phase.SEARCH or sim.phase == MatchSim.Phase.HUNT
	match sim.phase:
		MatchSim.Phase.SEARCH:
			var s: int = int(ceil(sim.search_left))
			top_label.text = "탐색  %d:%02d" % [s / 60, s % 60]
		MatchSim.Phase.HUNT:
			top_label.text = "남은 사람  %d" % sim.normals_alive()
		MatchSim.Phase.REVEAL:
			top_label.text = String(OUTCOME_KO.get(String(sim.result.get("outcome", "")), ""))
		_:
			top_label.text = ""
	var total: int = int(sim.preset["accusations"])
	right_label.text = "지목 기회  %d/%d" % [sim.accusations_left, total]
	if sim.player_speed_mult < 0.999:
		right_label.text += "\n이동속도 %d%%" % int(round(sim.player_speed_mult * 100.0))
	right_label.visible = playing
	crosshair.visible = playing and not sim.paused
	crosshair.text = "◯" if sim.observe_blend > 0.5 else "+"
	prompt_label.text = _prompt(sim) if playing and not sim.paused else ""
	var bp: PanelContainer = briefing_box.get_meta("panel")
	bp.visible = sim.phase == MatchSim.Phase.BRIEFING
	if bp.visible:
		var names: PackedStringArray = []
		for t: String in sim.setup.types_used:
			names.append(type_name(t))
		briefing_text.text = "이번 손님은 %d종류입니다: %s\n같은 종류끼리는 모두 똑같지만, 단 한 명이 어딘가 다릅니다.\n제한시간이 지나면 그 한 명이 보이지 않는 곳에서 사람들을 지웁니다.\n\n%s" % [
			names.size(), ", ".join(names), "Space: 시작" if sim.phase_time >= MatchSim.BRIEFING_SKIP_AFTER_S else "잠시 뒤 시작합니다"]
	reference_box.visible = reference_held and playing and not sim.paused and reference_allowed
	center_text.text = "착지 중…" if sim.phase == MatchSim.Phase.DROP else ""
	if reference_held and playing and not reference_allowed:
		_message("어려움 난이도에서는 기준 외형을 브리핑 때만 볼 수 있습니다")
	center_panel.visible = center_text.text != ""
	pause_dim.visible = sim.paused
	pause_box.visible = sim.paused
	debug_label.visible = debug_on
	if debug_on:
		debug_label.text = _debug_text(sim)
	_layout()
	queue_redraw()


func _draw() -> void:
	if _arcs.is_empty():
		return
	var vp: Vector2 = get_viewport_rect().size
	var c: Vector2 = vp * 0.5
	var r: float = minf(vp.x, vp.y) * 0.42
	for a: Dictionary in _arcs:
		var alpha: float = 1.0 - float(a["age"]) / ARC_LIFE_S
		var ang: float = float(a["angle"]) - PI * 0.5
		draw_arc(c, r, ang - 0.28, ang + 0.28, 24, Color(1.0, 0.35, 0.25, alpha), 8.0, true)
		draw_arc(c, r - 12.0, ang - 0.16, ang + 0.16, 16, Color(1.0, 0.85, 0.8, alpha * 0.8), 3.0, true)


func _prompt(sim: MatchSim) -> String:
	var lines: PackedStringArray = []
	var locked: float = sim.lock_until - sim.match_time
	if locked > 0.0:
		lines.append("지목 불가 %.1f초" % locked)
	if sim.aim_id >= 0:
		var d: float = sim.aim_distance()
		var inter: Dictionary = sim.player_t["interaction"]
		var parts: PackedStringArray = []
		if d <= float(inter["call_range_m"]):
			parts.append("%s 호출" % _key("interact"))
		if d <= float(inter["accuse_range_m"]) and locked <= 0.0:
			parts.append("%s 지목(누르고 있기)" % _key("accuse"))
		if not parts.is_empty():
			lines.append(" · ".join(parts))
	elif sim.phase == MatchSim.Phase.HUNT:
		var inter2: Dictionary = sim.player_t["interaction"]
		for tr: Dictionary in sim.traces:
			if sim.player_pos.distance_to(tr["pos"] as Vector2) <= float(inter2["trace_inspect_range_m"]):
				lines.append("%s 흔적 조사" % _key("interact"))
				break
	if sim.hold_id >= 0 and sim.hold_time > 0.0:
		var ratio: float = sim.hold_time / float(sim.player_t["interaction"]["accuse_hold_s"])
		var filled: int = int(round(ratio * 10.0))
		lines.append("지목 중 [%s%s]" % ["■".repeat(filled), "□".repeat(10 - filled)])
	return "\n".join(lines)


func _key(action: String) -> String:
	return settings.binding_text(action).split(" / ")[0] if settings != null else action


## 결과 화면(§8.4): 승패·점수 + 기준 인물과 타겟을 나란히 놓은 턴테이블, 차이 부위 강조.
func show_results(store: DataStore, sim: MatchSim, mats: MaterialCache, record_note: String, replay_allowed: bool) -> void:
	var r: Dictionary = sim.result
	var lines: PackedStringArray = []
	var outcome: String = String(r.get("outcome", ""))
	if outcome == "WIN":
		lines.append("찾았다!   등급 %s · %d점" % [r.get("grade", "-"), int(r.get("score", 0))])
		lines.append("%s에서 찾음" % ("1단계(탐색)" if String(r.get("found_in", "")) == "SEARCH" else "2단계(사냥)"))
	else:
		lines.append(String(OUTCOME_KO.get(outcome, outcome)))
	lines.append("구한 사람 %d명 · 걸린 시간 %d:%02d · 오답 %d회" % [int(r.get("remaining", 0)), int(r.get("match_time", 0.0)) / 60, int(r.get("match_time", 0.0)) % 60, int(r.get("wrongs", 0))])
	var v: Dictionary = r.get("variant", {})
	var tname: String = type_name(String(r.get("target_type", "")))
	if v.is_empty():
		lines.append("\n타겟: %s (차이 없음 — 디버그 판)" % tname)
	else:
		lines.append("\n타겟: %s — %s" % [tname, v.get("name_ko", "")])
		var dirs: PackedStringArray = []
		for d: Variant in v.get("visible_from", []):
			dirs.append(String(DIR_KO.get(String(d), String(d))))
		var how: String = "관찰 모드로 " if int(v.get("difficulty", 1)) >= 3 else ""
		lines.append("부위: %s · %s에서, %s%.0f m 안쪽에서 보였다 (등급 %d)" % [GROUP_KO.get(String(v.get("group", "")), ""), "·".join(dirs), how, float(v.get("identify_distance_m", 0.0)), int(v.get("difficulty", 0))])
	if record_note != "":
		lines.append("\n" + record_note)
	lines.append("\n시드 %d · %s" % [int(r.get("seed", 0)), "같은 시드로 다시 하면 기록에 남지 않습니다" if replay_allowed else ""])
	results_text.text = "\n".join(lines)
	# 턴테이블: 기준 인물 | 타겟
	var t: String = String(r.get("target_type", ""))
	var base_app: Dictionary = sim.setup.base_appearances[t]
	var target_app: Dictionary = sim.setup.appearances[int(r.get("target", 0))]
	var scene: String = store.type_scene(sim.setup.outfit_id, t)
	results_table.show_models([{"app": base_app, "scene": scene, "label": "기준 (%s)" % tname}, {"app": target_app, "scene": scene, "label": "타겟"}], mats)
	results_table.clear_highlight()
	if not v.is_empty():
		var slot: String = String(v["op"]["slot"])
		results_table.highlight(1, slot)
		if String(v["op"]["type"]) == "hide":
			results_table.highlight(0, slot)
	replay_button.visible = replay_allowed
	results_box.visible = true


func hide_results() -> void:
	results_box.visible = false


func _debug_text(sim: MatchSim) -> String:
	var lines: PackedStringArray = []
	lines.append("[디버그] 시드 %d · 변이 %s · 타겟 #%d(%s)" % [sim.match_seed, sim.setup.variant_id if sim.setup.variant_id != "" else "NONE", sim.target.id, sim.target.type_id])
	lines.append("단계 %s · 사냥 %s · 피해자 %d · 제거 %d" % [sim.phase_name(), sim.hunter_name(), sim.victim_id, sim.kills])
	if sim.phase == MatchSim.Phase.HUNT:
		lines.append("사냥 %.1f초 · 다음 제거 가능 %.1f초 · 기회 공백 %.1f초" % [sim.hunt_time, maxf(0.0, sim.cooldown_ready_at - sim.hunt_time), sim.drought_time])
	var counts: PackedStringArray = []
	for t: String in sim.setup.types_used:
		counts.append("%s %d" % [t, int(sim.setup.type_counts[t])])
	lines.append("타입 인원: %s" % ", ".join(counts))
	for w: String in sim.setup.warnings:
		lines.append("경고: %s" % w)
	lines.append("F1 오버레이 · F2 즉시 사냥 · F3 즉시 힌트")
	return "\n".join(lines)
