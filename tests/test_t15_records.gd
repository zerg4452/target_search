extends TestCase
## T-15: 기록·도감·직전 변이·일일 시드 저장(§10.2, §10.3, §13.9)과 설정 저장(§11.4).

const TMP: String = "user://test_records.json"
const TMP_CFG: String = "user://test_settings.cfg"


func _clean() -> void:
	for p: String in [TMP, TMP + ".tmp", TMP + ".broken", TMP + ".v0.bak", TMP_CFG]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _win(vid: String, score: int, found_in: String = "SEARCH") -> Dictionary:
	return {"outcome": "WIN", "win": true, "found_in": found_in, "score": score, "remaining": 29, "match_time": 80.0, "variant_id": vid}


func test_records_roundtrip_and_codex() -> bool:
	_clean()
	var r: Records = Records.load_from(TMP)
	eq(r.games(), 0, "새 기록")
	check(not r.hard_unlocked(), "어려움은 처음에 잠김")
	var meta: Dictionary = {"preset": "standard", "date": "2026-10-12", "fov_deg": 70.0, "exclusion": 3}
	var out: Dictionary = r.apply_result(_win("VA01_BAG_MIRROR", 4000), meta)
	check(bool(out["new_best"]), "첫 승리는 최고 점수")
	check(bool(out["hard_unlocked_now"]), "표준 승리로 어려움이 열림")
	eq(String(out["codex_new"]), "VA01_BAG_MIRROR", "도감 새 항목")
	r.apply_result({"outcome": "LOSE_ALL_GONE", "win": false, "variant_id": "VB02_GLASSES_MISSING", "remaining": 0, "match_time": 290.0}, meta)
	eq(r.save(), OK, "저장")
	check(not FileAccess.file_exists(TMP + ".tmp"), "임시 파일이 남지 않음")
	var r2: Records = Records.load_from(TMP)
	eq(r2.games(), 2, "판 수")
	check(r2.hard_unlocked(), "어려움 열림 유지")
	eq(r2.codex_state("VA01_BAG_MIRROR"), "found", "찾은 변이")
	eq(r2.codex_state("VB02_GLASSES_MISSING"), "seen", "본 변이(패배 후 공개)")
	eq(r2.codex_state("VC01_BACKPACK_ONE_STRAP"), "", "만나지 못한 변이")
	var rec: Dictionary = r2.data["records"]["standard"]
	eq(int(rec["wins"]), 1, "승")
	eq(int(rec["losses"]), 1, "패")
	eq(int(rec["search_finds"]), 1, "1단계 발견")
	eq(int(rec["best_score"]), 4000, "최고 점수")
	check(absf(float(rec["best_score_fov"]) - 70.0) < 0.01, "최고 점수와 함께 FOV를 남김(§11.4)")
	_clean()
	return true


func test_recent_variants_keep_last_three() -> bool:
	var r: Records = Records.new()
	r.data = Records.empty_data()
	var meta: Dictionary = {"preset": "practice", "date": "2026-10-12", "exclusion": 3}
	for vid: String in ["V1", "V2", "V3", "V4", "V2"]:
		r.apply_result(_win(vid, 100, "HUNT"), meta)
	eq(str(r.recent_variants()), str(["V3", "V4", "V2"]), "직전 3판, 중복은 가장 최근으로")
	return true


func test_unrecorded_matches_change_nothing() -> bool:
	var r: Records = Records.new()
	r.data = Records.empty_data()
	r.apply_result(_win("VA01_BAG_MIRROR", 4000), {"preset": "standard", "date": "2026-10-12", "recorded": false})
	eq(r.games(), 0, "같은 시드로 다시·디버그 판은 기록하지 않음")
	eq(r.codex_state("VA01_BAG_MIRROR"), "", "도감도 바꾸지 않음")
	check(r.recent_variants().is_empty(), "직전 변이도 바꾸지 않음")
	return true


