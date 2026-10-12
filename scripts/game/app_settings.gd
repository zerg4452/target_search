class_name AppSettings
extends RefCounted
## 설정(§11.4, §13.9): user://settings.cfg(ConfigFile). 입력 재지정, 감도, Y축 반전, FOV, 관찰 토글,
## 음량, 자막, 소리 방향 표시, 깜빡임 줄이기, UI 글자 크기.

const DEFAULT_PATH: String = "user://settings.cfg"
const REBINDABLE: Array[String] = ["move_forward", "move_back", "move_left", "move_right", "run", "observe", "interact", "accuse", "reference", "pause"]
const ACTION_KO: Dictionary = {
	"move_forward": "앞으로", "move_back": "뒤로", "move_left": "왼쪽", "move_right": "오른쪽", "run": "달리기",
	"observe": "관찰 모드", "interact": "호출 / 조사", "accuse": "지목(누르고 있기)", "reference": "기준 외형 보기", "pause": "일시정지",
}
const DEFAULTS: Dictionary = {
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"fov_deg": 65.0,
	"observe_toggle": false,
	"volume_master": 0.9,
	"volume_music": 0.55,
	"volume_sfx": 0.9,
	"subtitles": true,
	"sound_direction": false,
	"reduce_flashing": false,
	"ui_scale": 1.0,
	"graphics_quality": "",   ## data/graphics_quality.json의 단계 id. 비면 기본 단계
}
const FOV_RANGE: Vector2 = Vector2(55.0, 80.0)
const UI_SCALES: Array[float] = [0.85, 1.0, 1.2, 1.4]

var values: Dictionary = DEFAULTS.duplicate()
var bindings: Dictionary = {}   ## action -> Array[Dictionary] {"key": physical_keycode} 또는 {"mouse": button}
var path: String = DEFAULT_PATH


static func load_from(p_path: String = DEFAULT_PATH) -> AppSettings:
	var s: AppSettings = AppSettings.new()
	s.path = p_path
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(p_path) == OK:
		for key: String in DEFAULTS:
			s.values[key] = cf.get_value("options", key, DEFAULTS[key])
		for action: String in REBINDABLE:
			var b: Variant = cf.get_value("input", action, null)
			if typeof(b) == TYPE_ARRAY:
				s.bindings[action] = b
	s.values["fov_deg"] = clampf(float(s.values["fov_deg"]), FOV_RANGE.x, FOV_RANGE.y)
	return s


func save() -> Error:
	var cf: ConfigFile = ConfigFile.new()
	for key: String in values:
		cf.set_value("options", key, values[key])
	for action: String in bindings:
		cf.set_value("input", action, bindings[action])
	return cf.save(path)


func get_f(key: String) -> float:
	return float(values.get(key, DEFAULTS.get(key, 0.0)))


func get_b(key: String) -> bool:
	return bool(values.get(key, DEFAULTS.get(key, false)))


## 저장된 재지정을 InputMap에 반영한다. 없으면 기본(InputSetup)을 둔다.
func apply_input() -> void:
	for action: String in bindings:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for e: Dictionary in bindings[action]:
			var ev: InputEvent = event_from(e)
			if ev != null:
				InputMap.action_add_event(action, ev)


func rebind(action: String, ev: InputEvent) -> void:
	var d: Dictionary = describe_event(ev)
	if d.is_empty():
		return
	## 같은 입력이 다른 동작에 묶여 있으면 그 동작에서 뺀다.
	for other: String in REBINDABLE:
		if other == action:
			continue
		var list: Array = current_binding(other)
		var kept: Array = []
		for e: Dictionary in list:
			if e != d:
				kept.append(e)
		if kept.size() != list.size():
			bindings[other] = kept
	bindings[action] = [d]
	apply_input()


func reset_input() -> void:
	bindings.clear()
	for action: String in REBINDABLE:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	InputSetup.ensure_actions()


func current_binding(action: String) -> Array:
	if bindings.has(action):
		return bindings[action]
	var out: Array = []
	if InputMap.has_action(action):
		for ev: InputEvent in InputMap.action_get_events(action):
			var d: Dictionary = describe_event(ev)
			if not d.is_empty():
				out.append(d)
	return out


static func describe_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k: InputEventKey = ev as InputEventKey
		var code: int = int(k.physical_keycode) if k.physical_keycode != KEY_NONE else int(k.keycode)
		return {"key": code}
	if ev is InputEventMouseButton:
		return {"mouse": int((ev as InputEventMouseButton).button_index)}
	return {}


static func event_from(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var k: InputEventKey = InputEventKey.new()
		k.physical_keycode = int(d["key"]) as Key
		return k
	if d.has("mouse"):
		var m: InputEventMouseButton = InputEventMouseButton.new()
		m.button_index = int(d["mouse"]) as MouseButton
		return m
	return null


static func label_of(d: Dictionary) -> String:
	if d.has("key"):
		return OS.get_keycode_string(int(d["key"]) as Key)
	if d.has("mouse"):
		match int(d["mouse"]):
			MOUSE_BUTTON_LEFT: return "마우스 왼쪽"
			MOUSE_BUTTON_RIGHT: return "마우스 오른쪽"
			MOUSE_BUTTON_MIDDLE: return "마우스 가운데"
		return "마우스 %d" % int(d["mouse"])
	return "?"


func binding_text(action: String) -> String:
	var parts: PackedStringArray = []
	for d: Dictionary in current_binding(action):
		parts.append(label_of(d))
	return " / ".join(parts) if not parts.is_empty() else "(없음)"
