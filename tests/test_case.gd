class_name TestCase
extends RefCounted
## 테스트 기반 클래스. test_로 시작하는 메서드는 끝에서 true를 반환한다.

var failures: PackedStringArray = []
var notes: PackedStringArray = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(a: Variant, b: Variant, msg: String) -> void:
	if a != b:
		failures.append("%s (기대 %s, 실제 %s)" % [msg, str(b), str(a)])


func note(msg: String) -> void:
	notes.append(msg)
