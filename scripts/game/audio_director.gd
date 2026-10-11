class_name AudioDirector
extends Node
## 소리(§11.3). 시뮬레이션 이벤트를 받아 재생만 한다. 규칙 판정에 쓰지 않는다.
## 모든 NPC는 같은 발소리·호출 반응음을 쓴다. 발소리는 이동 속도와 상관없이 같은 박자로 난다
## (타겟이 안 보일 때 빨리 움직여도 소리로는 구분되지 않게, §11.2 4번).

const DIR: String = "res://assets/audio/"
const FOOTSTEP_RANGE_M: float = 12.0
const ELIM_RANGE_M: float = 22.0
const POOL: int = 10

var _streams: Dictionary = {}
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_next: int = 0
var _world: Node3D
var _lowpass: AudioEffectLowPassFilter
var _music_bus: int = -1
var _sfx_bus: int = -1


func setup() -> void:
	_music_bus = _ensure_bus("Music")
	_sfx_bus = _ensure_bus("SFX")
	if AudioServer.get_bus_effect_count(_music_bus) == 0:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 900.0
		AudioServer.add_bus_effect(_music_bus, _lowpass)
	else:
		_lowpass = AudioServer.get_bus_effect(_music_bus, 0) as AudioEffectLowPassFilter
	AudioServer.set_bus_effect_enabled(_music_bus, 0, false)
	for n: String in ["hvac_loop", "mall_music_loop", "chime_announce", "chime_hint", "elimination", "puddle", "counter_tick", "buzzer", "correct", "call_murmur", "footstep_1", "footstep_2", "footstep_3", "lights_flicker", "ui_click"]:
		var s: AudioStream = load(DIR + n + ".wav") as AudioStream
		if s is AudioStreamWAV and n.ends_with("_loop"):
			var w: AudioStreamWAV = s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		_streams[n] = s
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -8.0
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "SFX"
	_ambience.volume_db = -14.0
	add_child(_ambience)


func _exit_tree() -> void:
	## 재생 중인 소리를 멈추고 스트림 참조를 놓는다(종료 때 리소스가 남지 않게).
	for c: Node in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
			(c as AudioStreamPlayer).stream = null
	for p: AudioStreamPlayer3D in _pool:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_streams.clear()


func _ensure_bus(bus_name: String) -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func apply_volumes(settings: AppSettings) -> void:
	_set_linear(0, settings.get_f("volume_master"))
	_set_linear(_music_bus, settings.get_f("volume_music"))
	_set_linear(_sfx_bus, settings.get_f("volume_sfx"))


func _set_linear(bus: int, v: float) -> void:
	AudioServer.set_bus_mute(bus, v <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.001)))


## 판이 시작될 때 3D 소리를 붙일 세계를 정한다.
func attach_world(world: Node3D) -> void:
	_world = world
	_pool.clear()
	for i: int in POOL:
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = FOOTSTEP_RANGE_M
		p.unit_size = 3.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		world.add_child(p)
		_pool.append(p)


func start_match() -> void:
	set_hunt(false)
	_music.pitch_scale = 1.0
	_music.stream = _streams["mall_music_loop"]
	_music.play()
	_ambience.stream = _streams["hvac_loop"]
	_ambience.play()


func stop_match() -> void:
	_music.stop()
	_ambience.stop()
	set_hunt(false)


## 2단계: 음악이 느려지고 필터가 걸린다(§11.3).
func set_hunt(on: bool) -> void:
	AudioServer.set_bus_effect_enabled(_music_bus, 0, on)
	_music.pitch_scale = 0.82 if on else 1.0


func ui(sound: String, volume_db: float = 0.0) -> void:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = _streams.get(sound)
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func at(sound: String, pos: Vector3, max_dist: float, volume_db: float = 0.0) -> void:
	if _world == null:
		return
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.stream = _streams.get(sound)
	p.max_distance = max_dist
	p.unit_size = 4.0
	p.volume_db = volume_db
	p.position = pos
	_world.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func footstep(pos: Vector3, variant: int) -> void:
	if _pool.is_empty():
		return
	var p: AudioStreamPlayer3D = _pool[_pool_next]
	_pool_next = (_pool_next + 1) % _pool.size()
	p.stream = _streams["footstep_%d" % (variant % 3 + 1)]
	p.position = pos
	p.volume_db = -10.0
	p.play()
