class_name NpcVisual
extends Node3D
## NPC 한 명의 표시. 외형은 NpcModel(glb), 위치·동작은 MatchSim의 NpcState를 그대로 따른다.
## 동작 선택 규칙은 모든 NPC(타겟 포함)에 같다(§5.1). 규칙을 판단하지 않는다.

var npc_id: int = -1
var model: NpcModel
var debug_marker: MeshInstance3D
var reveal_ring: MeshInstance3D
var _marker_on: Material
var _marker_off: Material
var _marker_target: Material
var _phase: float = 0.0
var _last_mode: int = -1


func build(app: Dictionary, scene_path: String, mats: MaterialCache, phase: float) -> void:
	model = NpcModel.new()
	model.name = "Model"
	add_child(model)
	model.build(app, scene_path, mats)
	_phase = phase
	_build_debug()
	model.play_loop("idle", 1.0, _phase)


## 매 프레임: 위치·방향과 동작. walk_speed는 걷기 애니메이션이 만들어진 기준 속도(1.25 m/s).
func sync_state(n: NpcState, walk_speed: float, frozen: bool) -> void:
	position = Vector3(n.pos.x, 0.0, n.pos.y)
	rotation.y = atan2(-n.facing.x, -n.facing.y)
	if frozen:
		if model.anim != null:
			model.anim.speed_scale = 0.0
		return
	match n.mode:
		NpcState.Mode.MOVING:
			model.play_loop("walk", maxf(n.speed, 0.1) / walk_speed, _phase, true)
		NpcState.Mode.CALLED:
			if _last_mode != NpcState.Mode.CALLED:
				model.play_once("call_react")
		_:
			if _last_mode != NpcState.Mode.IDLE and n.look_around:
				model.play_once("look_around", 2.5 / maxf(n.idle_left, 0.5))
			else:
				model.play_loop("idle", 1.0, _phase)
	_last_mode = n.mode


func play_once(anim_name: String) -> void:
	model.play_once(anim_name)


func _build_debug() -> void:
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	debug_marker = _mesh(sm, null, Vector3(0.0, 2.05, 0.0))
	debug_marker.visible = false
	add_child(debug_marker)
	_marker_on = _unshaded(Color(0.2, 0.9, 0.3))
	_marker_off = _unshaded(Color(0.95, 0.2, 0.2))
	_marker_target = _unshaded(Color(1.0, 0.2, 1.0))
	var tm: TorusMesh = TorusMesh.new()
	tm.inner_radius = 0.35
	tm.outer_radius = 0.45
	reveal_ring = _mesh(tm, _unshaded(Color(1.0, 0.85, 0.1)), Vector3(0.0, 2.1, 0.0))
	reveal_ring.visible = false
	add_child(reveal_ring)


static func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func set_debug(show: bool, observed: bool, is_target: bool) -> void:
	debug_marker.visible = show
	if show:
		debug_marker.material_override = _marker_target if is_target else (_marker_on if observed else _marker_off)
		debug_marker.scale = Vector3.ONE * (1.6 if is_target else 1.0)
