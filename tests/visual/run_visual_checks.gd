extends SceneTree
## 시각 검사(§14.3, GPU 필요, 창 모드). 결과는 test_reports/visual/에 남긴다. 실패가 있으면 종료 코드 1.
##   V-01 변이 가시성: 같은 포즈·같은 조명에서 기준 인물과 변이 인물을 선언한 거리·방향마다 렌더해 비교.
##        등급 1~2는 기본 카메라(FOV 65°), 3~5는 관찰 카메라(FOV 30°). 휘도 차 0.08 이상 픽셀이
##        등급 1~2는 300 px, 3~5는 100 px 이상이고 가장 큰 연결 영역이 40 px 이상이어야 한다.
##   V-02 동일성: 같은 타입 일반 NPC 두 명을 같은 포즈·같은 카메라로 렌더하면 차이 픽셀 0.
##   V-03 조명 하한: 아레나 표본 12곳에서 기준 인물 정면 얼굴의 평균 밝기(sRGB) 1단계 ≥ 0.35, 2단계 ≥ 0.30.
##   --calibrate: V-01 대신, 변이마다 방향(앞·뒤·왼쪽·오른쪽, 선언했으면 위)과 카메라(기본 65°/관찰 30°)별로
##                기준을 통과하는 가장 먼 거리를 재서 test_reports/visual/calibration.json에 남긴다(tools/apply_calibration.py가 등급을 다시 매긴다).
## 사용: godot --path . --script res://tests/visual/run_visual_checks.gd [-- --only=V-01 --filter=VA0 --calibrate]

const W: int = 1920
const H: int = 1080
const LUMA_DIFF: float = 0.08
const OUT_DIR: String = "res://test_reports/visual"

var store: DataStore
var mats: MaterialCache
var vp: SubViewport
var stage: Node3D
var cam: Camera3D
var model: NpcModel
var report: Array[Dictionary] = []
var failures: int = 0
var only: String = ""
var filter: String = ""
var calibrate: bool = false
var _rect: Rect2i = Rect2i(0, 0, W, H)
var _base_cache: Dictionary = {}
const CAL_DISTANCES: Array[float] = [16.0, 14.0, 12.0, 10.0, 8.5, 7.0, 6.0, 5.0, 4.5, 4.0, 3.5, 3.0, 2.5, 2.0]


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
		elif a == "--calibrate":
			calibrate = true
	_run.call_deferred()


