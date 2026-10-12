class_name ArenaVisual
extends Node3D
## 에코 몰 아트리움(§9) 표시. Blender가 같은 배치 JSON으로 만든 glb를 세우고, 조명은 맵 데이터(lighting)로 만든다.
## 재질 세부 텍스처(map.art.materials → data/material_details.json)는 월드 좌표 삼면 투영으로 입힌다(D-33).
## 그래픽 품질 단계(data/graphics_quality.json)는 조명 효과만 바꾼다. 형상·재질은 단계와 무관하게 같다.
## 2단계 전환(§3.1): 0.5초 깜빡임 → 밝기 −15% + 붉은 비상등. '깜빡임 줄이기'면 부드럽게 바꾼다.
## 차폐 판정은 ArenaLayout(시뮬레이션)이 한다. 여기서는 보여 주기만 한다.

var sun: DirectionalLight3D
var env: Environment
var probe: ReflectionProbe
var _cfg: Dictionary = {}
var _art: Dictionary = {}
var _quality: Dictionary = {}
var _downlights: Array[OmniLight3D] = []
var _emergency: Array[OmniLight3D] = []
var _emergency_mat: StandardMaterial3D
var _water_mat: StandardMaterial3D
var _water_flow: Vector2 = Vector2.ZERO
var _jet_mat: StandardMaterial3D
var _jet_flow: float = 0.0
var _shop_lights: Array[OmniLight3D] = []
var _base_shop: float = 1.0
var _base_sun: float = 1.0
var _base_ambient: float = 1.0
var _base_down: float = 1.0
var _level: float = 1.0          ## 현재 밝기 배율
var _flicker_left: float = 0.0
var _flicker_total: float = 0.5
var _flicker_calm: bool = false
var _hunt: bool = false
var _blackout_left: float = 0.0
var _blackout_calm: bool = false
var _t: float = 0.0


## quality_id가 비면 graphics_quality.json의 기본 단계를 쓴다.
func build(layout: ArenaLayout, map: Dictionary, store: DataStore, quality_id: String = "") -> void:
	_cfg = map.get("lighting", {})
	_art = map.get("art", {})
	var ps: PackedScene = load(String(map.get("scene", ""))) as PackedScene
	if ps != null:
		var inst: Node3D = ps.instantiate() as Node3D
		inst.name = "ArenaArt"
		add_child(inst)
		_dress_materials(inst, store)
		var em: MeshInstance3D = inst.find_child("EmergencyStrips", true, false) as MeshInstance3D
		if em != null:
			_emergency_mat = StandardMaterial3D.new()
			_emergency_mat.albedo_color = Color(0.45, 0.08, 0.06)
			_emergency_mat.emission_enabled = true
			_emergency_mat.emission = Color(1.0, 0.12, 0.08)
			_emergency_mat.emission_energy_multiplier = 0.0
			em.material_override = _emergency_mat
		_add_shop_lights(inst)
		for node_name: Variant in _art.get("no_shadow_nodes", []):
			var mi: GeometryInstance3D = inst.find_child(String(node_name), true, false) as GeometryInstance3D
			if mi != null:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		push_error("아레나 glb를 불러올 수 없음: %s" % map.get("scene", ""))
	_build_lights(layout)
	apply_quality(store.graphics_level(quality_id))


## glb 재질 이름으로 세부 텍스처를 붙인다. 같은 이름은 한 리소스를 공유한다.
func _dress_materials(inst: Node, store: DataStore) -> void:
	var table: Dictionary = _art.get("materials", {})
	var screens: Dictionary = _art.get("screens", {})
	var glass_ids: Array = _art.get("glass_materials", [])
	var jet_id: String = String(_art.get("water_jet_material", ""))
	_jet_flow = float(_art.get("water_jet_flow_mps", 0.5))
	if table.is_empty() and screens.is_empty():
		return
	var mc: MaterialCache = MaterialCache.for_store(store, {})
	var done: Dictionary = {}
	var flow: Array = _art.get("water_flow_mps", [0.0, 0.0])
	_water_flow = Vector2(float(flow[0]), float(flow[1]))
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		for i: int in mi.mesh.get_surface_count():
			var src: BaseMaterial3D = mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			var id: String = String(src.resource_name)
			if screens.has(id) and not done.has(id):
				done[id] = _screen_material(String(screens[id]), float(_art.get("screen_energy", 1.3)))
			if glass_ids.has(id) and not done.has(id):
				done[id] = _glass_material(src)
			if id == jet_id and jet_id != "" and not done.has(id):
				_jet_mat = _water_jet_material(src, mc)
				done[id] = _jet_mat
			if not done.has(id) and not table.has(id):
				continue
			if not done.has(id):
				var m: StandardMaterial3D = StandardMaterial3D.new()
				m.albedo_color = src.albedo_color
				m.roughness = src.roughness
				m.metallic = src.metallic
				m.cull_mode = src.cull_mode   ## Blender 재질은 양면이다. 같게 둔다
				m.resource_name = id
				mc.apply_detail(m, String(table[id]), true)
				if id == String(_art.get("water_material", "")):
					_water_mat = m
				done[id] = m
			mi.set_surface_override_material(i, done[id])


