class_name ArenaObstacle
extends RefCounted
## 아레나 구조물 하나. 바닥 평면(x, z) 위의 원기둥 또는 축 정렬 상자이고 높이는 y = 0..height.

var id: String = ""
var kind: String = "box"        ## "circle" | "box"
var tag: String = ""
var center: Vector2 = Vector2.ZERO
var radius: float = 0.0         ## circle
var half: Vector2 = Vector2.ZERO  ## box 반폭 (x, z)
var height: float = 1.0
var occluder: bool = false


static func from_dict(d: Dictionary, occluder_min_height: float) -> ArenaObstacle:
	var o: ArenaObstacle = ArenaObstacle.new()
	o.id = String(d["id"])
	o.kind = String(d["kind"])
	o.tag = String(d.get("tag", ""))
	var c: Array = d["center"]
	o.center = Vector2(float(c[0]), float(c[1]))
	if o.kind == "circle":
		o.radius = float(d["radius"])
	else:
		var s: Array = d["size"]
		o.half = Vector2(float(s[0]), float(s[1])) * 0.5
	o.height = float(d["height"])
	o.occluder = o.height >= occluder_min_height
	return o


## 바닥 평면에서 표면까지의 거리. 안쪽이면 음수.
func distance_to(p: Vector2) -> float:
	if kind == "circle":
		return p.distance_to(center) - radius
	var d: Vector2 = (p - center).abs() - half
	var outside: float = Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()
	return outside + minf(maxf(d.x, d.y), 0.0)


## 반지름 r인 원이 겹치지 않도록 밀어낸 위치.
func push_out(p: Vector2, r: float) -> Vector2:
	if kind == "circle":
		var off: Vector2 = p - center
		var dist: float = off.length()
		var need: float = radius + r
		if dist >= need:
			return p
		if dist < 0.0001:
			off = Vector2.RIGHT
			dist = 1.0
		return center + off / dist * need
	var q: Vector2 = Vector2(clampf(p.x, center.x - half.x, center.x + half.x), clampf(p.y, center.y - half.y, center.y + half.y))
	if q != p:
		var off2: Vector2 = p - q
		var dist2: float = off2.length()
		if dist2 >= r:
			return p
		return q + off2 / dist2 * r
	## 상자 안: 가장 가까운 면으로 내보낸다.
	var dx_l: float = p.x - (center.x - half.x)
	var dx_r: float = (center.x + half.x) - p.x
	var dz_t: float = p.y - (center.y - half.y)
	var dz_b: float = (center.y + half.y) - p.y
	var m: float = minf(minf(dx_l, dx_r), minf(dz_t, dz_b))
	if m == dx_l:
		return Vector2(center.x - half.x - r, p.y)
	if m == dx_r:
		return Vector2(center.x + half.x + r, p.y)
	if m == dz_t:
		return Vector2(p.x, center.y - half.y - r)
	return Vector2(p.x, center.y + half.y + r)


## 선분 a→b가 구조물과 처음 만나는 위치(0..1). 만나지 않으면 -1.
func segment_fraction(a: Vector3, b: Vector3) -> float:
	if kind == "box":
		var box: AABB = AABB(Vector3(center.x - half.x, 0.0, center.y - half.y), Vector3(half.x * 2.0, height, half.y * 2.0))
		if box.has_point(a):
			return 0.0
		var hit: Variant = box.intersects_segment(a, b)
		if hit == null:
			return -1.0
		var length: float = a.distance_to(b)
		return 0.0 if length < 0.0001 else a.distance_to(hit as Vector3) / length
	var d: Vector2 = Vector2(b.x - a.x, b.z - a.z)
	var f: Vector2 = Vector2(a.x - center.x, a.z - center.y)
	var qa: float = d.dot(d)
	var lo: float = 0.0
	var hi: float = 1.0
	if qa < 0.000001:
		if f.length() > radius:
			return -1.0
	else:
		var qb: float = 2.0 * f.dot(d)
		var qc: float = f.dot(f) - radius * radius
		var disc: float = qb * qb - 4.0 * qa * qc
		if disc < 0.0:
			return -1.0
		var s: float = sqrt(disc)
		lo = maxf((-qb - s) / (2.0 * qa), 0.0)
		hi = minf((-qb + s) / (2.0 * qa), 1.0)
		if lo > hi:
			return -1.0
	var y_lo: float = lerpf(a.y, b.y, lo)
	var y_hi: float = lerpf(a.y, b.y, hi)
	if minf(y_lo, y_hi) > height or maxf(y_lo, y_hi) < 0.0:
		return -1.0
	if y_lo >= 0.0 and y_lo <= height:
		return lo
	var target_y: float = height if y_lo > height else 0.0
	return clampf((target_y - a.y) / (b.y - a.y), lo, hi)
