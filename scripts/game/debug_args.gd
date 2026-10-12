class_name DebugArgs
extends RefCounted
## 명령줄 사용자 인자(§13.10). `godot --path . -- --seed=7 --skip-intro` 처럼 `--` 뒤에 쓴다.
## 판 관련 인자가 하나라도 있으면 메뉴를 건너뛰고 바로 판을 시작한다(direct).

var has_seed: bool = false
var match_seed: int = 0
var difficulty: String = "standard"
var variant: String = ""
var skip_intro: bool = false
var search_time: float = -1.0
var debug_overlay: bool = false
var screenshot: String = ""
var screenshot_at: float = 3.0
var yaw_deg: float = 0.0
var pitch_deg: float = -12.0
var force_hunt: bool = false
var face_trace: bool = false   ## 스크린샷 직전 카메라를 가장 최근 흔적으로 돌린다(시각 확인용)
var playtest_log: bool = false
var direct: bool = false
var panel: String = ""         ## 메뉴 스크린샷용: codex | records | settings
var end_as: String = ""        ## 디버그: 1초 뒤 판을 끝낸다 win | lose_all | lose_chances
var show_reference: bool = false
var pause_at: float = -1.0
var quality: String = ""       ## 이번 실행만 그래픽 품질 단계를 바꾼다(저장하지 않음): low | medium | high


static func parse(list: PackedStringArray) -> DebugArgs:
	var a: DebugArgs = DebugArgs.new()
	for raw: String in list:
		var key: String = raw
		var value: String = ""
		var eq: int = raw.find("=")
		if eq >= 0:
			key = raw.substr(0, eq)
			value = raw.substr(eq + 1)
		match key:
			"--seed":
				a.has_seed = true
				a.match_seed = int(value)
				a.direct = true
			"--difficulty":
				a.difficulty = value
				a.direct = true
			"--variant":
				a.variant = value
				a.direct = true
			"--skip-intro":
				a.skip_intro = true
				a.direct = true
			"--search-time":
				a.search_time = float(value)
				a.direct = true
			"--debug-overlay":
				a.debug_overlay = true
			"--screenshot":
				a.screenshot = value
			"--screenshot-at":
				a.screenshot_at = float(value)
			"--yaw":
				a.yaw_deg = float(value)
			"--pitch":
				a.pitch_deg = float(value)
			"--hunt":
				a.force_hunt = true
				a.direct = true
			"--face-trace":
				a.face_trace = true
			"--playtest-log":
				a.playtest_log = true
			"--play":
				a.direct = true
			"--panel":
				a.panel = value
			"--end":
				a.end_as = value
				a.direct = true
			"--show-reference":
				a.show_reference = true
			"--pause-at":
				a.pause_at = float(value)
			"--quality":
				a.quality = value
	return a


## 시드나 변이를 강제한 판은 기록·도감에 남기지 않는다.
func forces_match() -> bool:
	return has_seed or variant != "" or search_time >= 0.0 or force_hunt or end_as != ""