## 반투명 유리(가게 진열창·회랑 난간). 장식일 뿐 차폐 판정과 무관하다.
func _glass_material(src: BaseMaterial3D) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(src.albedo_color.r, src.albedo_color.g, src.albedo_color.b, 0.14)
	m.roughness = 0.04
	m.metallic_specular = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.resource_name = "glass"
	return m


## 흘러내리는 분수 물(반투명, 물결 노멀이 아래로 흐른다).
func _water_jet_material(src: BaseMaterial3D, mc: MaterialCache) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(src.albedo_color.r, src.albedo_color.g, src.albedo_color.b, 0.42)
	m.roughness = 0.05
	m.metallic_specular = 0.7
	mc.apply_detail(m, "water", false)
	m.albedo_texture = null
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_scale = Vector3(4.0, 3.0, 1.0)
	m.resource_name = "water_jet"
	return m


## 열린 가게 내부 조명: glb의 ShopLight_* 자리에 둔다.
func _add_shop_lights(inst: Node) -> void:
	var sl: Dictionary = _cfg.get("shop_lights", {})
	if sl.is_empty():
		return
	_base_shop = float(sl.get("energy", 1.2))
	for n: Node in inst.find_children("ShopLight_*", "Node3D", true, false):
		var l: OmniLight3D = OmniLight3D.new()
		l.light_color = _col(sl.get("color", []), Color(1.0, 0.9, 0.76))
		l.light_energy = _base_shop
		l.omni_range = float(sl.get("range", 6.0))
		l.light_volumetric_fog_energy = 0.0
		(n as Node3D).add_child(l)
		_shop_lights.append(l)


