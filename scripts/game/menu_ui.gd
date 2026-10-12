class_name MenuUi
extends Control
## 메인 메뉴(§10): 난이도 선택, 오늘의 도전(일일 시드), 변이 도감, 기록, 설정, 종료.
## 처음 실행하면 연습을 권한다. 어려움은 표준에서 한 번 이기면 열린다(§10.1).

signal start_requested(preset: String, daily: bool)
signal quit_requested
signal settings_changed

const PRESET_KO: Dictionary = {"practice": "연습", "standard": "표준", "hard": "어려움"}
const GRADE_DIR_KO: Dictionary = {"front": "앞", "back": "뒤", "left": "왼쪽", "right": "오른쪽", "top": "위", "any": "전방위"}

var store: DataStore
var records: Records
var settings: AppSettings
var mats: MaterialCache
var _main_box: VBoxContainer
var _note: Label
var _hard_button: Button
var _daily_button: Button
var _practice_button: Button
var _records_panel: PanelContainer
var _records_text: Label
var _codex_panel: PanelContainer
var _codex_list: ItemList
var _codex_table: Turntable
var _codex_info: Label
var _codex_ids: Array[String] = []
var _settings_panel: SettingsPanel
var _backdrop: Turntable


func setup(p_store: DataStore, p_records: Records, p_settings: AppSettings) -> void:
	store = p_store
	records = p_records
	settings = p_settings
	mats = MaterialCache.for_store(store, store.outfits["mall_guest"]["palette"])
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# 뒤쪽에 이 맵의 손님 타입 넷을 세운다.
	_backdrop = Turntable.new()
	_backdrop.setup(Vector2i(900, 560), Color(0.12, 0.12, 0.14))
	_backdrop.spin_speed = 0.35
	_backdrop.position = Vector2(560, 120)
	add_child(_backdrop)
	var entries: Array = []
	for t: Dictionary in store.maps["atrium"]["types"]:
		var tid: String = String(t["id"])
		entries.append({"app": Appearance.base_from(store.type_data("mall_guest", tid)["appearance"]["slots"]), "scene": store.type_scene("mall_guest", tid), "label": String(t["name_ko"])})
	_backdrop.show_models(entries, mats)
	_main_box = VBoxContainer.new()
	_main_box.position = Vector2(80, 70)
	_main_box.add_theme_constant_override("separation", 10)
	add_child(_main_box)
	var title: Label = Label.new()
	title.text = "틀린 사람 찾기"
	title.add_theme_font_size_override("font_size", 52)
	_main_box.add_child(title)
	var sub: Label = Label.new()
	sub.text = "ODD ONE OUT (가칭) · 에코 몰 아트리움"
	sub.add_theme_font_size_override("font_size", 18)
	sub.modulate = Color(1, 1, 1, 0.7)
	_main_box.add_child(sub)
	_main_box.add_child(_spacer(18))
	_practice_button = _button("연습 — 12명 · 손님 2종류 · 안내 팝업", func() -> void: start_requested.emit("practice", false))
	_button("표준 — 30명 · 손님 3종류 · 지목 3회", func() -> void: start_requested.emit("standard", false))
	_hard_button = _button("", func() -> void: start_requested.emit("hard", false))
	_daily_button = _button("", func() -> void: start_requested.emit("standard", true))
	_main_box.add_child(_spacer(8))
	_button("변이 도감", _show_codex)
	_button("기록", _show_records)
	_button("설정", _show_settings)
	_button("종료", func() -> void: quit_requested.emit())
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 16)
	_note.modulate = Color(1.0, 0.9, 0.5)
	_main_box.add_child(_note)
	_build_records()
	_build_codex()
	_settings_panel = SettingsPanel.new()
	_settings_panel.setup(settings, store.graphics)
	_settings_panel.visible = false
	_settings_panel.closed.connect(_hide_panels)
	_settings_panel.changed.connect(func() -> void: settings_changed.emit())
	add_child(_settings_panel)
	refresh()