func test_daily_seed_counts_first_result_only() -> bool:
	eq(Records.daily_seed("2026-10-12"), Records.daily_seed("2026-10-12"), "같은 날 같은 시드")
	check(Records.daily_seed("2026-10-12") != Records.daily_seed("2026-10-13"), "날짜가 다르면 다른 시드")
	var r: Records = Records.new()
	r.data = Records.empty_data()
	var meta: Dictionary = {"preset": "standard", "date": "2026-10-12", "daily": true}
	var a: Dictionary = r.apply_result({"outcome": "LOSE_ALL_GONE", "win": false, "variant_id": "VA02_SHOES_LOAFER", "remaining": 0, "match_time": 280.0}, meta)
	var b: Dictionary = r.apply_result(_win("VA02_SHOES_LOAFER", 3000), meta)
	check(bool(a["daily_counted"]), "첫 결과는 기록")
	check(not bool(b["daily_counted"]), "다시 해도 처음 결과만 남음")
	check(not bool(r.data["daily"]["2026-10-12"]["win"]), "남은 결과는 첫 판(패배)")
	## 일일 시드 판은 누구에게나 같은 판이어야 하므로 직전 변이 제외 없이 구성한다(main.gd).
	var store: DataStore = SimFixture.store()
	var s1: MatchSetup = MatchSetup.build(store, SimFixture.layout(), "standard", "atrium", Records.daily_seed("2026-10-12"))
	var s2: MatchSetup = MatchSetup.build(store, SimFixture.layout(), "standard", "atrium", Records.daily_seed("2026-10-12"))
	eq(s1.variant_id, s2.variant_id, "일일 시드 판 구성 재현")
	return true


func test_broken_and_old_files_are_preserved() -> bool:
	_clean()
	var f: FileAccess = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var r: Records = Records.load_from(TMP)
	check(FileAccess.file_exists(TMP + ".broken"), "망가진 파일 보존")
	check(r.load_note != "", "알림")
	eq(r.games(), 0, "새로 시작")
	var f2: FileAccess = FileAccess.open(TMP, FileAccess.WRITE)
	f2.store_string(JSON.stringify({"version": 0, "games": 5, "unlocked_hard": true}))
	f2.close()
	var r2: Records = Records.load_from(TMP)
	check(FileAccess.file_exists(TMP + ".v0.bak"), "이전 버전 파일 보존")
	eq(r2.games(), 5, "이전 값 이어받기")
	_clean()
	return true


func test_settings_roundtrip_and_rebind() -> bool:
	_clean()
	InputSetup.ensure_actions()
	var s: AppSettings = AppSettings.load_from(TMP_CFG)
	check(absf(s.get_f("fov_deg") - 65.0) < 0.01, "기본 FOV 65°")
	s.values["fov_deg"] = 120.0
	s.values["invert_y"] = true
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = KEY_G
	s.rebind("interact", ev)
	eq(s.save(), OK, "설정 저장")
	var s2: AppSettings = AppSettings.load_from(TMP_CFG)
	check(absf(s2.get_f("fov_deg") - AppSettings.FOV_RANGE.y) < 0.01, "FOV는 55~80°로 제한")
	check(s2.get_b("invert_y"), "Y축 반전 유지")
	eq(s2.binding_text("interact"), OS.get_keycode_string(KEY_G), "재지정 유지")
	s2.apply_input()
	var found: bool = false
	for e: InputEvent in InputMap.action_get_events("interact"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_G:
			found = true
	check(found, "InputMap에 반영")
	## 다른 동작과 겹치면 그 동작에서 뺀다.
	var ev2: InputEventKey = InputEventKey.new()
	ev2.physical_keycode = KEY_G
	s2.rebind("accuse", ev2)
	check(s2.binding_text("interact") == "(없음)", "겹친 키는 원래 동작에서 빠짐")
	s2.reset_input()
	_clean()
	return true


func test_fov_option_changes_observation() -> bool:
	## FOV 옵션은 관찰 판정에도 그대로 쓰인다(§11.4). 넓히면 보호 범위가 넓어진다.
	var narrow: MatchSim = SimFixture.make(5, {"fov_deg": 55.0})
	var wide: MatchSim = SimFixture.make(5, {"fov_deg": 80.0})
	check(absf(narrow.camera.fov_deg - 55.0) < 0.01, "좁은 FOV 반영")
	check(absf(wide.camera.fov_deg - 80.0) < 0.01, "넓은 FOV 반영")
	var p: Vector3 = wide.camera.eye + wide.camera.forward() * 10.0 + wide.camera.basis.y * 6.2
	check(wide.camera.is_in_expanded_view(p, 0.0) and not narrow.camera.is_in_expanded_view(p, 0.0), "넓은 FOV에서만 보이는 점")
	return true
