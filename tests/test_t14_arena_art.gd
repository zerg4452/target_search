extends TestCase
## T-14 (I-03 보강): 아레나 아트의 차폐물이 시뮬레이션의 차폐 부피를 빈틈없이 덮는지.
## 판정에서 '가려졌다'고 보는 곳은 화면에서도 반드시 가려져야 한다. 그래서 그림의 차폐물(OCC_<id>)이
## 판정 부피보다 크거나 같고, 불투명해야 한다. 반대(그림이 더 큼)는 보수적이라 허용한다.

const ARENA: String = "res://assets/arena/arena_atrium.glb"


func _xform_to_root(n: Node3D) -> Transform3D:
	var t: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p is Node3D and p.get_parent() != null:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _points(mi: MeshInstance3D) -> PackedVector3Array:
	var xf: Transform3D = _xform_to_root(mi)
	var out: PackedVector3Array = []
	for s: int in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		for v: Vector3 in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			out.append(xf * v)
	return out


func test_occluders_cover_sim_volumes() -> bool:
	var ps: PackedScene = load(ARENA) as PackedScene
	check(ps != null, "아레나 glb 불러오기")
	if ps == null:
		return true
	var inst: Node = ps.instantiate()
	var layout: ArenaLayout = SimFixture.layout()
	var checked: int = 0
	for o: ArenaObstacle in layout.obstacles:
		if not o.occluder:
			continue
		var mi: MeshInstance3D = inst.find_child("OCC_" + o.id, true, false) as MeshInstance3D
		check(mi != null, "차폐물 %s의 그림(OCC_%s)이 없음" % [o.id, o.id])
		if mi == null:
			continue
		checked += 1
		for s: int in mi.mesh.get_surface_count():
			var mat: BaseMaterial3D = mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null:
				check(mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "%s: 차폐물 그림은 불투명해야 함" % o.id)
		var pts: PackedVector3Array = _points(mi)
		var lo: Vector3 = Vector3(INF, INF, INF)
		var hi: Vector3 = Vector3(-INF, -INF, -INF)
		for p: Vector3 in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		check(lo.y <= 0.001 and hi.y >= o.height - 0.001, "%s: 높이 %.2f~%.2f가 판정 0~%.2f를 덮지 못함" % [o.id, lo.y, hi.y, o.height])
		if o.kind == "box":
			check(lo.x <= o.center.x - o.half.x + 0.001 and hi.x >= o.center.x + o.half.x - 0.001, "%s: x 범위 부족" % o.id)
			check(lo.z <= o.center.y - o.half.y + 0.001 and hi.z >= o.center.y + o.half.y - 0.001, "%s: z 범위 부족" % o.id)
		else:
			## 볼록 다각형 기둥: 바깥 꼭짓점을 각도순으로 이어 만든 모든 변이 중심에서 반지름 이상 떨어져야 한다.
			var rim: Array[Vector2] = []
			for p2: Vector3 in pts:
				var q: Vector2 = Vector2(p2.x, p2.z) - o.center
				if q.length() > o.radius * 0.9:
					rim.append(q)
			rim.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.angle() < b.angle())
			var uniq: Array[Vector2] = []
			for q2: Vector2 in rim:
				if uniq.is_empty() or uniq[-1].distance_to(q2) > 0.001:
					uniq.append(q2)
			var min_edge: float = INF
			for i: int in uniq.size():
				var a2: Vector2 = uniq[i]
				var b2: Vector2 = uniq[(i + 1) % uniq.size()]
				var edge: Vector2 = b2 - a2
				if edge.length() < 0.0001:
					continue
				var dist: float = absf(a2.cross(edge)) / edge.length()
				min_edge = minf(min_edge, dist)
			check(min_edge >= o.radius - 0.0005, "%s: 다각형 기둥의 내접 반지름 %.3f < 판정 반지름 %.3f" % [o.id, min_edge, o.radius])
	note("검사한 차폐물 %d개" % checked)
	check(checked >= 18, "차폐물 수가 너무 적음 (%d)" % checked)
	inst.free()
	return true


func test_arena_has_lighting_data() -> bool:
	var m: Dictionary = SimFixture.store().maps["atrium"]
	var l: Dictionary = m.get("lighting", {})
	for key: String in ["sun", "ambient", "downlights", "emergency", "hunt_dim"]:
		check(l.has(key), "lighting.%s 없음" % key)
	check(absf(float(l.get("hunt_dim", 0.0)) - 0.85) < 0.001, "2단계 밝기 −15%%(§3.1)")
	return true