func _run() -> void:
	store = DataStore.load_default()
	mats = MaterialCache.new(store.outfits["mall_guest"]["palette"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	stage = Node3D.new()
	vp.add_child(stage)
	cam = Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	if calibrate:
		await _calibrate()
		quit(0)
		return
	if only == "" or only == "V-01":
		await _v01()
	if only == "" or only == "V-02":
		await _v02()
	if only == "" or only == "V-03":
		await _v03()
	_write_report()
	quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------- 공용

func _clear_stage() -> void:
	for c: Node in stage.get_children():
		if c != cam:
			c.queue_free()
	await process_frame


func _set_model(app: Dictionary, scene: String, pos: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> void:
	if model != null:
		model.queue_free()
		await process_frame
	model = NpcModel.new()
	stage.add_child(model)
	model.position = pos
	model.rotation.y = yaw
	model.build(app, scene, mats)
	model.freeze_at("idle", 0.0)


## 변이가 바꾸는 슬롯의 높이(모델 공간 AABB 가운데). 변이 쪽에 노드가 없으면(숨김) 기준 쪽을 쓴다.
func _slot_height(base: Dictionary, var_app: Dictionary, scene: String, slot: String) -> float:
	for app: Dictionary in [var_app, base]:
		await _set_model(app, scene)
		var mi: MeshInstance3D = model.slot_nodes.get(slot) as MeshInstance3D
		if mi != null:
			var bb: AABB = mi.get_aabb()
			## 1 cm 단위로 맞춘다. 기준 그림 캐시의 키와 카메라가 정확히 같은 값을 쓰게 한다.
			return snappedf(clampf(bb.get_center().y, 0.1, 1.75), 0.01)
	return 1.0


## 모델을 바꾼 직후에는 자세·그림자가 한두 프레임 늦게 자리 잡을 수 있다.
## 연속한 두 프레임이 똑같아질 때까지 기다린 뒤 찍는다(최대 8프레임).
func _render() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var prev: Image = vp.get_texture().get_image()
	for _i: int in 8:
		await RenderingServer.frame_post_draw
		var cur: Image = vp.get_texture().get_image()
		if cur.get_data() == prev.get_data():
			return cur
		prev = cur
	push_warning("렌더가 8프레임 안에 안정되지 않음")
	return prev


static func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## 휘도 차 픽셀 수와 가장 큰 4-연결 영역 크기. 바이트 배열로 직접 비교한다(sRGB 0~255).
## _rect(인물과 그림자가 들어가는 화면 영역) 안만 본다. 그 밖은 두 그림이 같다.
func _diff(a: Image, b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var da: PackedByteArray = a.get_data()
	var db: PackedByteArray = b.get_data()
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(W * H)
	var count: int = 0
	var exact: int = 0
	var thr: float = LUMA_DIFF * 255.0
	var hits: PackedInt32Array = []
	for y0: int in range(_rect.position.y, _rect.end.y):
		for x0: int in range(_rect.position.x, _rect.end.x):
			var i: int = y0 * W + x0
			var k: int = i * 3
			var ra: int = da[k]
			var ga: int = da[k + 1]
			var ba: int = da[k + 2]
			var rb: int = db[k]
			var gb: int = db[k + 1]
			var bb: int = db[k + 2]
			if ra != rb or ga != gb or ba != bb:
				exact += 1
				if absf(0.2126 * (ra - rb) + 0.7152 * (ga - gb) + 0.0722 * (ba - bb)) >= thr:
					mask[i] = 1
					hits.append(i)
					count += 1
	var largest: int = 0
	if count > 0:
		var seen: PackedByteArray = PackedByteArray()
		seen.resize(W * H)
		for i2: int in hits:
			if seen[i2] == 0:
				var size: int = 0
				var stack: PackedInt32Array = [i2]
				seen[i2] = 1
				while not stack.is_empty():
					var j: int = stack[stack.size() - 1]
					stack.remove_at(stack.size() - 1)
					size += 1
					var jx: int = j % W
					if jx > 0 and mask[j - 1] == 1 and seen[j - 1] == 0:
						seen[j - 1] = 1
						stack.append(j - 1)
					if jx < W - 1 and mask[j + 1] == 1 and seen[j + 1] == 0:
						seen[j + 1] = 1
						stack.append(j + 1)
					if j >= W and mask[j - W] == 1 and seen[j - W] == 0:
						seen[j - W] = 1
						stack.append(j - W)
					if j + W < W * H and mask[j + W] == 1 and seen[j + W] == 0:
						seen[j + W] = 1
						stack.append(j + W)
				largest = maxi(largest, size)
	return {"count": count, "largest": largest, "exact": exact, "mask": mask}


## 인물(원점, 키 1.72 m)과 바닥 그림자가 들어갈 화면 사각형.
func _update_rect() -> void:
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for x: float in [-1.8, 1.8]:
		for y: float in [0.0, 2.0]:
			for z: float in [-1.8, 1.8]:
				var p: Vector3 = Vector3(x, y, z)
				if cam.is_position_behind(p):
					_rect = Rect2i(0, 0, W, H)
					return
				var sp: Vector2 = cam.unproject_position(p)
				lo = lo.min(sp)
				hi = hi.max(sp)
	var r: Rect2i = Rect2i(Vector2i(int(lo.x) - 4, int(lo.y) - 4), Vector2i(int(hi.x - lo.x) + 9, int(hi.y - lo.y) + 9))
	_rect = r.intersection(Rect2i(0, 0, W, H))


func _save_diff(name: String, a: Image, b: Image, mask: PackedByteArray) -> void:
	var img: Image = Image.create(W * 2, H, false, Image.FORMAT_RGB8)
	img.blit_rect(a, Rect2i(0, 0, W, H), Vector2i(0, 0))
	img.blit_rect(b, Rect2i(0, 0, W, H), Vector2i(W, 0))
	for y: int in H:
		for x: int in W:
			if mask[y * W + x] == 1:
				img.set_pixel(W + x, y, Color(1.0, 0.0, 1.0))
	img.resize(W, H / 2)
	img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(name + ".png")))


## 바뀐 부위(슬롯)의 높이를 겨눈다. 눈높이는 3인칭 카메라 중심 높이(약 1.6 m), dist는 카메라와 그 부위 사이 거리다.
func _cam_for(view: String, dist: float, fov: float, aim_y: float = 1.0) -> void:
	cam.fov = fov
	var target: Vector3 = Vector3(0.0, aim_y, 0.0)
	var dir: Vector3 = PreviewStage.view_dir(view)
	var eye: Vector3
	if view == "top":
		eye = target + dir * dist
	else:
		var dy: float = 1.6 - aim_y
		var horiz: float = sqrt(maxf(dist * dist - dy * dy, 0.25))
		eye = target + Vector3(dir.x, 0.0, dir.z).normalized() * horiz
		eye.y = 1.6
	cam.look_at_from_position(eye, target, Vector3.UP)
	_update_rect()


# ---------------------------------------------------------------- V-01

func _v01() -> void:
	await _clear_stage()
	PreviewStage.add_lighting(stage)
	for t: Dictionary in store.maps["atrium"]["types"]:
		var tid: String = String(t["id"])
		var scene: String = store.type_scene("mall_guest", tid)
		var base: Dictionary = Appearance.base_from(store.type_data("mall_guest", tid)["appearance"]["slots"])
		for v: Dictionary in store.type_data("mall_guest", tid)["variants"]:
			var vid: String = String(v["id"])
			if filter != "" and not vid.contains(filter):
				continue
			if not store.milestone_ok(String(v.get("milestone", "M0"))):
				continue
			var grade: int = int(v["difficulty"])
			var fov: float = 65.0 if grade <= 2 else 30.0
			var need: int = 300 if grade <= 2 else 100
			var dirs: Array = v["visible_from"]
			if dirs.has("any"):
				dirs = ["front", "back", "left", "right"]
			var variant_app: Dictionary = Appearance.apply_op(base, v["op"])
			var aim_y: float = await _slot_height(base, variant_app, scene, String(v["op"]["slot"]))
			for view: String in dirs:
				_cam_for(view, float(v["identify_distance_m"]), fov, aim_y)
				await _set_model(base, scene)
				var a: Image = await _render()
				await _set_model(variant_app, scene)
				var b: Image = await _render()
				var d: Dictionary = _diff(a, b)
				var ok: bool = int(d["count"]) >= need and int(d["largest"]) >= 40
				report.append({"check": "V-01", "id": vid, "view": view, "grade": grade, "distance_m": float(v["identify_distance_m"]), "fov": fov,
					"diff_px": d["count"], "largest": d["largest"], "need_px": need, "pass": ok})
				print("V-01 %s %-6s %s  diff %6d  largest %6d  (need %d/40)" % ["PASS" if ok else "FAIL", view, vid, d["count"], d["largest"], need])
				if not ok:
					failures += 1
					_save_diff("V01_%s_%s" % [vid, view], a, b, d["mask"])


# ---------------------------------------------------------------- V-02

func _v02() -> void:
	await _clear_stage()
	_rect = Rect2i(0, 0, W, H)
	PreviewStage.add_lighting(stage)
	var layout: ArenaLayout = ArenaLayout.from_map(store.maps["atrium"], store.npc["spawn"])
	var s: MatchSetup = MatchSetup.build(store, layout, "hard", "atrium", 9)
	for tid: String in s.types_used:
		var idx: Array[int] = []
		for i: int in s.npc_types.size():
			if s.npc_types[i] == tid and i != s.target_index:
				idx.append(i)
		if idx.size() < 2:
			continue
		for view: String in ["front", "back"]:
			_cam_for(view, 3.0, 30.0)
			await _set_model(s.appearances[idx[0]], store.type_scene("mall_guest", tid))
			var a: Image = await _render()
			await _set_model(s.appearances[idx[1]], store.type_scene("mall_guest", tid))
			var b: Image = await _render()
			var d: Dictionary = _diff(a, b)
			var ok: bool = int(d["exact"]) == 0
			report.append({"check": "V-02", "id": tid, "view": view, "npcs": [idx[0], idx[1]], "diff_px": d["exact"], "pass": ok})
			print("V-02 %s %s %s  NPC %d vs %d  다른 픽셀 %d" % ["PASS" if ok else "FAIL", tid, view, idx[0], idx[1], d["exact"]])
			if not ok:
				failures += 1
				_save_diff("V02_%s_%s" % [tid, view], a, b, d["mask"])


# ---------------------------------------------------------------- V-03

func _v03() -> void:
	await _clear_stage()
	model = null
	var layout: ArenaLayout = ArenaLayout.from_map(store.maps["atrium"], store.npc["spawn"])
	var arena: ArenaVisual = ArenaVisual.new()
	stage.add_child(arena)
	arena.build(layout, store.maps["atrium"])
	var cands: Array = layout.spawn_candidates
	var points: Array[Vector2] = []
	var step: int = maxi(1, cands.size() / 12)
	for i: int in range(0, cands.size(), step):
		if points.size() < 12:
			points.append(cands[i])
	var base: Dictionary = Appearance.base_from(store.type_data("mall_guest", "a_hoodie")["appearance"]["slots"])
	var scene: String = store.type_scene("mall_guest", "a_hoodie")
	for phase: String in ["SEARCH", "HUNT"]:
		arena.set_hunt_lighting(phase == "HUNT")
		var floor_v: float = 0.35 if phase == "SEARCH" else 0.30
		var values: Array[float] = []
		for p: Vector2 in points:
			## 카메라는 인물 앞 2.5 m. 구조물 안이나 뒤가 되지 않는 방향을 고른다(아레나 가운데 쪽부터).
			var to_center: Vector2 = (-p).normalized() if p.length() > 0.1 else Vector2(0, 1)
			for k: int in 16:
				var cand: Vector2 = to_center.rotated(TAU * float((k + 1) / 2) / 16.0 * (1.0 if k % 2 == 0 else -1.0))
				var e2: Vector2 = p + cand * 2.5
				if layout.is_walkable(e2) and not layout.segment_blocked(Vector3(e2.x, 1.6, e2.y), Vector3(p.x, 1.585, p.y)):
					to_center = cand
					break
			var eye2: Vector2 = p + to_center * 2.5
			var yaw: float = atan2(-to_center.x, -to_center.y)
			await _set_model(base, scene, Vector3(p.x, 0.0, p.y), yaw)
			cam.fov = 30.0
			var face_c: Vector3 = Vector3(p.x, 1.585, p.y) + Vector3(to_center.x, 0.0, to_center.y) * 0.105
			cam.look_at_from_position(Vector3(eye2.x, 1.6, eye2.y), face_c, Vector3.UP)
			var img: Image = await _render()
			var sp: Vector2 = cam.unproject_position(face_c)
			var sum: float = 0.0
			var n: int = 0
			for dy: int in range(-6, 7):
				for dx: int in range(-10, 11):
					var px: Vector2i = Vector2i(int(sp.x) + dx, int(sp.y) + dy)
					if px.x >= 0 and px.y >= 0 and px.x < W and px.y < H:
						sum += _luma(img.get_pixelv(px))
						n += 1
			var mean: float = sum / maxf(n, 1)
			values.append(mean)
			var ok: bool = mean >= floor_v
			report.append({"check": "V-03", "id": "%s@(%.1f,%.1f)" % [phase, p.x, p.y], "phase": phase, "mean": mean, "floor": floor_v, "pass": ok})
			print("V-03 %s %s (%.1f, %.1f) 얼굴 평균 밝기 %.3f (하한 %.2f)" % ["PASS" if ok else "FAIL", phase, p.x, p.y, mean, floor_v])
			if not ok:
				failures += 1
				img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join("V03_%s_%d.png" % [phase, values.size()])))
	model = null


