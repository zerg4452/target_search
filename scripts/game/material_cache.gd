class_name MaterialCache
extends RefCounted
## 같은 머티리얼 ID는 같은 리소스를 공유한다. 일반 NPC끼리 렌더 차이가 생기지 않게 한다(§6.8).
## 모든 NPC 머티리얼은 같은 기능 조합(StandardMaterial3D 기본 + 값만 다름)이라 셰이더가 하나다.
## 그래서 타겟의 변이 머티리얼이 처음 화면에 나와도 셰이더 컴파일 끊김이 생기지 않는다(§11.2 2번).

var _palette: Dictionary = {}
var _cache: Dictionary = {}


func _init(palette: Dictionary) -> void:
	_palette = palette


func get_mat(id: String) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	var d: Variant = _palette.get(id, null)
	if typeof(d) == TYPE_DICTIONARY:
		var c: Array = (d as Dictionary)["color"]
		m.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
		m.roughness = float((d as Dictionary).get("roughness", 0.8))
		m.metallic = float((d as Dictionary).get("metallic", 0.0))
		m.metallic_specular = float((d as Dictionary).get("specular", 0.5))
	else:
		m.albedo_color = Color(1.0, 0.0, 1.0)
	m.resource_name = id
	_cache[id] = m
	return m


func ids() -> Array:
	return _palette.keys()


static func flat(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

