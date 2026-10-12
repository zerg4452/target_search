extends TestCase
## T-13: Blender가 만든 glb와 노드 목록(manifest)·외형 데이터가 서로 맞는지(§12.5 이름 계약, §12.2 삼각형 예산).
## glb는 헤드리스에서도 읽힌다(tools/run_tests.ps1이 먼저 --import를 돌린다).

const ANIMS: Array[String] = ["walk", "idle", "look_around", "call_react", "wrong_accused", "land", "reveal"]
const TRI_BUDGET: int = 60000   ## §12.2 (D-33에서 8,000 → 12,000, D-35에서 35,000 → 60,000)


func test_glb_matches_manifest() -> bool:
	var store: DataStore = SimFixture.store()
	for type_id: String in store.types["mall_guest"]:
		var path: String = store.type_scene("mall_guest", type_id)
		var ps: PackedScene = load(path) as PackedScene
		check(ps != null, "%s 불러오기" % path)
		if ps == null:
			continue
		var inst: Node = ps.instantiate()
		var man: Dictionary = store.manifests["mall_guest"][type_id]
		var meshes: Dictionary = {}
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			meshes[String(mi.name)] = mi
		for node: String in man["nodes"]:
			check(meshes.has(node), "%s: glb에 노드 %s 없음" % [type_id, node])
			if meshes.has(node):
				var m: MeshInstance3D = meshes[node]
				eq(m.mesh.get_surface_count(), (man["nodes"][node]["surfaces"] as Array).size(), "%s/%s 표면 수" % [type_id, node])
				check(m.skin != null, "%s/%s는 골격에 스키닝돼야 함" % [type_id, node])
		for node2: String in man["remnants"]:
			check(meshes.has(node2), "%s: 잔해 노드 %s 없음" % [type_id, node2])
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		check(ap != null, "%s: AnimationPlayer 없음" % type_id)
		if ap != null:
			for a: String in ANIMS:
				check(ap.has_animation(a), "%s: 애니메이션 %s 없음" % [type_id, a])
		inst.free()
	return true


func test_base_triangle_budget() -> bool:
	var store: DataStore = SimFixture.store()
	for type_id: String in store.types["mall_guest"]:
		var man: Dictionary = store.manifests["mall_guest"][type_id]
		var slots: Dictionary = store.type_data("mall_guest", type_id)["appearance"]["slots"]
		var tris: int = 0
		for slot: String in slots:
			var node: String = String(slots[slot]["node"])
			if node != "NONE":
				tris += int(man["nodes"][node]["tris"])
		note("%s 기준 인물 삼각형 %d" % [type_id, tris])
		check(tris <= TRI_BUDGET, "%s 기준 인물 삼각형 %d > %d (§12.2)" % [type_id, tris, TRI_BUDGET])
		## 변이 하나를 적용해도 예산 안이어야 한다.
		for v: Dictionary in store.type_data("mall_guest", type_id)["variants"]:
			var op: Dictionary = v["op"]
			if String(op["type"]) != "swap_mesh":
				continue
			var before: int = int(man["nodes"].get(String(slots[String(op["slot"])]["node"]), {"tris": 0})["tris"])
			var after: int = tris - before + int(man["nodes"][String(op["node"])]["tris"])
			check(after <= TRI_BUDGET + 800, "%s %s 적용 뒤 삼각형 %d" % [type_id, v["id"], after])
	return true


func test_player_model_exists() -> bool:
	var ps: PackedScene = load("res://assets/player/player.glb") as PackedScene
	check(ps != null, "플레이어 glb")
	if ps != null:
		var inst: Node = ps.instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		check(ap != null and ap.has_animation("run") and ap.has_animation("walk"), "플레이어 run/walk 애니메이션")
		inst.free()
	return true