# ---------------------------------------------------------------- 보고서

func _write_report() -> void:
	var f: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT_DIR.path_join("visual_report.json")), FileAccess.WRITE)
	f.store_string(JSON.stringify({"generated": Time.get_datetime_string_from_system(), "failures": failures, "results": report}, "  "))
	f.close()
	var lines: PackedStringArray = ["# 시각 검사 결과 (§14.3)", "", "생성: %s · 실패 %d건 · 항목 %d개" % [Time.get_datetime_string_from_system(), failures, report.size()], ""]
	lines.append("| 검사 | 대상 | 방향/단계 | 값 | 기준 | 결과 |")
	lines.append("|---|---|---|---:|---|---|")
	for r: Dictionary in report:
		match String(r["check"]):
			"V-01":
				lines.append("| V-01 | %s (등급 %d, %.0f m, FOV %d°) | %s | %d px / 최대 영역 %d | %d px / 40 | %s |" % [r["id"], r["grade"], r["distance_m"], int(r["fov"]), r["view"], int(r["diff_px"]), int(r["largest"]), int(r["need_px"]), "통과" if r["pass"] else "**실패**"])
			"V-02":
				lines.append("| V-02 | %s NPC %s | %s | %d px | 0 | %s |" % [r["id"], str(r["npcs"]), r["view"], int(r["diff_px"]), "통과" if r["pass"] else "**실패**"])
			"V-03":
				lines.append("| V-03 | %s | %s | %.3f | ≥ %.2f | %s |" % [r["id"], r["phase"], float(r["mean"]), float(r["floor"]), "통과" if r["pass"] else "**실패**"])
	var f2: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT_DIR.path_join("visual_report.md")), FileAccess.WRITE)
	f2.store_string("\n".join(lines) + "\n")
	f2.close()
	print("visual report: %s (failures %d)" % [OUT_DIR, failures])