func _spacer(h: float) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _button(text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	_main_box.add_child(b)
	return b


func refresh() -> void:
	var unlocked: bool = records.hard_unlocked()
	_hard_button.disabled = not unlocked
	_hard_button.text = "어려움 — 30명 · 손님 4종류 · 지목 1회" if unlocked else "어려움 (잠김 — 표준에서 한 번 이기면 열림)"
	var today: String = Records.today()
	var done: bool = (records.data["daily"] as Dictionary).has(today)
	_daily_button.text = "오늘의 도전 %s%s" % [today, " — 완료 (다시 해도 기록은 처음 결과)" if done else " — 표준 규칙, 모두 같은 판"]
	_note.text = "처음이라면 연습부터 해 보세요." if records.games() == 0 else ""
	if records.games() == 0:
		_practice_button.grab_focus.call_deferred()


## 디버그 스크린샷용으로 패널을 바로 연다.
func open_panel(panel_name: String) -> void:
	match panel_name:
		"codex":
			_show_codex()
			if _codex_list.item_count > 0:
				_codex_list.select(0)
				_on_codex_selected(0)
		"records":
			_show_records()
		"settings":
			_show_settings()


func _hide_panels() -> void:
	_records_panel.visible = false
	_codex_panel.visible = false
	_settings_panel.visible = false
	_sub_open(false)


## 하위 화면이 열려 있는 동안 메뉴 목록과 뒤쪽 인물을 감춘다(겹쳐 보이지 않게).
func _sub_open(open: bool) -> void:
	_main_box.visible = not open
	_backdrop.visible = not open


func _panel_layout(p: Control) -> void:
	p.reset_size()
	p.position = (get_viewport_rect().size - p.size) * 0.5


func _show_settings() -> void:
	_hide_panels()
	_sub_open(true)
	_settings_panel.visible = true
	_panel_layout.call_deferred(_settings_panel)


# ---------------------------------------------------------------- 기록

func _build_records() -> void:
	_records_panel = PanelContainer.new()
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_records_text = Label.new()
	_records_text.custom_minimum_size = Vector2(620, 0)
	v.add_child(_records_text)
	var close: Button = Button.new()
	close.text = "닫기"
	close.pressed.connect(_hide_panels)
	v.add_child(close)
	var mc: MarginContainer = _margin(v, 24)
	_records_panel.add_child(mc)
	_records_panel.visible = false
	add_child(_records_panel)


func _margin(c: Control, m: int) -> MarginContainer:
	var mc: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, m)
	mc.add_child(c)
	return mc


func _show_records() -> void:
	_hide_panels()
	var lines: PackedStringArray = ["기록", ""]
	var recs: Dictionary = records.data["records"]
	for pid: String in ["practice", "standard", "hard"]:
		var r: Dictionary = recs.get(pid, {})
		if r.is_empty():
			lines.append("%s: 아직 기록 없음" % PRESET_KO[pid])
			continue
		var best_t: float = float(r.get("best_find_s", -1.0))
		lines.append("%s: %d승 %d패 · 1단계 발견 %d회 · 최고 %d점(FOV %d°) · 최단 발견 %s" % [
			PRESET_KO[pid], int(r["wins"]), int(r["losses"]), int(r["search_finds"]), int(r["best_score"]), int(r["best_score_fov"]),
			"-" if best_t < 0.0 else "%d:%02d" % [int(best_t) / 60, int(best_t) % 60]])
	lines.append("")
	lines.append("오늘의 도전 (최근 7일)")
	var daily: Dictionary = records.data["daily"]
	var days: Array = daily.keys()
	days.sort()
	days.reverse()
	if days.is_empty():
		lines.append("  없음")
	for d: String in days.slice(0, 7):
		var e: Dictionary = daily[d]
		lines.append("  %s: %s · 구한 사람 %d명 · %d점" % [d, "성공" if bool(e["win"]) else "실패", int(e["remaining"]), int(e["score"])])
	var found: int = 0
	var seen: int = 0
	for vid: String in records.data["codex"]:
		match records.codex_state(vid):
			"found": found += 1
			"seen": seen += 1
	lines.append("")
	lines.append("변이 도감: 찾음 %d · 봄 %d / 전체 %d" % [found, seen, _all_variant_ids().size()])
	_records_text.text = "\n".join(lines)
	_sub_open(true)
	_records_panel.visible = true
	_panel_layout.call_deferred(_records_panel)


# ---------------------------------------------------------------- 변이 도감(§10.3)

