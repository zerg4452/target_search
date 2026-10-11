class_name NpcState
extends RefCounted
## NPC 한 명의 런타임 상태. 타겟도 같은 클래스·같은 배회 코드를 쓴다(§5.3).

enum Mode { IDLE, MOVING, CALLED }

var id: int = 0
var type_id: String = ""
var is_target: bool = false
var alive: bool = true
var pos: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2(0.0, -1.0)
var speed: float = 0.0
var rng: RandomNumberGenerator

var mode: int = Mode.IDLE
var path: PackedVector2Array = []
var path_index: int = 0
var idle_left: float = 0.0
var look_around: bool = false

var call_elapsed: float = 0.0
var call_from: Vector2 = Vector2.ZERO
var call_to: Vector2 = Vector2.ZERO

var stuck_time: float = 0.0

## 관찰 기록: 마지막으로 관찰된 시각(match_time). 처음에는 아주 오래전.
var last_observed_time: float = -1000.0
var observed_now: bool = false

## 통계(행동 동일성 검사 T-05용)
var stat_moving_time: float = 0.0
var stat_idle_time: float = 0.0
var stat_distance: float = 0.0
var stat_legs: int = 0
var stat_leg_distance: float = 0.0


func destination() -> Vector2:
	return path[path.size() - 1] if not path.is_empty() else pos
