class_name ArenaLayout
extends RefCounted
## 아레나 지오메트리와 내비게이션 격자(§9). 시뮬레이션과 3D 표시가 같은 데이터를 쓴다.
## 좌표: 바닥 평면 Vector2(x, z). 북쪽이 -z.

const CELL: float = 0.5
const NAV_CLEARANCE: float = 0.4
const OCCLUDER_MIN_HEIGHT: float = 2.0   ## §9.3: 2.0 m 이상만 차폐물
const CEILING: float = 9.0
const SPAWN_GRID: Vector2i = Vector2i(9, 5)

var min_x: float = -22.0
var min_z: float = -16.0
var max_x: float = 22.0
var max_z: float = 16.0
var obstacles: Array[ArenaObstacle] = []
var occluders: Array[ArenaObstacle] = []
var player_spawn: Vector2 = Vector2.ZERO
var spawn_candidates: Array[Vector2] = []
var hide_points: Array[Vector2] = []
var astar: AStarGrid2D = AStarGrid2D.new()
var cols: int = 0
var rows: int = 0


static func from_map(map: Dictionary, spawn_cfg: Dictionary) -> ArenaLayout:
	var l: ArenaLayout = ArenaLayout.new()
	var lay: Dictionary = map["layout"]
	var b: Array = lay["bounds"]
	l.min_x = float(b[0])
	l.min_z = float(b[1])
	l.max_x = float(b[2])
	l.max_z = float(b[3])
	var ps: Array = lay["player_spawn"]
	l.player_spawn = Vector2(float(ps[0]), float(ps[1]))
	for d: Dictionary in lay["obstacles"]:
		var o: ArenaObstacle = ArenaObstacle.from_dict(d, OCCLUDER_MIN_HEIGHT)
		l.obstacles.append(o)
		if o.occluder:
			l.occluders.append(o)
	l._build_nav()
	l._build_spawns(int(spawn_cfg["candidates"]), float(spawn_cfg["min_separation_m"]), float(spawn_cfg["min_distance_from_player_m"]))
	l._build_hide_points()
	return l


# ---------------------------------------------------------------- 내비게이션

func _build_nav() -> void:
	cols = int(round((max_x - min_x) / CELL))
	rows = int(round((max_z - min_z) / CELL))
	astar.region = Rect2i(0, 0, cols, rows)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(min_x + CELL * 0.5, min_z + CELL * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()
	for i: int in cols:
		for j: int in rows:
			if not _cell_free(cell_to_world(Vector2i(i, j))):
				astar.set_point_solid(Vector2i(i, j), true)


func _cell_free(p: Vector2) -> bool:
	if p.x < min_x + NAV_CLEARANCE or p.x > max_x - NAV_CLEARANCE or p.y < min_z + NAV_CLEARANCE or p.y > max_z - NAV_CLEARANCE:
		return false
	for o: ArenaObstacle in obstacles:
		if o.distance_to(p) < NAV_CLEARANCE:
			return false
	return true


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - min_x) / CELL)), 0, cols - 1), clampi(int(floor((p.y - min_z) / CELL)), 0, rows - 1))


func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(min_x + (c.x + 0.5) * CELL, min_z + (c.y + 0.5) * CELL)


func is_walkable(p: Vector2) -> bool:
	return not astar.is_point_solid(world_to_cell(p))


## 가장 가까운 통행 가능 칸의 중심. 이미 통행 가능하면 칸 중심을 돌려준다.
func nearest_walkable(p: Vector2, max_ring: int = 40) -> Vector2:
	var c: Vector2i = world_to_cell(p)
	if not astar.is_point_solid(c):
		return cell_to_world(c)
	for r: int in range(1, max_ring + 1):
		var best: Vector2 = Vector2.INF
		var best_d: float = INF
		for dx: int in range(-r, r + 1):
			for dz: int in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var cc: Vector2i = c + Vector2i(dx, dz)
				if cc.x < 0 or cc.y < 0 or cc.x >= cols or cc.y >= rows or astar.is_point_solid(cc):
					continue
				var w: Vector2 = cell_to_world(cc)
				var d: float = w.distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = w
		if best_d < INF:
			return best
	return p


## a에서 b까지 경로(시작 칸 제외, 끝은 b의 가장 가까운 통행 칸). 없으면 빈 배열.
func find_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var ca: Vector2i = world_to_cell(nearest_walkable(a))
	var cb: Vector2i = world_to_cell(nearest_walkable(b))
	if ca == cb:
		return PackedVector2Array([cell_to_world(cb)])
	var path: PackedVector2Array = astar.get_point_path(ca, cb)
	if path.size() > 1:
		path.remove_at(0)
	return _smooth(a, path)


