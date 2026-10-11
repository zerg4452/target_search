class_name Appearance
extends RefCounted
## NPC 외형(슬롯 → 노드·머티리얼·블렌드셰이프·표시 여부)과 외형 서명(§6.8).
## 외형 사전 형식: { slot: {"node": String, "materials": Array, "blend": Dictionary, "visible": bool} }


## appearance.json의 slots에서 기준 외형을 만든다. 원본 데이터는 바꾸지 않는다.
static func base_from(slots: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot: String in slots:
		var s: Dictionary = slots[slot]
		out[slot] = {
			"node": String(s["node"]),
			"materials": (s["materials"] as Array).duplicate(),
			"blend": {},
			"visible": true,
		}
	return out


## 변이 연산 하나를 적용한 새 외형을 돌려준다. 정확히 한 슬롯만 바뀐다.
static func apply_op(app: Dictionary, op: Dictionary) -> Dictionary:
	var out: Dictionary = app.duplicate(true)
	var slot: String = String(op["slot"])
	var s: Dictionary = out[slot]
	match String(op["type"]):
		"swap_mesh":
			s["node"] = String(op["node"])
			s["materials"] = (op.get("materials", s["materials"]) as Array).duplicate()
		"swap_material":
			var mats: Array = s["materials"]
			mats[int(op.get("surface", 0))] = String(op["material"])
		"set_blend_shape":
			(s["blend"] as Dictionary)[String(op["name"])] = float(op["weight"])
		"hide":
			s["visible"] = false
	return out


static func slot_key(s: Dictionary) -> String:
	var blend: Dictionary = s["blend"]
	var blend_keys: Array = blend.keys()
	blend_keys.sort()
	var blend_parts: PackedStringArray = []
	for k: Variant in blend_keys:
		blend_parts.append("%s:%.3f" % [k, blend[k]])
	var mats: PackedStringArray = []
	for m: Variant in s["materials"]:
		mats.append(String(m))
	return "%s|%s|%s|%s" % [s["node"], ",".join(mats), ",".join(blend_parts), "1" if s["visible"] else "0"]


## 타입 ID + 슬롯 이름순 연결. 같은 타입의 일반 NPC는 모두 같아야 한다(I-01).
static func signature(type_id: String, app: Dictionary) -> String:
	var slots: Array = app.keys()
	slots.sort()
	var parts: PackedStringArray = [type_id]
	for slot: Variant in slots:
		parts.append("%s=%s" % [slot, slot_key(app[slot])])
	return ";".join(parts)


## 두 외형에서 서로 다른 슬롯 목록.
static func diff_slots(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for slot: String in a:
		if not b.has(slot) or slot_key(a[slot]) != slot_key(b[slot]):
			out.append(slot)
	for slot: String in b:
		if not a.has(slot):
			out.append(slot)
	return out
