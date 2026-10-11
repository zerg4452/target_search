extends SceneTree
## 외형 확인용 렌더(창 모드, GPU 필요). 타입 기준 인물이나 변이를 한 줄로 세워 PNG로 저장한다.
## 사용: godot --path . --script res://tools/render_type_sheet.gd -- --out=test_reports/m1/sheet.png --view=front
##       [--specs=a_hoodie,a_hoodie:VA01_BAG_MIRROR,...] [--dist=6] [--fov=40] [--size=1600x900] [--anim=idle] [--t=0]

var _out: String = "test_reports/sheet.png"
var _view: String = "front"
var _specs: PackedStringArray = []
var _dist: float = 6.0
var _fov: float = 40.0
var _size: Vector2i = Vector2i(1600, 900)
var _anim: String = "idle"
var _t: float = 0.0
var _frames: int = 0
var _vp: SubViewport


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		var v: String = kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"out": _out = v
			"view": _view = v
			"specs": _specs = v.split(",")
			"dist": _dist = float(v)
			"fov": _fov = float(v)
			"size":
				var wh: PackedStringArray = v.split("x")
				_size = Vector2i(int(wh[0]), int(wh[1]))
			"anim": _anim = v
			"t": _t = float(v)
	var store: DataStore = DataStore.load_default()
	var outfit_id: String = "mall_guest"
	if _specs.is_empty():
		for t: Dictionary in store.maps["atrium"]["types"]:
			_specs.append(String(t["id"]))
	_vp = SubViewport.new()
	_vp.size = _size
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(_vp)
	var world: Node3D = Node3D.new()
	_vp.add_child(world)
	PreviewStage.add_lighting(world)
	var mats: MaterialCache = MaterialCache.new(store.outfits[outfit_id]["palette"])
	var gap: float = 0.9
	var x0: float = -gap * (_specs.size() - 1) * 0.5
	for i: int in _specs.size():
		var parts: PackedStringArray = _specs[i].split(":")
		var type_id: String = parts[0]
		var app: Dictionary = Appearance.base_from(store.type_data(outfit_id, type_id)["appearance"]["slots"])
		if parts.size() > 1:
			var found: Dictionary = store.find_variant(outfit_id, parts[1])
			app = Appearance.apply_op(app, found["variant"]["op"])
		var m: NpcModel = NpcModel.new()
		world.add_child(m)
		m.build(app, store.type_scene(outfit_id, type_id), mats)
		m.position = Vector3(x0 + gap * i, 0.0, 0.0)
		m.freeze_at(_anim, _t)
	var cam: Camera3D = Camera3D.new()
	cam.fov = _fov
	world.add_child(cam)
	var dir: Vector3 = PreviewStage.view_dir(_view)
	var target: Vector3 = Vector3(0.0, 0.95, 0.0)
	cam.look_at_from_position(target + dir * _dist + Vector3(0.0, 0.25 if _view != "top" else 0.0, 0.0), target, Vector3.UP)
	cam.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 8:
		var img: Image = _vp.get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out.get_base_dir()))
		img.save_png(ProjectSettings.globalize_path("res://").path_join(_out))
		print("saved ", _out)
		return true
	return false