## 광고판·안내판 화면: 그림이 스스로 빛나고 표면은 유리처럼 매끈하다.
func _screen_material(image: String, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	var tex: Texture2D = MaterialCache.texture(image)
	m.albedo_texture = tex
	m.albedo_color = Color(0.03, 0.03, 0.03)
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission = Color(0, 0, 0)   ## 더하기 방식: 발광 = (색 + 그림) × 세기. 색을 0으로 둬야 그림만 빛난다
	m.emission_energy_multiplier = energy
	m.roughness = 1.0
	m.metallic_specular = 0.0   ## 반사가 그림을 하얗게 덮지 않게 무광으로 둔다
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.resource_name = image
	return m


func _col(a: Array, fallback: Color) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else fallback


func _build_lights(_layout: ArenaLayout) -> void:
	var sc: Dictionary = _cfg.get("sun", {})
	sun = DirectionalLight3D.new()
	var rot: Array = sc.get("rotation_deg", [-56.0, 32.0, 0.0])
	sun.rotation_degrees = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
	_base_sun = float(sc.get("energy", 1.1))
	sun.light_energy = _base_sun
	sun.light_color = _col(sc.get("color", []), Color(1.0, 0.93, 0.82))
	sun.shadow_enabled = bool(sc.get("shadows", true))
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.5
	add_child(sun)
	var ev: Dictionary = _cfg.get("environment", {})
	var we: WorldEnvironment = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _col(_cfg.get("background", []), Color(0.55, 0.6, 0.68))
	var amb: Dictionary = _cfg.get("ambient", {})
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _col(amb.get("color", []), Color(0.86, 0.86, 0.9))
	_base_ambient = float(amb.get("energy", 0.6))
	env.ambient_light_energy = _base_ambient
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if String(ev.get("tonemap", "agx")) == "agx" else Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(ev.get("exposure", 1.0))
	env.tonemap_white = float(ev.get("white", 6.0))
	var ao: Dictionary = ev.get("ssao", {})
	env.ssao_radius = float(ao.get("radius", 1.0))
	env.ssao_intensity = float(ao.get("intensity", 2.0))
	env.ssao_power = float(ao.get("power", 1.5))
	env.ssao_detail = float(ao.get("detail", 0.5))
	var il: Dictionary = ev.get("ssil", {})
	env.ssil_radius = float(il.get("radius", 5.0))
	env.ssil_intensity = float(il.get("intensity", 1.0))
	var gi: Dictionary = ev.get("sdfgi", {})
	env.sdfgi_energy = float(gi.get("energy", 1.0))
	env.sdfgi_bounce_feedback = float(gi.get("bounce_feedback", 0.5))
	env.sdfgi_min_cell_size = float(gi.get("min_cell_size", 0.2))
	env.sdfgi_cascades = int(gi.get("cascades", 4))
	env.sdfgi_use_occlusion = true
	var rr: Dictionary = ev.get("ssr", {})
	env.ssr_max_steps = int(rr.get("max_steps", 56))
	env.ssr_fade_in = float(rr.get("fade_in", 0.15))
	env.ssr_fade_out = float(rr.get("fade_out", 2.0))
	env.ssr_depth_tolerance = float(rr.get("depth_tolerance", 0.2))
	var gl: Dictionary = ev.get("glow", {})
	env.glow_intensity = float(gl.get("intensity", 0.5))
	env.glow_bloom = float(gl.get("bloom", 0.05))
	env.glow_hdr_threshold = float(gl.get("hdr_threshold", 1.0))
	env.glow_strength = float(gl.get("strength", 1.0))
	var fg: Dictionary = ev.get("fog", {})
	env.volumetric_fog_density = float(fg.get("density", 0.006))
	env.volumetric_fog_albedo = _col(fg.get("albedo", []), Color(1, 1, 1))
	env.volumetric_fog_anisotropy = float(fg.get("anisotropy", 0.5))
	env.volumetric_fog_length = float(fg.get("length", 48.0))
	env.volumetric_fog_ambient_inject = 0.0
	sun.light_volumetric_fog_energy = float(fg.get("sun_energy", 2.0))
	var adj: Dictionary = ev.get("adjust", {})
	if not adj.is_empty():
		env.adjustment_enabled = true
		env.adjustment_contrast = float(adj.get("contrast", 1.0))
		env.adjustment_saturation = float(adj.get("saturation", 1.0))
	we.environment = env
	add_child(we)
	var dl: Dictionary = _cfg.get("downlights", {})
	_base_down = float(dl.get("energy", 0.8))
	for p: Array in dl.get("points", []):
		var l: OmniLight3D = OmniLight3D.new()
		l.position = Vector3(float(p[0]), float(dl.get("height", 7.0)), float(p[1]))
		l.light_color = _col(dl.get("color", []), Color(1.0, 0.95, 0.88))
		l.light_energy = _base_down
		l.omni_range = float(dl.get("range", 13.0))
		l.light_volumetric_fog_energy = 0.0
		add_child(l)
		_downlights.append(l)
	var ec: Dictionary = _cfg.get("emergency", {})
	for p2: Array in ec.get("points", []):
		var l2: OmniLight3D = OmniLight3D.new()
		l2.position = Vector3(float(p2[0]), float(ec.get("height", 2.8)), float(p2[1]))
		l2.light_color = _col(ec.get("color", []), Color(1.0, 0.16, 0.1))
		l2.light_energy = 0.0
		l2.omni_range = float(ec.get("range", 9.0))
		l2.light_volumetric_fog_energy = 0.0
		add_child(l2)
		_emergency.append(l2)
	var rp: Dictionary = _cfg.get("reflection_probe", {})
	if not rp.is_empty():
		probe = ReflectionProbe.new()
		var c: Array = rp.get("center", [0.0, 4.5, 0.0])
		var sz: Array = rp.get("size", [44.0, 9.0, 32.0])
		probe.position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		probe.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
		probe.box_projection = true
		probe.interior = true
		probe.intensity = float(rp.get("intensity", 1.0))
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		add_child(probe)


## 그래픽 품질 단계를 적용한다(설정을 바꾸면 판 중에도 다시 부른다).
func apply_quality(q: Dictionary) -> void:
	_quality = q
	env.ssao_enabled = bool(q.get("ssao", true))
	env.ssil_enabled = bool(q.get("ssil", false))
	env.sdfgi_enabled = bool(q.get("sdfgi", false))
	env.ssr_enabled = bool(q.get("ssr", false))
	env.volumetric_fog_enabled = bool(q.get("volumetric_fog", false))
	env.glow_enabled = bool(q.get("glow", true))
	if probe != null:
		probe.visible = bool(q.get("reflection_probe", true))
	var shadows: bool = bool(q.get("downlight_shadows", false))
	for l: OmniLight3D in _downlights:
		l.shadow_enabled = shadows
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi([0, 2, 4, 8].find(int(q.get("msaa", 4))), 0, 3)]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(q.get("fxaa", false)) else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.anisotropic_filtering_level = clampi(int(q.get("anisotropy", 2)), 0, 4) as Viewport.AnisotropicFiltering
		vp.positional_shadow_atlas_size = 4096 if shadows else 1024
	if vp != null:
		vp.scaling_3d_scale = clampf(float(q.get("render_scale", 1.0)), 0.5, 2.0)
	_apply_effects_quality(String(q.get("effects_quality", "high")))
	_set_vignette(float(q.get("vignette", 0.0)))
	RenderingServer.directional_shadow_atlas_set_size(int(q.get("sun_shadow_size", 4096)), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(clampi(int(q.get("soft_shadow_quality", 2)), 0, 5) as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(clampi(int(q.get("soft_shadow_quality", 2)), 0, 5) as RenderingServer.ShadowQuality)
	_apply(_level)


## SSAO·SSIL·SDFGI·화면 공간 반사의 내부 품질(전역 렌더 설정).
func _apply_effects_quality(level: String) -> void:
	var i: int = maxi(["low", "medium", "high", "ultra"].find(level), 0)
	RenderingServer.environment_set_ssao_quality(i as RenderingServer.EnvironmentSSAOQuality, i < 2, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(i as RenderingServer.EnvironmentSSILQuality, i < 3, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_sdfgi_ray_count([RenderingServer.ENV_SDFGI_RAY_COUNT_32, RenderingServer.ENV_SDFGI_RAY_COUNT_64, RenderingServer.ENV_SDFGI_RAY_COUNT_96, RenderingServer.ENV_SDFGI_RAY_COUNT_128][i])
	RenderingServer.environment_set_ssr_roughness_quality([RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_DISABLED, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_LOW, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM, RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH][i])


var _vignette: ColorRect


## 화면 가장자리를 살짝 어둡게(영화 같은 마무리). HUD보다 아래 층에 그린다. 0이면 끈다.
func _set_vignette(strength: float) -> void:
	if _vignette == null:
		var layer: CanvasLayer = CanvasLayer.new()
		layer.layer = 0
		add_child(layer)
		_vignette = ColorRect.new()
		_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
		_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh: Shader = Shader.new()
		sh.code = """shader_type canvas_item;
uniform float strength = 0.2;
void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	float v = smoothstep(0.32, 0.9, length(uv * vec2(1.0, 0.82)) * 1.3);
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
"""
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = sh
		_vignette.material = mat
		layer.add_child(_vignette)
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", strength)
	_vignette.visible = strength > 0.001


## 2단계 전환을 시작한다.
func start_hunt_transition(calm: bool) -> void:
	_hunt = true
	_flicker_total = float(_cfg.get("flicker_s", 0.5))
	_flicker_left = _flicker_total
	_flicker_calm = calm


## 패배 A 연출: 조명이 seconds초 꺼진다. calm이면 완전히 끄지 않고 어둡게만 한다.
func blackout(seconds: float, calm: bool) -> void:
	_blackout_left = seconds
	_blackout_calm = calm


## 즉시 2단계 조명(시각 검사 V-03용).
func set_hunt_lighting(on: bool) -> void:
	_hunt = on
	_flicker_left = 0.0
	_apply(1.0)


func _process(delta: float) -> void:
	_t += delta
	if _water_mat != null:
		_water_mat.uv1_offset = Vector3(_water_flow.x * _t, _water_flow.y * _t, 0.0)
	if _jet_mat != null:
		_jet_mat.uv1_offset = Vector3(0.0, _jet_flow * _t, 0.0)
	var level: float = 1.0
	if _flicker_left > 0.0:
		_flicker_left -= delta
		if _flicker_calm:
			level = 1.0
		else:
			level = 0.25 if int(_t * 14.0) % 2 == 0 else 1.0
	if _blackout_left > 0.0:
		_blackout_left -= delta
		level = 0.35 if _blackout_calm else 0.0
	_apply(level)


func _apply(level: float) -> void:
	_level = level
	var dim: float = float(_cfg.get("hunt_dim", 0.85)) if _hunt else 1.0
	if _hunt and _flicker_left > 0.0 and _flicker_calm:
		## 부드러운 전환: 깜빡이지 않고 0.5초 동안 서서히 어두워진다.
		dim = lerpf(1.0, dim, 1.0 - _flicker_left / maxf(_flicker_total, 0.01))
	var k: float = dim * level
	sun.light_energy = _base_sun * k
	env.ambient_light_energy = _base_ambient * float(_quality.get("ambient_scale", 1.0)) * k
	for l: OmniLight3D in _downlights:
		l.light_energy = _base_down * k
	for l3: OmniLight3D in _shop_lights:
		l3.light_energy = _base_shop * k
	var e_on: float = (1.0 if _hunt and _flicker_left <= 0.0 else 0.0) * (1.0 if level > 0.0 else 0.0)
	var ec: Dictionary = _cfg.get("emergency", {})
	for l2: OmniLight3D in _emergency:
		l2.light_energy = float(ec.get("energy", 1.6)) * e_on * (0.85 + 0.15 * sin(_t * 3.0))
	if _emergency_mat != null:
		_emergency_mat.emission_energy_multiplier = 3.0 * e_on
