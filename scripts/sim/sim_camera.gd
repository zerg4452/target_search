class_name SimCamera
extends ObserverView
## 3인칭 카메라의 수학 모델. 게임의 Camera3D는 매 틱 이 값(위치·방향·FOV)을 그대로 따라간다.
## 그래서 화면에 그려지는 범위와 '관찰됨' 판정의 범위가 같다. 테스트에서는 이 객체를 직접 배치한다.

var eye: Vector3 = Vector3(0.0, 1.6, 3.0)
var basis: Basis = Basis.IDENTITY
var fov_deg: float = 65.0        ## 세로 FOV (Camera3D.KEEP_HEIGHT와 같은 정의)
var aspect: float = 16.0 / 9.0
var near: float = 0.05
var body_pos: Vector3 = Vector3.ZERO


func get_eye_position() -> Vector3:
	return eye


func get_body_position() -> Vector3:
	return body_pos


func forward() -> Vector3:
	return -basis.z


func is_in_expanded_view(point: Vector3, margin: float) -> bool:
	var local: Vector3 = basis.transposed() * (point - eye)
	var depth: float = -local.z
	if depth <= near:
		return false
	var t: float = tan(deg_to_rad(fov_deg) * 0.5)
	var lim: float = 1.0 + 2.0 * margin
	return absf(local.y / (depth * t)) <= lim and absf(local.x / (depth * t * aspect)) <= lim


## 디버그·테스트용: 화면 좌표(-1..1)로 투영. 뒤쪽이면 null.
func project_ndc(point: Vector3) -> Variant:
	var local: Vector3 = basis.transposed() * (point - eye)
	var depth: float = -local.z
	if depth <= near:
		return null
	var t: float = tan(deg_to_rad(fov_deg) * 0.5)
	return Vector2(local.x / (depth * t * aspect), local.y / (depth * t))


func copy_from(other: SimCamera) -> void:
	eye = other.eye
	basis = other.basis
	fov_deg = other.fov_deg
	aspect = other.aspect
	near = other.near
	body_pos = other.body_pos