# ---------------------------------------------------------------- 보정(--calibrate)

## 같은 카메라·거리의 기준 인물 그림은 한 번만 찍는다.
func _base_image(tid: String, base: Dictionary, scene: String, view: String, dist: float, fov: float, aim_y: float) -> Image:
	var key: String = "%s|%s|%.2f|%.0f|%.2f" % [tid, view, dist, fov, aim_y]
	if not _base_cache.has(key):
		await _set_model(base, scene)
		_base_cache[key] = await _render()
	return _base_cache[key]


func _passes(tid: String, base: Dictionary, var_app: Dictionary, scene: String, view: String, dist: float, fov: float, need: int, aim_y: float) -> bool:
	_cam_for(view, dist, fov, aim_y)
	var a: Image = await _base_image(tid, base, scene, view, dist, fov, aim_y)
	await _set_model(var_app, scene)
	var b: Image = await _render()
	var d: Dictionary = _diff(a.duplicate() as Image, b)
	return int(d["count"]) >= need and int(d["largest"]) >= 40


## 기준을 통과하는 가장 먼 거리(통과 못 하면 0). 가까울수록 잘 보인다고 보고 이분 탐색한다.
func _max_pass(tid: String, base: Dictionary, var_app: Dictionary, scene: String, view: String, fov: float, need: int, aim_y: float) -> float:
	var n: int = CAL_DISTANCES.size()
	if not await _passes(tid, base, var_app, scene, view, CAL_DISTANCES[n - 1], fov, need, aim_y):
		return 0.0
	if await _passes(tid, base, var_app, scene, view, CAL_DISTANCES[0], fov, need, aim_y):
		return CAL_DISTANCES[0]
	var lo: int = 0       ## 실패
	var hi: int = n - 1   ## 통과
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		if await _passes(tid, base, var_app, scene, view, CAL_DISTANCES[mid], fov, need, aim_y):
			hi = mid
		else:
			lo = mid
	return CAL_DISTANCES[hi]


