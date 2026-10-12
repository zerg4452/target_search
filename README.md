# 틀린 사람 찾기 (가칭) — M2

똑같이 생긴 NPC 30명 중 한 군데가 다른 1명을 찾는 3D 3인칭 관찰·추리 게임. 설계는 [GAME_DESIGN.md](GAME_DESIGN.md), 구현 상태는 그 문서의 §15.

## 실행

- 게임: `run_game.cmd` → 메인 메뉴(연습·표준·어려움·오늘의 도전·변이 도감·기록·설정)
  - 바로 판 시작(디버그): `run_game.cmd --seed=7 --skip-intro --debug-overlay` (이런 판은 기록에 남지 않는다)
- 헤드리스 검사: `pwsh tools/run_tests.ps1` (T-01~T-15 + 아레나)
- 시각 검사(GPU, 창 모드): `pwsh tools/run_visual_checks.ps1` (V-01 변이 가시성, V-02 동일성, V-03 조명 하한)
- 봇 플레이테스트(한 판 길이 계측): `godot_console --headless --path . --script res://tools/bot_playtest.gd -- --seeds=8`
- 한 판 길이(구석 시나리오): `godot_console --headless --path . --script res://tools/measure_match_length.gd`

Godot 4.7.2 Standard가 필요하다. 기본 경로는 WinGet 설치 위치이며 `GODOT_EXE`(게임) / `GODOT`(검사)로 바꿀 수 있다.

## 에셋 다시 만들기

모든 아트·소리는 스크립트로 만든다. 원본 `.blend`는 `art_source/`에 있다.

| 대상 | 명령 |
|---|---|
| NPC 4타입 + 플레이어 | `blender --background --factory-startup --python tools/blender/build_npc_type.py -- --all` |
| 아레나 | `blender --background --factory-startup --python tools/blender/build_arena_atrium.py` |
| 소리 | `py -3 tools/generate_audio.py` |
| 재질 세부 텍스처·광고판 그림 | `py -3 tools/generate_textures.py` → `godot --headless --path . --import` |
| 노드 재질 면을 덧붙인 뒤 외형 데이터 맞추기 | `py -3 tools/sync_node_materials.py` |
| 변이 등급 다시 매기기 | `godot --path . --script res://tests/visual/run_visual_checks.gd -- --calibrate` → `py -3 tools/apply_calibration.py` |
| 설계서 자동 구역(§6.5 카탈로그, 부록 B) | `py -3 tools/sync_design_doc.py` |

Blender 5.2 기준(`%LOCALAPPDATA%\Programs\Blender Foundation\Blender 5.2\blender.exe`). 모델을 다시 만든 뒤에는 Godot 가져오기(`--import`)를 한 번 돌린다(검사 스크립트가 한다).

## 조작

| 입력 | 기능 |
|---|---|
| WASD / Shift | 이동 / 달리기 |
| 마우스 / 우클릭(누르고 있기, 옵션으로 토글) | 카메라 / 관찰 모드 |
| E | 호출(3 m) / 흔적 조사 |
| F 0.8초 누르고 있기 | 지목(4 m) |
| Tab 누르고 있기 (+ 마우스 휠) | 기준 외형 보기 (어려움은 브리핑 때만) |
| Esc | 일시정지(계속·설정·메뉴) |
| Space | 브리핑 건너뛰기 |
| R / T / M | 결과 화면: 다시 하기 / 같은 시드로(기록 안 함) / 메뉴 |
| F1 / F2 / F3 | 디버그 오버레이 / 즉시 사냥 / 즉시 힌트 (디버그 빌드) |

키는 설정에서 다시 지정할 수 있다.

## 디버그 인자 (`--` 뒤)

`--seed=<int>` `--difficulty=<practice|standard|hard>` `--variant=<ID|NONE>` `--skip-intro` `--search-time=<초>` `--hunt` `--debug-overlay` `--yaw=<도>` `--pitch=<도>` `--screenshot=<경로> --screenshot-at=<초>` `--face-trace` `--end=<win|lose_all|lose_chances>` `--show-reference` `--pause-at=<초>` `--panel=<codex|records|settings>` `--playtest-log`

## 저장 위치

`user://settings.cfg`(설정), `user://records.json`(기록·도감·오늘의 도전), 디버그 빌드에서 `user://playtest_log.jsonl`(판 요약). Windows에서 `user://`는 `%APPDATA%\Godot\app_userdata\<프로젝트 이름>`이다.
