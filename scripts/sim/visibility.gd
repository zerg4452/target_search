class_name Visibility
extends RefCounted
## '관찰됨' 판정(§7.1). 화면에 보일 수 있으면 관찰됨이다(보수적 판정).
## 1) 플레이어 몸과의 수평 거리 ≤ 안전지대 반경, 또는
## 2) 표본점(발·가슴·머리) 중 하나가 넓힌 화면 안 + 거리 한도 안 + 차폐물에 가리지 않음.


static func observed_now(npc_pos: Vector2, view: ObserverView, layout: ArenaLayout, vis: Dictionary) -> bool:
	var body: Vector3 = view.get_body_position()
	if Vector2(body.x, body.z).distance_to(npc_pos) <= float(vis["safe_radius_m"]):
		return true
	var eye: Vector3 = view.get_eye_position()
	var margin: float = float(vis["screen_margin_ratio"])
	var max_d: float = float(vis["max_distance_m"])
	for h: Variant in vis["sample_heights_m"]:
		var p: Vector3 = Vector3(npc_pos.x, float(h), npc_pos.y)
		if eye.distance_to(p) > max_d:
			continue
		if not view.is_in_expanded_view(p, margin):
			continue
		if layout.segment_blocked(eye, p):
			continue
		return true
	return false
