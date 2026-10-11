extends SceneTree
## 헤드리스 테스트 실행기.
## 사용: godot_console --headless --path . --script res://tests/run_tests.gd [-- --filter=이름일부]
## 실패가 하나라도 있으면 종료 코드 1.

const TEST_DIR: String = "res://tests"

var _started: bool = false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_all()
	return false


func _run_all() -> void:
	var filter: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
	var passed: int = 0
	var failed: int = 0
	for path: String in _find_test_files():
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("FAIL  %s : 스크립트를 불러올 수 없음" % path)
			failed += 1
			continue
		for method_name: String in _test_method_names(script):
			var full_name: String = "%s::%s" % [path.get_file().get_basename(), method_name]
			if filter != "" and not full_name.contains(filter):
				continue
			var obj: Object = script.new()
			var tc: TestCase = obj as TestCase
			if tc == null:
				print("FAIL  %s : TestCase를 상속하지 않음" % full_name)
				failed += 1
				continue
			var t0: int = Time.get_ticks_msec()
			var ret: Variant = obj.call(method_name)
			var ms: int = Time.get_ticks_msec() - t0
			var completed: bool = typeof(ret) == TYPE_BOOL and ret == true
			if completed and tc.failures.is_empty():
				passed += 1
				print("PASS  %s (%d ms)" % [full_name, ms])
			else:
				failed += 1
				print("FAIL  %s (%d ms)" % [full_name, ms])
				if not completed:
					print("      - 테스트가 끝까지 실행되지 않음(스크립트 오류 또는 true 미반환)")
				for f: String in tc.failures:
					print("      - %s" % f)
			for note: String in tc.notes:
				print("      · %s" % note)
	print("")
	print("결과: 통과 %d, 실패 %d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _find_test_files() -> PackedStringArray:
	var out: PackedStringArray = []
	for f: String in DirAccess.get_files_at(TEST_DIR):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append("%s/%s" % [TEST_DIR, f])
	out.sort()
	return out


func _test_method_names(script: GDScript) -> Array[String]:
	var names: Array[String] = []
	for m: Dictionary in script.get_script_method_list():
		var n: String = m["name"]
		if n.begins_with("test_") and not names.has(n):
			names.append(n)
	names.sort()
	return names
