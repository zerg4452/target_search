class_name NpcModel
extends Node3D
## glb 외형 타입 하나를 인스턴스로 만들고 외형 사전(슬롯 → 노드·머티리얼)대로 부품을 켜고 칠한다(§6.8).
## 쓰지 않는 부품 노드는 지운다. 애니메이션은 모든 NPC가 같은 라이브러리·같은 규칙으로 재생한다(§5.1).
## 규칙을 판단하지 않는다. 상태는 NpcVisual이 시뮬레이션에서 읽어 넘겨준다.

const LOOPING: Array[String] = ["walk", "idle", "run"]
## 아주 작은 부착물·인쇄물은 그림자를 드리우지 않는다(그리기 호출 절약, §13.12). 타겟과 일반 NPC에 똑같이 적용한다.
const NO_SHADOW_SLOTS: Array[String] = ["face", "top_print_front", "top_print_back", "pants_tab", "watch", "hood_strings", "coat_buttons",
	"vest_patch", "lapel_pin", "pocket_square", "earphones", "ears", "glasses", "socks", "top_pocket", "tie"]
const BLEND_S: float = 0.18

static var _scenes: Dictionary = {}

var skeleton: Skeleton3D
var anim: AnimationPlayer
var slot_nodes: Dictionary = {}   ## slot -> MeshInstance3D
var _current: String = ""
var _oneshot: String = ""
var _oneshot_speed: float = 1.0


static func scene_for(path: String) -> PackedScene:
	if not _scenes.has(path):
		var ps: PackedScene = load(path) as PackedScene
		_scenes[path] = ps
		if ps != null:
			_prepare_loops(ps)
	return _scenes[path]


static var _remnants: Dictionary = {}


## 종료할 때 공용 캐시를 비운다(리소스가 남은 채 끝나지 않게).
static func clear_cache() -> void:
	_scenes.clear()
	_remnants.clear()


## 흔적 잔해용 메시(glb 안의 Remnant_* 노드). 타입 glb마다 한 번만 꺼내 둔다.
static func remnant_mesh(path: String, node_name: String) -> Mesh:
	var key: String = path + "#" + node_name
	if _remnants.has(key):
		return _remnants[key]
	var ps: PackedScene = scene_for(path)
	var mesh: Mesh = null
	if ps != null:
		var inst: Node = ps.instantiate()
		var mi: MeshInstance3D = inst.find_child(node_name, true, false) as MeshInstance3D
		if mi != null:
			mesh = mi.mesh
		inst.free()
	_remnants[key] = mesh
	return mesh


## 반복 애니메이션의 반복 모드를 공용 리소스에 한 번만 정한다.
static func _prepare_loops(ps: PackedScene) -> void:
	var inst: Node = ps.instantiate()
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		for n: StringName in ap.get_animation_list():
			var a: Animation = ap.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(String(n)) else Animation.LOOP_NONE
	inst.free()


## 외형 사전으로 모델을 만든다. 실패하면 false.
func build(app: Dictionary, scene_path: String, mats: MaterialCache) -> bool:
	var ps: PackedScene = scene_for(scene_path)
	if ps == null:
		push_error("외형 glb를 불러올 수 없음: %s" % scene_path)
		return false
	var inst: Node3D = ps.instantiate() as Node3D
	add_child(inst)
	skeleton = inst.find_child("NpcSkeleton", true, false) as Skeleton3D
	if skeleton == null:
		skeleton = inst.find_child("*", true, false) as Skeleton3D
	anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var wanted: Dictionary = {}   ## node -> slot
	for slot: String in app:
		var s: Dictionary = app[slot]
		if bool(s["visible"]) and String(s["node"]) != "NONE":
			wanted[String(s["node"])] = slot
	var found: Dictionary = {}
	for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var node_name: String = String(mi.name)
		if not wanted.has(node_name):
			mi.get_parent().remove_child(mi)
			mi.free()
			continue
		var slot: String = wanted[node_name]
		var m: MeshInstance3D = mi as MeshInstance3D
		var s2: Dictionary = app[slot]
		var mlist: Array = s2["materials"]
		for i: int in m.mesh.get_surface_count():
			var mid: String = String(mlist[mini(i, mlist.size() - 1)])
			m.set_surface_override_material(i, mats.get_mat(mid))
		for bs: String in (s2.get("blend", {}) as Dictionary):
			var idx: int = m.find_blend_shape_by_name(bs)
			if idx >= 0:
				m.set_blend_shape_value(idx, float(s2["blend"][bs]))
		if NO_SHADOW_SLOTS.has(slot):
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		slot_nodes[slot] = m
		found[node_name] = true
	for node_name: String in wanted:
		if not found.has(node_name):
			push_error("glb에 노드가 없음: %s (%s)" % [node_name, scene_path])
	return true


## 반복 동작 전환. phase(0~1)는 처음 시작할 때의 위상이다(§5.1: 위상만 개체마다 다름).
func play_loop(anim_name: String, speed: float = 1.0, phase: float = -1.0, force: bool = false) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	if not force and _oneshot != "" and anim.is_playing() and anim.current_animation == _oneshot:
		anim.speed_scale = _oneshot_speed   ## 일시정지 뒤 이어서 재생
		return
	anim.speed_scale = speed
	_oneshot = ""
	if _current == anim_name:
		return
	_current = anim_name
	anim.play(anim_name, BLEND_S)
	if phase >= 0.0:
		anim.seek(phase * anim.current_animation_length, true)


## 한 번 재생하는 동작(호출 반응·두리번거리기 등). 끝나면 다음 play_loop가 이어받는다.
func play_once(anim_name: String, speed: float = 1.0) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	_oneshot = anim_name
	_oneshot_speed = speed
	_current = anim_name
	anim.speed_scale = speed
	anim.play(anim_name, BLEND_S)


func oneshot_playing() -> bool:
	return _oneshot != "" and anim != null and anim.is_playing() and anim.current_animation == _oneshot


## 같은 포즈 비교용(V-02): 애니메이션을 정해진 시각에 멈춘다.
func freeze_at(anim_name: String, t: float) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	anim.play(anim_name, 0.0)
	anim.seek(t, true)
	anim.pause()
	_current = anim_name
