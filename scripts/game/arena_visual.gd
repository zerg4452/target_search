class_name ArenaVisual
extends Node3D
## 에코 몰 아트리움(§9) 표시. Blender가 같은 배치 JSON으로 만든 glb를 세우고, 조명은 맵 데이터(lighting)로 만든다.
## 2단계 전환(§3.1): 0.5초 깜빡임 → 밝기 −15% + 붉은 비상등. '깜빡임 줄이기'면 부드럽게 바꾼다.
## 차폐 판정은 ArenaLayout(시뮬레이션)이 한다. 여기서는 보여 주기만 한다.

var sun: DirectionalLight3D
var env: Environment
var _cfg: Dictionary = {}
var _downlights: Array[OmniLight3D] = []
var _emergency: Array[OmniLight3D] = []
var _emergency_mat: StandardMaterial3D
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


func build(layout: ArenaLayout, map: Dictionary) -> void:
	var ps: PackedScene = load(String(map.get("scene", ""))) as PackedScene
	if ps != null:
		var inst: Node3D = ps.instantiate() as Node3D
		inst.name = "ArenaArt"
		add_child(inst)
		var em: MeshInstance3D = inst.find_child("EmergencyStrips", true, false) as MeshInstance3D
		if em != null:
			_emergency_mat = StandardMaterial3D.new()
			_emergency_mat.albedo_color = Color(0.45, 0.08, 0.06)
			_emergency_mat.emission_enabled = true
			_emergency_mat.emission = Color(1.0, 0.12, 0.08)
			_emergency_mat.emission_energy_multiplier = 0.0
			em.material_override = _emergency_mat
	else:
		push_error("아레나 glb를 불러올 수 없음: %s" % map.get("scene", ""))
	_cfg = map.get("lighting", {})
	_build_lights(layout)


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
	add_child(sun)
	var we: WorldEnvironment = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _col(_cfg.get("background", []), Color(0.55, 0.6, 0.68))
	var amb: Dictionary = _cfg.get("ambient", {})
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _col(amb.get("color", []), Color(0.86, 0.86, 0.9))
	_base_ambient = float(amb.get("energy", 0.6))
	env.ambient_light_energy = _base_ambient
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
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
		l.shadow_enabled = false
		add_child(l)
		_downlights.append(l)
	var ec: Dictionary = _cfg.get("emergency", {})
	for p2: Array in ec.get("points", []):
		var l2: OmniLight3D = OmniLight3D.new()
		l2.position = Vector3(float(p2[0]), float(ec.get("height", 2.8)), float(p2[1]))
		l2.light_color = _col(ec.get("color", []), Color(1.0, 0.16, 0.1))
		l2.light_energy = 0.0
		l2.omni_range = float(ec.get("range", 9.0))
		add_child(l2)
		_emergency.append(l2)


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
	var dim: float = float(_cfg.get("hunt_dim", 0.85)) if _hunt else 1.0
	if _hunt and _flicker_left > 0.0 and _flicker_calm:
		## 부드러운 전환: 깜빡이지 않고 0.5초 동안 서서히 어두워진다.
		dim = lerpf(1.0, dim, 1.0 - _flicker_left / maxf(_flicker_total, 0.01))
	var k: float = dim * level
	sun.light_energy = _base_sun * k
	env.ambient_light_energy = _base_ambient * k
	for l: OmniLight3D in _downlights:
		l.light_energy = _base_down * k
	var e_on: float = (1.0 if _hunt and _flicker_left <= 0.0 else 0.0) * (1.0 if level > 0.0 else 0.0)
	var ec: Dictionary = _cfg.get("emergency", {})
	for l2: OmniLight3D in _emergency:
		l2.light_energy = float(ec.get("energy", 1.6)) * e_on * (0.85 + 0.15 * sin(_t * 3.0))
	if _emergency_mat != null:
		_emergency_mat.emission_energy_multiplier = 3.0 * e_on
