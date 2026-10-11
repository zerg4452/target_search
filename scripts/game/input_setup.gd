class_name InputSetup
extends RefCounted
## InputMap 액션을 코드에서 등록한다(§4.1). 이미 있는 액션은 건드리지 않는다. 재지정은 AppSettings가 덮어쓴다.

const KEYS: Dictionary = {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"interact": [KEY_E],
	"accuse": [KEY_F],
	"reference": [KEY_TAB],
	"pause": [KEY_ESCAPE],
	"skip": [KEY_SPACE, KEY_ENTER],
	"restart": [KEY_R],
	"replay_same": [KEY_T],
	"to_menu": [KEY_M],
	"debug_overlay": [KEY_F1],
	"debug_hunt": [KEY_F2],
	"debug_hint": [KEY_F3],
}
const MOUSE: Dictionary = {
	"observe": [MOUSE_BUTTON_RIGHT],
}


static func ensure_actions() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code: int in KEYS[action]:
			var ev: InputEventKey = InputEventKey.new()
			ev.physical_keycode = code as Key
			InputMap.action_add_event(action, ev)
	for action2: String in MOUSE:
		if InputMap.has_action(action2):
			continue
		InputMap.add_action(action2)
		for button: int in MOUSE[action2]:
			var mev: InputEventMouseButton = InputEventMouseButton.new()
			mev.button_index = button as MouseButton
			InputMap.action_add_event(action2, mev)
