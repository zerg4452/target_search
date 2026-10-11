class_name PlayerInput
extends RefCounted
## 한 틱의 플레이어 입력. 게임은 InputMap에서, 테스트는 직접 채운다.

var move: Vector2 = Vector2.ZERO      ## x: 오른쪽, y: 앞
var run: bool = false
var observe: bool = false
var look_delta: Vector2 = Vector2.ZERO  ## 라디안. x: yaw, y: pitch
var interact_pressed: bool = false
var accuse_held: bool = false
var pause_pressed: bool = false
var skip_pressed: bool = false
## 테스트 전용: 0 이상이면 조준 계산 대신 이 NPC를 조준한 것으로 본다.
var aim_override: int = -1
