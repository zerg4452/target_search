class_name SettingsPanel
extends PanelContainer
## 설정 화면(§11.4). 메인 메뉴와 일시정지 메뉴에서 같이 쓴다. 바꾸면 바로 저장하고 changed를 알린다.

signal changed
signal closed

var settings: AppSettings
var _waiting_action: String = ""
var _bind_buttons: Dictionary = {}
var _fov_label: Label
var _sens_label: Label


func setup(p_settings: AppSettings) -> void:
	settings = p_settings
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	var title: Label = Label.new()
	title.text = "설정"
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	root.add_child(cols)
	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(420, 0)
	cols.add_child(left)
	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size = Vector2(420, 0)
	cols.add_child(right)
	_sens_label = _slider(left, "마우스 감도", "mouse_sensitivity", 0.25, 3.0, 0.05, func(v: float) -> String: return "%.2f배" % v)
	_fov_label = _slider(left, "시야각(FOV)", "fov_deg", AppSettings.FOV_RANGE.x, AppSettings.FOV_RANGE.y, 1.0, func(v: float) -> String: return "%d°" % int(v))
	var fov_note: Label = Label.new()
	fov_note.text = "넓히면 화면에 보이는 범위가 넓어지고, 그만큼 '보이는 곳에서는 제거되지 않는' 범위도 넓어진다. 기록에 함께 남는다."
	fov_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fov_note.custom_minimum_size = Vector2(400, 0)
	fov_note.add_theme_font_size_override("font_size", 14)
	left.add_child(fov_note)
	_check(left, "Y축 반전", "invert_y")
	_check(left, "관찰 모드: 누르고 있기 대신 토글", "observe_toggle")
	_slider(left, "전체 음량", "volume_master", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d%%" % int(v * 100.0))
	_slider(left, "음악", "volume_music", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d%%" % int(v * 100.0))
	_slider(left, "효과음", "volume_sfx", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d%%" % int(v * 100.0))
	_check(left, "자막(안내 방송)", "subtitles")
	_check(left, "소리 방향 표시(제거음)", "sound_direction")
	_check(left, "조명 깜빡임·화면 효과 줄이기", "reduce_flashing")
	var ui_row: HBoxContainer = HBoxContainer.new()
	var ui_l: Label = Label.new()
	ui_l.text = "UI 글자 크기"
	ui_l.custom_minimum_size = Vector2(160, 0)
	ui_row.add_child(ui_l)
	var ob: OptionButton = OptionButton.new()
	for sc: float in AppSettings.UI_SCALES:
		ob.add_item("%d%%" % int(sc * 100.0))
	ob.select(maxi(AppSettings.UI_SCALES.find(settings.get_f("ui_scale")), 0))
	ob.item_selected.connect(func(i: int) -> void:
		settings.values["ui_scale"] = AppSettings.UI_SCALES[i]
		_commit())
	ui_row.add_child(ob)
	left.add_child(ui_row)
	var kt: Label = Label.new()
	kt.text = "키 재지정 (버튼을 누른 뒤 새 키를 누른다)"
	right.add_child(kt)
	for action: String in AppSettings.REBINDABLE:
		var row: HBoxContainer = HBoxContainer.new()
		var al: Label = Label.new()
		al.text = String(AppSettings.ACTION_KO[action])
		al.custom_minimum_size = Vector2(190, 0)
		row.add_child(al)
		var b: Button = Button.new()
		b.custom_minimum_size = Vector2(200, 34)
		b.text = settings.binding_text(action)
		b.pressed.connect(func() -> void:
			_waiting_action = action
			b.text = "… 입력 대기 (Esc 취소)")
		row.add_child(b)
		_bind_buttons[action] = b
		right.add_child(row)
	var reset: Button = Button.new()
	reset.text = "키 설정 초기화"
	reset.pressed.connect(func() -> void:
		settings.reset_input()
		_refresh_bindings()
		_commit())
	right.add_child(reset)
	var close: Button = Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(200, 44)
	close.pressed.connect(func() -> void: closed.emit())
	root.add_child(close)
	var mc: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, 24)
	mc.add_child(root)
	add_child(mc)


func _slider(parent: Control, text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	var l: Label = Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(160, 0)
	row.add_child(l)
	var s: HSlider = HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = settings.get_f(key)
	s.custom_minimum_size = Vector2(170, 24)
	row.add_child(s)
	var vl: Label = Label.new()
	vl.text = fmt.call(s.value)
	vl.custom_minimum_size = Vector2(70, 0)
	row.add_child(vl)
	s.value_changed.connect(func(v: float) -> void:
		settings.values[key] = v
		vl.text = fmt.call(v)
		_commit())
	parent.add_child(row)
	return vl


func _check(parent: Control, text: String, key: String) -> void:
	var c: CheckBox = CheckBox.new()
	c.text = text
	c.button_pressed = settings.get_b(key)
	c.toggled.connect(func(on: bool) -> void:
		settings.values[key] = on
		_commit())
	parent.add_child(c)


func _commit() -> void:
	settings.save()
	changed.emit()


func _refresh_bindings() -> void:
	for action: String in _bind_buttons:
		(_bind_buttons[action] as Button).text = settings.binding_text(action)


func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not visible:
		return
	var accepted: bool = false
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).physical_keycode != KEY_ESCAPE:
			settings.rebind(_waiting_action, event)
		accepted = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: MouseButton = (event as InputEventMouseButton).button_index
		if mb != MOUSE_BUTTON_LEFT and mb != MOUSE_BUTTON_WHEEL_UP and mb != MOUSE_BUTTON_WHEEL_DOWN:
			settings.rebind(_waiting_action, event)
			accepted = true
	if accepted:
		_waiting_action = ""
		_refresh_bindings()
		_commit()
		get_viewport().set_input_as_handled()