## 가시선이 통행 가능 칸으로만 이어지는 중간점을 건너뛴다(격자 지그재그 제거).
func _smooth(start: Vector2, path: PackedVector2Array) -> PackedVector2Array:
	if path.size() <= 2:
		return path
	var out: PackedVector2Array = []
	var anchor: Vector2 = start
	var i: int = 0
	while i < path.size():
		var j: int = path.size() - 1
		while j > i and not _clear_walk(anchor, path[j]):
			j -= 1
		out.append(path[j])
		anchor = path[j]
		i = j + 1
	return out


func _clear_walk(a: Vector2, b: Vector2) -> bool:
	var steps: int = int(ceil(a.distance_to(b) / (CELL * 0.5)))
	for s: int in range(1, steps + 1):
		if astar.is_point_solid(world_to_cell(a.lerp(b, float(s) / steps))):
			return false
	return true


func path_length(a: Vector2, path: PackedVector2Array) -> float:
	if path.is_empty():
		return INF
	var total: float = a.distance_to(path[0])
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


# ---------------------------------------------------------------- 충돌·차폐

## 반지름 r인 원을 구조물과 외벽 밖으로 밀어낸다.
func resolve_circle(p: Vector2, r: float) -> Vector2:
	var q: Vector2 = p
	for _pass: int in 2:
		for o: ArenaObstacle in obstacles:
			q = o.push_out(q, r)
		q.x = clampf(q.x, min_x + r, max_x - r)
		q.y = clampf(q.y, min_z + r, max_z - r)
	return q


## 차폐물(높이 2 m 이상)이 선분을 가리는지(§7.1).
func segment_blocked(a: Vector3, b: Vector3) -> bool:
	for o: ArenaObstacle in occluders:
		if o.segment_fraction(a, b) >= 0.0:
			return true
	return false


## 카메라 팔 충돌용: 모든 구조물·외벽·바닥·천장 중 처음 만나는 위치(0..1). 없으면 1.
func first_hit_fraction(a: Vector3, b: Vector3) -> float:
	var best: float = 1.0
	for o: ArenaObstacle in obstacles:
		var f: float = o.segment_fraction(a, b)
		if f >= 0.0 and f < best:
			best = f
	var lo: Vector3 = Vector3(min_x + 0.15, 0.15, min_z + 0.15)
	var hi: Vector3 = Vector3(max_x - 0.15, CEILING - 0.15, max_z - 0.15)
	for axis: int in 3:
		var d: float = b[axis] - a[axis]
		if absf(d) < 0.000001:
			continue
		if b[axis] < lo[axis]:
			best = minf(best, (lo[axis] - a[axis]) / d)
		elif b[axis] > hi[axis]:
			best = minf(best, (hi[axis] - a[axis]) / d)
	return clampf(best, 0.0, 1.0)


func min_distance_to_occluder(p: Vector2) -> float:
	var best: float = INF
	for o: ArenaObstacle in occluders:
		best = minf(best, maxf(o.distance_to(p), 0.0))
	return best


# ---------------------------------------------------------------- 스폰·숨는 지점

func _build_spawns(count: int, min_sep: float, min_from_player: float) -> void:
	var span: Vector2 = Vector2(max_x - min_x - 5.0, max_z - min_z - 5.0)
	for jz: int in SPAWN_GRID.y:
		for ix: int in SPAWN_GRID.x:
			if spawn_candidates.size() >= count:
				return
			var p: Vector2 = Vector2(min_x + 2.5 + span.x * ix / (SPAWN_GRID.x - 1), min_z + 2.5 + span.y * jz / (SPAWN_GRID.y - 1))
			p = nearest_walkable(p)
			if p.distance_to(player_spawn) < min_from_player:
				continue
			var ok: bool = true
			for q: Vector2 in spawn_candidates:
				if q.distance_to(p) < min_sep:
					ok = false
					break
			if ok:
				spawn_candidates.append(p)


func _build_hide_points() -> void:
	for o: ArenaObstacle in occluders:
		if o.kind != "box":
			continue
		if o.tag == "alcove_wall":
			continue
		var along_z: bool = o.half.x >= o.half.y
		for side: float in [-1.0, 1.0]:
			var off: Vector2 = Vector2(0.0, (o.half.y + 0.9) * side) if along_z else Vector2((o.half.x + 0.9) * side, 0.0)
			var p: Vector2 = o.center + off
			if p.x > min_x and p.x < max_x and p.y > min_z and p.y < max_z:
				hide_points.append(nearest_walkable(p))
	## 알코브 안쪽 중심
	hide_points.append(nearest_walkable(Vector2(min_x + 2.0, 0.0)))
	hide_points.append(nearest_walkable(Vector2(max_x - 2.0, 0.0)))
