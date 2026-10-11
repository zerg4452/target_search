class_name Records
extends RefCounted
## 기록·변이 도감·직전 변이·일일 시드(§10.2, §10.3, §13.9). 판 결과를 받아 갱신만 한다. 규칙 판정에는 쓰지 않는다.
## 파일: user://records.json = {"version", "records", "codex", "recent_variants", "daily", "unlocked_hard", "games"}.
## 저장은 임시 파일에 먼저 쓴 뒤 바꿔치기한다. 버전이 다르면 이전 파일을 보존하고 변환한다.

const VERSION: int = 1
const DEFAULT_PATH: String = "user://records.json"

var data: Dictionary = {}
var path: String = DEFAULT_PATH
var load_note: String = ""


static func empty_data() -> Dictionary:
	return {
		"version": VERSION,
		"records": {},
		"codex": {},
		"recent_variants": [],
		"daily": {},
		"unlocked_hard": false,
		"games": 0,
	}


static func load_from(p_path: String = DEFAULT_PATH) -> Records:
	var r: Records = Records.new()
	r.path = p_path
	r.data = empty_data()
	if not FileAccess.file_exists(p_path):
		return r
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		## 망가진 파일은 지우지 않고 옆에 보존한 뒤 새로 시작한다.
		DirAccess.copy_absolute(p_path, p_path + ".broken")
		r.load_note = "기록 파일을 읽을 수 없어 %s.broken으로 보존하고 새로 시작했다" % p_path
		return r
	var d: Dictionary = parsed
	var ver: int = int(d.get("version", 0))
	if ver != VERSION:
		DirAccess.copy_absolute(p_path, "%s.v%d.bak" % [p_path, ver])
		r.load_note = "기록 파일 버전 %d → %d 변환(원본 보존)" % [ver, VERSION]
	for key: String in r.data:
		if d.has(key) and key != "version":
			r.data[key] = d[key]
	return r


func save() -> Error:
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


## 직전 판들의 변이(§6.7 2번). 새 판의 변이 고르기에서 뺀다.
func recent_variants() -> Array:
	return (data["recent_variants"] as Array).duplicate()


func hard_unlocked() -> bool:
	return bool(data.get("unlocked_hard", false))


func games() -> int:
	return int(data.get("games", 0))


## 판 결과를 반영한다. meta: {"preset", "date", "daily": bool, "recorded": bool, "fov_deg", "exclusion": int}
## recorded가 거짓이면(같은 시드로 다시, 디버그 시드·변이) 기록·도감을 바꾸지 않는다.
func apply_result(result: Dictionary, meta: Dictionary) -> Dictionary:
	var out: Dictionary = {"new_best": false, "codex_new": "", "hard_unlocked_now": false, "daily_counted": false}
	if not bool(meta.get("recorded", true)):
		return out
	var preset: String = String(meta.get("preset", result.get("preset", "standard")))
	var date: String = String(meta.get("date", ""))
	var win: bool = bool(result.get("win", false))
	data["games"] = games() + 1
	var recs: Dictionary = data["records"]
	if not recs.has(preset):
		recs[preset] = {"wins": 0, "losses": 0, "search_finds": 0, "best_score": 0, "best_score_fov": 0.0, "best_find_s": -1.0}
	var rec: Dictionary = recs[preset]
	if win:
		rec["wins"] = int(rec["wins"]) + 1
		if String(result.get("found_in", "")) == "SEARCH":
			rec["search_finds"] = int(rec["search_finds"]) + 1
		var score: int = int(result.get("score", 0))
		if score > int(rec["best_score"]):
			rec["best_score"] = score
			rec["best_score_fov"] = float(meta.get("fov_deg", result.get("fov_deg", 65.0)))
			out["new_best"] = true
		var t: float = float(result.get("match_time", 0.0))
		if float(rec["best_find_s"]) < 0.0 or t < float(rec["best_find_s"]):
			rec["best_find_s"] = t
		if preset == "standard" and not hard_unlocked():
			data["unlocked_hard"] = true
			out["hard_unlocked_now"] = true
	else:
		rec["losses"] = int(rec["losses"]) + 1
	# 도감: 찾음(승리) / 봄(패배 후 공개). 처음 기록한 날짜를 남긴다.
	var vid: String = String(result.get("variant_id", ""))
	if vid != "":
		var codex: Dictionary = data["codex"]
		if not codex.has(vid):
			codex[vid] = {"found": "", "seen": ""}
			out["codex_new"] = vid
		var entry: Dictionary = codex[vid]
		var key: String = "found" if win else "seen"
		if String(entry[key]) == "":
			entry[key] = date
		var recent: Array = data["recent_variants"]
		recent.erase(vid)
		recent.append(vid)
		var keep: int = int(meta.get("exclusion", 3))
		while recent.size() > keep:
			recent.remove_at(0)
	if bool(meta.get("daily", false)) and date != "":
		var daily: Dictionary = data["daily"]
		if not daily.has(date):
			daily[date] = {"win": win, "score": int(result.get("score", 0)), "remaining": int(result.get("remaining", 0)), "match_time": float(result.get("match_time", 0.0)), "variant_id": vid}
			out["daily_counted"] = true
	return out


func codex_state(variant_id: String) -> String:
	var e: Dictionary = (data["codex"] as Dictionary).get(variant_id, {})
	if String(e.get("found", "")) != "":
		return "found"
	if String(e.get("seen", "")) != "":
		return "seen"
	return ""


## 일일 시드(§10.2): 날짜 문자열로 만든 시드. 같은 날이면 누구나 같은 판이다.
static func daily_seed(date: String) -> int:
	return absi(hash("daily:%s" % date)) % 2147483647


static func today() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]
