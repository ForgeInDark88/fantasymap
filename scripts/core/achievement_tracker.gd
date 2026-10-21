class_name AchievementTracker
extends RefCounted
## Учёт достижений (data/achievements): глобальный профиль игрока вне
## сохранений мира (user://achievements.json). Условия проверяются по
## событиям: записи летописи и счётчики мира (через World.observer → EventBus),
## смена года (годовые условия — мир без войн, доли земель, уровни героев) и
## события интерфейса. Без опроса данных каждый тик. Логика без нод — её
## использует автолоад Achievements и тесты.

const PATH := "user://achievements.json"
const YEARLY := [&"peace_years", &"nation_share", &"race_share", &"hero_level", &"religion_races", &"nations_total", &"year"]

var defs: Array[AchievementDef] = []
## id → {"year": год мира, "date": дата получения}.
var unlocked: Dictionary = {}
## id → прогресс 0..1 (лучший за все миры).
var progress: Dictionary = {}
var path := PATH
## С какого года в текущем мире нет войн (-1 — сейчас война).
var _peace_since := -1
var _last_year := -1


func _init(file: String = PATH) -> void:
	path = file
	var reg := Registry.new("res://data/achievements/", AchievementDef)
	for d in reg.items:
		if (d as AchievementDef).hero_play and not Features.HERO_PLAY:
			continue
		defs.append(d as AchievementDef)
	load_profile()


func load_profile() -> void:
	unlocked = {}
	progress = {}
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		unlocked = (data as Dictionary).get("unlocked", {})
		progress = (data as Dictionary).get("progress", {})


func save_profile() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"unlocked": unlocked, "progress": progress}, "\t"))
		f.close()


func is_unlocked(id: StringName) -> bool:
	return unlocked.has(String(id))


func get_progress(d: AchievementDef) -> float:
	return 1.0 if is_unlocked(d.id) else float(progress.get(String(d.id), 0.0))


## Новый мир: сбросить серии (мир без войн).
func reset_world(world: World) -> void:
	_peace_since = world.year if world.diplomacy.wars.is_empty() else -1
	_last_year = world.year


## Событие мира: what — &"log" ({kind, text}) или &"count" ({key, value}); или &"ui" ({key}).
## Возвращает только что полученные достижения.
func handle(world: World, what: StringName, data: Dictionary) -> Array[AchievementDef]:
	var got: Array[AchievementDef] = []
	for d in defs:
		if is_unlocked(d.id):
			continue
		match what:
			&"log":
				if d.cond == &"event" and data.kind == d.kind and String(data.text).contains(d.contains):
					_unlock(world, d, got)
			&"count":
				if d.cond == &"count" and data.key == d.key:
					_record(world, d, float(data.value) / d.target, got)
			&"ui":
				if d.cond == &"ui" and StringName(data.key) == d.key:
					_unlock(world, d, got)
	if not got.is_empty():
		save_profile()
	return got


## Смена года: годовые условия (вызывается по EventBus.year_passed, раз в год мира).
func new_year(world: World) -> Array[AchievementDef]:
	var got: Array[AchievementDef] = []
	if world.year == _last_year:
		return got
	_last_year = world.year
	if world.diplomacy.wars.is_empty():
		if _peace_since < 0:
			_peace_since = world.year
	else:
		_peace_since = -1
	var land := 0.0
	var best_nation := 0.0
	var by_race := {}
	for n in world.nations:
		if n.alive:
			land += n.cell_count
			best_nation = maxf(best_nation, n.cell_count)
			by_race[n.race_id] = by_race.get(n.race_id, 0.0) + n.cell_count
	for d in defs:
		if is_unlocked(d.id) or not YEARLY.has(d.cond):
			continue
		match d.cond:
			&"peace_years":
				_record(world, d, (world.year - _peace_since) / d.target if _peace_since >= 0 else 0.0, got)
			&"nation_share":
				_record(world, d, best_nation / maxf(1.0, land) / d.share, got)
			&"race_share":
				_record(world, d, by_race.get(d.race, 0.0) / maxf(1.0, land) / d.share, got)
			&"hero_level":
				var lvl := 0
				for h in world.heroes:
					if h.alive:
						lvl = maxi(lvl, h.level)
				_record(world, d, lvl / d.target, got)
			&"religion_races":
				_record(world, d, _faith_races(world) / d.target, got)
			&"nations_total":
				_record(world, d, world.nations.size() / d.target, got)
			&"year":
				_record(world, d, world.year / d.target, got)
	if not got.is_empty() or world.year % 10 == 0:
		save_profile()
	return got


## Наибольшее число рас, у которых одна вера — вера большинства регионов.
static func _faith_races(world: World) -> int:
	var races := {}
	for region in world.regions:
		var f := region.main_faith()
		var o := region.controller()
		if f < 0 or o < 0:
			continue
		var r := world.region_majority_race(region, o)
		if r == World.NO_RACE:
			continue
		var seen: Dictionary = races.get(f, {})
		seen[r] = true
		races[f] = seen
	var best := 0
	for f in races:
		best = maxi(best, (races[f] as Dictionary).size())
	return best


func _record(world: World, d: AchievementDef, value: float, got: Array[AchievementDef]) -> void:
	var key := String(d.id)
	if value >= 1.0:
		_unlock(world, d, got)
	elif value > float(progress.get(key, 0.0)):
		progress[key] = snappedf(value, 0.001)


func _unlock(world: World, d: AchievementDef, got: Array[AchievementDef]) -> void:
	unlocked[String(d.id)] = {"year": world.year if world != null else 0, "date": Time.get_datetime_string_from_system(false, true)}
	progress.erase(String(d.id))
	got.append(d)
