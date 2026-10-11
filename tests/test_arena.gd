extends TestCase
## 아레나 기준(§5.6, §9.3): 스폰 후보 40개(2.5 m 간격, 착지점에서 5 m), 차폐물 12 m 기준, 가시성 기본 동작.


func test_spawn_candidates() -> bool:
	var l: ArenaLayout = SimFixture.layout()
	eq(l.spawn_candidates.size(), 40, "스폰 후보 수")
	for i: int in l.spawn_candidates.size():
		var p: Vector2 = l.spawn_candidates[i]
		check(l.is_walkable(p), "후보 %d 통행 불가" % i)
		check(p.distance_to(l.player_spawn) >= 5.0, "후보 %d가 착지점에 너무 가까움" % i)
		for j: int in range(i + 1, l.spawn_candidates.size()):
			check(p.distance_to(l.spawn_candidates[j]) >= 2.5 - 0.0001, "후보 %d·%d 간격 부족" % [i, j])
	return true


func test_occluder_within_12m_everywhere() -> bool:
	var l: ArenaLayout = SimFixture.layout()
	var worst: float = 0.0
	for i: int in l.cols:
		for j: int in l.rows:
			var c: Vector2i = Vector2i(i, j)
			if l.astar.is_point_solid(c):
				continue
			worst = maxf(worst, l.min_distance_to_occluder(l.cell_to_world(c)))
	note("통행 가능 지점에서 가장 먼 차폐물 거리 %.2f m" % worst)
	check(worst <= 12.0, "차폐물이 12 m 밖인 지점이 있음 (%.2f m)" % worst)
	return true


func test_visibility_basics() -> bool:
	var l: ArenaLayout = SimFixture.layout()
	var vis: Dictionary = SimFixture.store().visibility
	var cam: SimCamera = SimCamera.new()
	cam.eye = Vector3(0.0, 1.6, 10.0)
	cam.basis = Basis.IDENTITY   ## 북쪽(-z)을 본다
	cam.body_pos = Vector3(0.0, 0.0, 30.0)   ## 안전지대 영향 제거
	check(Visibility.observed_now(Vector2(0.0, 5.0), cam, l, vis), "정면 5 m는 관찰됨")
	check(not Visibility.observed_now(Vector2(0.0, 14.0), cam, l, vis), "카메라 뒤는 비관찰")
	## 기둥 P5(-11, 5) 바로 뒤(북쪽)는 기둥에 가린다.
	cam.eye = Vector3(-11.0, 1.6, 9.0)
	check(not Visibility.observed_now(Vector2(-11.0, 3.5), cam, l, vis), "기둥 뒤는 비관찰")
	## 분수(높이 1 m)는 차폐물이 아니다.
	cam.eye = Vector3(0.0, 1.6, 6.0)
	check(Visibility.observed_now(Vector2(0.0, -4.0), cam, l, vis), "분수 너머는 머리가 보여 관찰됨")
	## 안전지대: 등 뒤 3 m도 관찰됨
	cam.body_pos = Vector3(0.0, 0.0, 6.0)
	check(Visibility.observed_now(Vector2(0.0, 9.0), cam, l, vis), "안전지대 4 m 안은 관찰됨")
	return true