func _all_variant_ids() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in store.maps["atrium"]["types"]:
		for v: Dictionary in store.type_data("mall_guest", String(t["id"]))["variants"]:
			if store.milestone_ok(String(v.get("milestone", "M0"))):
				out.append(String(v["id"]))
	return out


func _build_codex() -> void:
	_codex_panel = PanelContainer.new()
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var left: VBoxContainer = VBoxContainer.new()
	var title: Label = Label.new()
	title.text = "변이 도감 — 찾음(승리) / 봄(패배 후 공개)"
	title.add_theme_font_size_override("font_size", 22)
	left.add_child(title)
	_codex_list = ItemList.new()
	_codex_list.custom_minimum_size = Vector2(520, 520)
	_codex_list.item_selected.connect(_on_codex_selected)
	left.add_child(_codex_list)
	var close: Button = Button.new()
	close.text = "닫기"
	close.pressed.connect(_hide_panels)
	left.add_child(close)
	h.add_child(left)
	var right: VBoxContainer = VBoxContainer.new()
	_codex_table = Turntable.new()
	_codex_table.setup(Vector2i(420, 480))
	right.add_child(_codex_table)
	_codex_info = Label.new()
	_codex_info.custom_minimum_size = Vector2(420, 0)
	_codex_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_codex_info)
	h.add_child(right)
	_codex_panel.add_child(_margin(h, 20))
	_codex_panel.visible = false
	add_child(_codex_panel)


func _show_codex() -> void:
	_hide_panels()
	_codex_list.clear()
	_codex_ids.clear()
	for t: Dictionary in store.maps["atrium"]["types"]:
		var tid: String = String(t["id"])
		for v: Dictionary in store.type_data("mall_guest", tid)["variants"]:
			if not store.milestone_ok(String(v.get("milestone", "M0"))):
				continue
			var vid: String = String(v["id"])
			var st: String = records.codex_state(vid)
			var label: String = "%s · 등급 %d · %s" % [String(t["name_ko"]), int(v["difficulty"]), String(v["name_ko"]) if st != "" else "???"]
			label = ("[찾음] " if st == "found" else ("[봄] " if st == "seen" else "[ ? ] ")) + label
			_codex_list.add_item(label)
			_codex_ids.append(vid)
	_codex_table.visible = false
	_codex_info.text = "항목을 고르면 기준 인물과 나란히 보여 준다. 아직 만나지 못한 변이는 내용이 가려져 있다."
	_sub_open(true)
	_codex_panel.visible = true
	_panel_layout.call_deferred(_codex_panel)


func _on_codex_selected(i: int) -> void:
	var vid: String = _codex_ids[i]
	var found: Dictionary = store.find_variant("mall_guest", vid)
	var v: Dictionary = found["variant"]
	var tid: String = String(found["type"])
	var st: String = records.codex_state(vid)
	if st == "":
		_codex_table.visible = false
		_codex_info.text = "아직 만나지 못한 변이다. 등급 %d · 부위 %s" % [int(v["difficulty"]), Hud.GROUP_KO.get(String(v["group"]), "")]
		return
	var base: Dictionary = Appearance.base_from(store.type_data("mall_guest", tid)["appearance"]["slots"])
	var var_app: Dictionary = Appearance.apply_op(base, v["op"])
	var scene: String = store.type_scene("mall_guest", tid)
	_codex_table.visible = true
	_codex_table.show_models([{"app": base, "scene": scene, "label": "기준"}, {"app": var_app, "scene": scene, "label": "변이"}], mats)
	_codex_table.highlight(1, String(v["op"]["slot"]))
	if String(v["op"]["type"]) == "hide":
		_codex_table.highlight(0, String(v["op"]["slot"]))
	var e: Dictionary = records.data["codex"][vid]
	var dirs: PackedStringArray = []
	for d: Variant in v["visible_from"]:
		dirs.append(String(GRADE_DIR_KO.get(String(d), String(d))))
	_codex_info.text = "%s\n등급 %d · %s에서 %.0f m 안쪽\n찾음: %s · 봄: %s" % [v["name_ko"], int(v["difficulty"]), "·".join(dirs), float(v["identify_distance_m"]),
		String(e.get("found", "")) if String(e.get("found", "")) != "" else "-", String(e.get("seen", "")) if String(e.get("seen", "")) != "" else "-"]
