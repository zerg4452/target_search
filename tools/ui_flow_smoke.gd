extends SceneTree
## 화면 흐름 연기 검사: 메뉴 → 연습 판 → 결과 → 메뉴 → 오늘의 도전 → 일시정지 → 설정 → 메뉴.
## 스크립트 오류 없이 전환되는지와 기록 반영을 확인한다. 실제 사용자 기록·설정 대신 임시 파일을 쓴다.
## 사용: godot_console --headless --path . --script res://tools/ui_flow_smoke.gd   (종료 코드 0 = 통과)

const REC: String = "user://smoke_records.json"
const CFG: String = "user://smoke_settings.cfg"

var main: Node
var _fail: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i: int in n:
		await physics_frame


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)
		print("FAIL ", msg)
	else:
		print("ok   ", msg)


func _run() -> void:
	for p: String in [REC, CFG]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)
	main.records = Records.load_from(REC)
	main.settings.path = CFG
	main.menu.records = main.records
	_check(main.menu.visible, "처음에는 메뉴가 보임")
	# 1) 연습 판 → 승리 → 결과
	main._on_menu_start("practice", false)
	await _frames(3)
	_check(main.sim != null and main.sim.preset_id == "practice", "연습 판 시작")
	_check(not main.menu.visible and main.hud.visible, "판 중에는 메뉴가 숨고 HUD가 보임")
	main.sim.skip_intro()
	main.args.end_as = "win"   ## main.gd의 디버그 경로로 끝낸다(이벤트가 같은 틱에 처리됨)
	await _frames(90)
	main.args.end_as = ""
	await _frames(int(MatchSim.REVEAL_S * 60.0) + 20)
	_check(main.sim.phase == MatchSim.Phase.RESULTS, "정체 공개 뒤 결과 화면")
	_check(main.hud.results_box.visible, "결과 상자 표시")
	_check(main.records.games() == 1, "기록에 판 수 반영 (%d)" % main.records.games())
	_check(main.records.codex_state(main.sim.setup.variant_id) == "found", "도감에 찾은 변이")
	# 2) 메뉴로
	main.hud.result_action.emit("menu")
	await _frames(3)
	_check(main.menu.visible and main.sim == null, "결과 → 메뉴")
	# 3) 오늘의 도전 → 일시정지 → 설정 → 메뉴
	main._on_menu_start("standard", true)
	await _frames(3)
	_check(main.sim.match_seed == Records.daily_seed(Records.today()), "오늘의 도전 시드")
	main.sim.skip_intro()
	await _frames(30)
	main._pause_request = true
	await _frames(3)
	_check(main.sim.paused and main.hud.pause_box.visible, "일시정지 메뉴")
	main.hud.pause_action.emit("settings")
	await _frames(2)
	_check(main.pause_settings.visible, "일시정지 중 설정")
	main.pause_settings.closed.emit()
	await _frames(2)
	main.hud.pause_action.emit("resume")
	await _frames(3)
	_check(not main.sim.paused, "계속하기")
	main._pause_request = true
	await _frames(3)
	main.hud.pause_action.emit("menu")
	await _frames(3)
	_check(main.menu.visible, "일시정지 → 메뉴")
	_check(main.records.games() == 1, "끝내지 않은 판은 기록하지 않음")
	# 4) 메뉴 하위 화면
	for p2: String in ["codex", "records", "settings"]:
		main.menu.open_panel(p2)
		await _frames(2)
	main.menu._hide_panels()
	await _frames(2)
	_check(main.menu._main_box.visible, "하위 화면을 닫으면 메뉴 목록이 돌아옴")
	for p3: String in [REC, CFG]:
		if FileAccess.file_exists(p3):
			DirAccess.remove_absolute(p3)
	print("결과: 실패 %d" % _fail.size())
	quit(1 if not _fail.is_empty() else 0)
