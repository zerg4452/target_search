class_name PreviewStage
extends RefCounted
## 기준 외형 보기·브리핑·결과 턴테이블·시각 검사가 함께 쓰는 중립 조명 무대.
## 아레나의 1단계 조명과 같은 방향광·환경광 값을 쓴다(§12.6: 실제 게임과 같은 조명으로 판단).

const SUN_ROT_DEG: Vector3 = Vector3(-50.0, 30.0, 0.0)
const SUN_ENERGY: float = 1.15
const SUN_COLOR: Color = Color(1.0, 0.95, 0.86)
const AMBIENT_COLOR: Color = Color(0.86, 0.86, 0.9)
const AMBIENT_ENERGY: float = 0.7


static func add_lighting(parent: Node3D, background: Color = Color(0.32, 0.33, 0.36)) -> WorldEnvironment:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = SUN_ROT_DEG
	sun.light_energy = SUN_ENERGY
	sun.light_color = SUN_COLOR
	sun.shadow_enabled = true
	parent.add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 200.0, 0.0)
	fill.light_energy = 0.35
	parent.add_child(fill)
	var we: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	parent.add_child(we)
	var floor_mi: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(12.0, 12.0)
	floor_mi.mesh = pm
	floor_mi.material_override = MaterialCache.flat(Color(0.62, 0.6, 0.57), 0.7)
	parent.add_child(floor_mi)
	return we


## 인물(정면 -Z)을 그 방향에서 보는 카메라 쪽 단위 벡터. left = 인물의 왼쪽.
static func view_dir(view: String) -> Vector3:
	match view:
		"back":
			return Vector3(0.0, 0.0, 1.0)
		"left":
			return Vector3(-1.0, 0.0, 0.0)
		"right":
			return Vector3(1.0, 0.0, 0.0)
		"top":
			return Vector3(0.0, 1.0, -1.0).normalized()
	return Vector3(0.0, 0.0, -1.0)
