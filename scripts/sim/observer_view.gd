class_name ObserverView
extends RefCounted
## 가시성 판정이 보는 '플레이어의 눈'(§13.7). VisibilityService는 Camera3D를 직접 참조하지 않는다.


## 레이캐스트 원점 (카메라 위치)
func get_eye_position() -> Vector3:
	return Vector3.ZERO


## 근접 안전지대의 기준 (플레이어 몸 위치)
func get_body_position() -> Vector3:
	return Vector3.ZERO


## 뷰포트를 margin 비율만큼 사방으로 넓힌 화면 안에 점이 투영되는지
func is_in_expanded_view(_point: Vector3, _margin: float) -> bool:
	return false
