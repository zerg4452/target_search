class_name TraceVisual
extends Node3D
## 흔적(§7.5): 번지는 잉크 웅덩이 + 피해자 타입의 잔해(기준 부품) + 젖은 발자국. 수명·연출만 다루고 규칙은 판단하지 않는다.

var _puddle: MeshInstance3D
var _footprints: Array[MeshInstance3D] = []
var _age: float = 0.0
var _tune: Dictionary = {}
var _foot_mat: StandardMaterial3D
var _puddle_mat: StandardMaterial3D
var _calm: bool = false


## type_app: 피해자 타입의 appearance.json. scene_path: 그 타입의 glb(잔해 노드가 들어 있다).
func build(trace: Dictionary, type_app: Dictionary, scene_path: String, mats: MaterialCache, tune: Dictionary, rng: RandomNumberGenerator, calm_fx: bool) -> void:
	_tune = tune
	_calm = calm_fx
	var p: Vector2 = trace["pos"]
	position = Vector3(p.x, 0.0, p.y)
	_puddle_mat = StandardMaterial3D.new()
	_puddle_mat.albedo_color = Color(0.025, 0.025, 0.04)
	_puddle_mat.roughness = 0.04
	_puddle_mat.metallic_specular = 1.0
	_puddle_mat.clearcoat_enabled = true
	_puddle_mat.clearcoat = 1.0
	var disc: CylinderMesh = CylinderMesh.new()
	var r: float = float(tune["puddle_diameter_m"]) * 0.5
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.008
	disc.radial_segments = 28
	_puddle = MeshInstance3D.new()
	_puddle.mesh = disc
	_puddle.material_override = _puddle_mat
	_puddle.position.y = 0.005
	_puddle.scale = Vector3(0.05, 1.0, 0.05)
	add_child(_puddle)
	# 잔해: 피해자 타입의 기준 부품(잔해 목록)을 웅덩이 안팎에 놓는다. 타겟의 변이와는 관계없다.
	var tr_def: Dictionary = type_app.get("trace", {})
	var remnants: Array = tr_def.get("remnants", []).duplicate()
	var count_range: Array = tr_def.get("remnant_count", [2, 2])
	var count: int = mini(rng.randi_range(int(count_range[0]), int(count_range[1])), remnants.size())
	RngUtil.shuffle(remnants, rng)
	for i: int in count:
		var rd: Dictionary = remnants[i]
		var mesh: Mesh = NpcModel.remnant_mesh(scene_path, String(rd["node"]))
		if mesh == null:
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		var ml: Array = rd["materials"]
		for s: int in mesh.get_surface_count():
			mi.set_surface_override_material(s, mats.get_mat(String(ml[mini(s, ml.size() - 1)])))
		var ang: float = TAU * float(i) / float(count) + rng.randf_range(-0.6, 0.6)
		var dist: float = rng.randf_range(0.12, 0.5)
		mi.position = Vector3(cos(ang) * dist, 0.004, sin(ang) * dist)
		mi.rotation.y = rng.randf() * TAU
		add_child(mi)
	# 젖은 발자국
	_foot_mat = StandardMaterial3D.new()
	_foot_mat.albedo_color = Color(0.03, 0.03, 0.05)
	_foot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_foot_mat.roughness = 0.08
	var prev: Vector2 = p
	var foot_mesh: CylinderMesh = CylinderMesh.new()
	foot_mesh.top_radius = 0.06
	foot_mesh.bottom_radius = 0.06
	foot_mesh.height = 0.004
	foot_mesh.radial_segments = 10
	var k: int = 0
	for fp: Vector2 in trace["footprints"]:
		var mi2: MeshInstance3D = MeshInstance3D.new()
		mi2.mesh = foot_mesh
		mi2.material_override = _foot_mat
		var dir: Vector2 = (fp - prev).normalized()
		var side: Vector2 = Vector2(-dir.y, dir.x) * (0.09 if k % 2 == 0 else -0.09)
		mi2.position = Vector3(fp.x - p.x + side.x, 0.003, fp.y - p.y + side.y)
		mi2.rotation.y = atan2(-dir.x, -dir.y)
		mi2.scale = Vector3(0.9, 1.0, 2.1)
		add_child(mi2)
		_footprints.append(mi2)
		prev = fp
		k += 1


func _process(delta: float) -> void:
	_age += delta
	var spread: float = clampf(_age / float(_tune["puddle_spread_s"]), 0.05, 1.0)
	var ripple: float = 0.0
	if _age < float(_tune["fresh_fx_s"]) and not _calm:
		ripple = 0.035 * sin(_age * 6.0) * (1.0 - _age / float(_tune["fresh_fx_s"]))
	_puddle.scale = Vector3(spread + ripple, 1.0, spread + ripple)
	var life: float = float(_tune["footprint_life_s"])
	var fade: float = float(_tune["footprint_fade_s"])
	if _age > life:
		var a: float = clampf(1.0 - (_age - life) / fade, 0.0, 1.0)
		_foot_mat.albedo_color.a = a
		if a <= 0.0:
			for f: MeshInstance3D in _footprints:
				f.visible = false
