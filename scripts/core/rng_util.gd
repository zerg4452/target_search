class_name RngUtil
extends RefCounted
## 판 시드에서 용도별 하위 난수원을 만든다(§13.8). 전역 난수(randi, Array.shuffle)는 쓰지 않는다.


static func make(match_seed: int, label: String) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash("%d:%s" % [match_seed, label])
	return r


## Fisher-Yates. 전달한 배열을 그 자리에서 섞는다.
static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
