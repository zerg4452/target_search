class_name MaterialCache
extends RefCounted
## 같은 머티리얼 ID는 같은 리소스를 공유한다. 일반 NPC끼리 렌더 차이가 생기지 않게 한다(§6.8).
## 모든 NPC 머티리얼은 같은 기능 조합(StandardMaterial3D + 명도·노멀·거칠기 세부 텍스처, 값만 다름)이라 셰이더가 하나다.
## 그래서 타겟의 변이 머티리얼이 처음 화면에 나와도 셰이더 컴파일 끊김이 생기지 않는다(§11.2 2번).
## 세부 텍스처(D-33)는 팔레트의 detail 이름으로 고른다. 같은 ID는 늘 같은 텍스처라 개체마다 다른 무늬는 없다.

const TEX_DIR: String = "res://assets/textures/"

static var _textures: Dictionary = {}

var _palette: Dictionary = {}
var _details: Dictionary = {}
var _stats: Dictionary = {}
var _cache: Dictionary = {}


## details: data/material_details.json의 details. stats: assets/textures/textures.manifest.json의 textures.
## details가 비면 세부 텍스처 없이 단색으로 만든다.
func _init(palette: Dictionary, details: Dictionary = {}, stats: Dictionary = {}) -> void:
	_palette = palette
	_details = details
	_stats = stats


static func for_store(store: DataStore, palette: Dictionary) -> MaterialCache:
	return MaterialCache.new(palette, store.material_details.get("details", {}), store.texture_stats.get("textures", {}))


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
		apply_detail(m, String((d as Dictionary).get("detail", "smooth")), false)
		_apply_surface_look(m, String((d as Dictionary).get("detail", "smooth")))
	else:
		m.albedo_color = Color(1.0, 0.0, 1.0)
		apply_detail(m, "smooth", false)
		_apply_surface_look(m, "smooth")
	m.resource_name = id
	_cache[id] = m
	return m


## 세부 텍스처를 붙인다. world면 월드 좌표 삼면 투영(아레나), 아니면 메시 UV(1 UV = 1 m, NPC).
## 명도 텍스처의 선형 평균으로 알베도를 나눠, 텍스처를 붙여도 평균 명도가 팔레트 값과 같게 한다.
func apply_detail(m: StandardMaterial3D, detail: String, world: bool) -> void:
	if _details.is_empty() or not _details.has(detail):
		return
	var det: Dictionary = _details[detail]
	var mean: float = float((_stats.get(detail, {}) as Dictionary).get("albedo_linear_mean", 1.0))
	if mean > 0.01 and mean < 0.999:
		var lin: Color = m.albedo_color.srgb_to_linear()
		m.albedo_color = Color(lin.r / mean, lin.g / mean, lin.b / mean, m.albedo_color.a).linear_to_srgb()
	m.albedo_texture = texture(detail + "_a")
	m.normal_enabled = true
	m.normal_texture = texture(detail + "_n")
	m.normal_scale = float(det.get("normal", 0.5))
	m.roughness_texture = texture(detail + "_r")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var k: float = 1.0 / maxf(float(det.get("tile_m", 1.0)), 0.001)
	m.uv1_scale = Vector3(k, k, k)
	if world:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


## 인물 재질 공통(D-35): 미리 구운 주변광 차폐(꼭짓점 색)를 알베도에 곱하고, 피부 표면하 산란과 옷감 윤곽광을 쓴다.
## 기능은 모든 인물 재질에 똑같이 켜고 값만 다르게 둬서 셰이더가 하나로 유지된다(§11.2 2번).
func _apply_surface_look(m: StandardMaterial3D, detail: String) -> void:
	if _details.is_empty():
		return
	var det: Dictionary = _details.get(detail, {})
	m.vertex_color_use_as_albedo = true
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = float(det.get("sss", 0.0))
	m.rim_enabled = true
	m.rim = float(det.get("rim", 0.0))
	m.rim_tint = 0.6


static func texture(tex_name: String) -> Texture2D:
	if not _textures.has(tex_name):
		var t: Texture2D = load(TEX_DIR + tex_name + ".png") as Texture2D
		if t == null:
			push_error("세부 텍스처를 불러올 수 없음: %s" % tex_name)
		_textures[tex_name] = t
	return _textures[tex_name]


## 종료할 때 공용 텍스처 캐시를 비운다.
static func clear_textures() -> void:
	_textures.clear()


func ids() -> Array:
	return _palette.keys()


static func flat(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