func _calibrate() -> void:
	await _clear_stage()
	PreviewStage.add_lighting(stage)
	var out: Dictionary = {}
	for t: Dictionary in store.maps["atrium"]["types"]:
		var tid: String = String(t["id"])
		var scene: String = store.type_scene("mall_guest", tid)
		var base: Dictionary = Appearance.base_from(store.type_data("mall_guest", tid)["appearance"]["slots"])
		for v: Dictionary in store.type_data("mall_guest", tid)["variants"]:
			var vid: String = String(v["id"])
			if filter != "" and not vid.contains(filter):
				continue
			var var_app: Dictionary = Appearance.apply_op(base, v["op"])
			var views: Array[String] = ["front", "back", "left", "right"]
			if (v["visible_from"] as Array).has("top"):
				views.append("top")
			var res: Dictionary = {}
			var aim_y: float = await _slot_height(base, var_app, scene, String(v["op"]["slot"]))
			for view: String in views:
				var d_def: float = await _max_pass(tid, base, var_app, scene, view, 65.0, 300, aim_y)
				var d_obs: float = await _max_pass(tid, base, var_app, scene, view, 30.0, 100, aim_y)
				res[view] = {"default": d_def, "observe": d_obs}
				print("CAL %s %-6s 기본 %.1f m · 관찰 %.1f m" % [vid, view, d_def, d_obs])
			out[vid] = res
	var f: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT_DIR.path_join("calibration.json")), FileAccess.WRITE)
	f.store_string(JSON.stringify({"generated": Time.get_datetime_string_from_system(), "distances": CAL_DISTANCES, "results": out}, "  "))
	f.close()
	print("calibration written")
