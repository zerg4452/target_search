class_name Turntable
extends VBoxContainer
## 별도 3D 세계(SubViewport)에서 인물 여러 명을 나란히 세워 천천히 돌린다.
## 브리핑(§3.1), 기준 외형 보기(§4.4), 결과 비교(§8.4), 변이 도감 미리보기에 쓴다.
## 모든 인물은 같은 포즈(대기 동작 0초)로 멈춰 있어 비교할 때 가짜 차이가 없다.

const GAP: float = 0.95

var viewport: SubViewport
var container: SubViewportContainer
var labels: HBoxContainer
var world: Node3D
var camera: Camera3D
var spin_speed: float = 0.6
var spin: bool = true
var _models: Array[NpcModel] = []
var _pivots: Array[Node3D] = []
var _overlay: StandardMaterial3D
var _time: float = 0.0
var _angle: float = 0.0


func setup(size: Vector2i, background: Color = Color(0.2, 0.21, 0.24)) -> void:
	add_theme_constant_override("separation", 4)
	container = SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(size)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	PreviewStage.add_lighting(world, background)
	camera = Camera3D.new()
	camera.fov = 30.0
	world.add_child(camera)
	labels = HBoxContainer.new()
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.add_theme_constant_override("separation", 12)
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(labels)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(1.0, 0.85, 0.1, 0.6)
	_overlay.grow = true
	_overlay.grow_amount = 0.004
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## entries: [{"app": 외형, "scene": glb 경로, "label": 문자열}]
func show_models(entries: Array, mats: MaterialCache, view_height: float = 0.95) -> void:
	for p: Node3D in _pivots:
		p.queue_free()
	_pivots.clear()
	_models.clear()
	for c: Node in labels.get_children():
		c.queue_free()
	var n: int = entries.size()
	for i: int in n:
		var e: Dictionary = entries[i]
		var pivot: Node3D = Node3D.new()
		## 카메라가 -Z에서 +Z를 보므로 화면 왼쪽이 +X다. 첫 인물이 화면 왼쪽(아래 이름표와 같은 순서)에 오게 한다.
		pivot.position = Vector3(GAP * (n - 1) * 0.5 - GAP * i, 0.0, 0.0)
		world.add_child(pivot)
		var m: NpcModel = NpcModel.new()
		pivot.add_child(m)
		m.build(e["app"], String(e["scene"]), mats)
		m.freeze_at("idle", 0.0)
		_pivots.append(pivot)
		_models.append(m)
		var l: Label = Label.new()
		l.text = String(e.get("label", ""))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(float(viewport.size.x) / maxf(n, 1) - 12.0, 0.0)
		l.add_theme_font_size_override("font_size", 16)
		labels.add_child(l)
	labels.visible = n > 0 and String(entries[0].get("label", "")) != ""
	var width: float = GAP * maxf(n - 1, 0) + 0.9
	var aspect: float = float(viewport.size.x) / maxf(float(viewport.size.y), 1.0)
	var vfov: float = deg_to_rad(camera.fov)
	var hfov: float = 2.0 * atan(tan(vfov * 0.5) * aspect)
	var dist: float = maxf((width * 0.5) / tan(hfov * 0.5), 1.0 / tan(vfov * 0.5)) + 0.6
	var target: Vector3 = Vector3(0.0, view_height, 0.0)
	camera.look_at_from_position(target + Vector3(0.0, 0.18, -dist), target, Vector3.UP)
	_angle = 0.0


## i번째 인물의 슬롯 노드를 깜빡이는 외곽 강조로 표시한다(결과 화면 전용).
func highlight(index: int, slot: String) -> void:
	if index < 0 or index >= _models.size():
		return
	var mi: MeshInstance3D = _models[index].slot_nodes.get(slot) as MeshInstance3D
	if mi != null:
		mi.material_overlay = _overlay


func clear_highlight() -> void:
	for m: NpcModel in _models:
		for mi: Variant in m.slot_nodes.values():
			(mi as MeshInstance3D).material_overlay = null


func set_angle(deg: float) -> void:
	spin = false
	_angle = deg_to_rad(deg)
	for p: Node3D in _pivots:
		p.rotation.y = _angle


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	if spin:
		_angle += delta * spin_speed
		for p: Node3D in _pivots:
			p.rotation.y = _angle
	_overlay.albedo_color.a = 0.25 + 0.45 * (0.5 + 0.5 * sin(_time * 5.0))
