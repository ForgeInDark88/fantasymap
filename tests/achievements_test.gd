extends SceneTree
## Headless-проверка этапа 10.4: данные достижений корректны; условия
## срабатывают по событиям мира (летопись, счётчики через World.observer,
## смена года) и интерфейса, а не опросом; прогресс копится; профиль
## пишется в отдельный файл вне сохранений мира и читается обратно.
##   godot --headless --path . -s res://tests/achievements_test.gd

const PROFILE := "user://_test_achievements.json"
var _failures := 0


func _initialize() -> void:
	DirAccess.remove_absolute(PROFILE)
	var tr := AchievementTracker.new(PROFILE)
	_expect(tr.defs.size() >= 15, "мало достижений")
	var conds := [&"count", &"event", &"peace_years", &"nation_share", &"race_share", &"hero_level", &"religion_races", &"nations_total", &"year", &"ui"]
	for d in tr.defs:
		_expect(conds.has(d.cond) and not d.title.is_empty() and not d.description.is_empty(), "достижение %s некорректно" % d.id)
		if d.cond == &"race_share":
			_expect(RaceDB.get_race(d.race) != null, "достижение %s: нет расы %s" % [d.id, d.race])
	var s := MapSettings.new()
	s.world_seed = 99
	s.apply_size_preset(0)
	var world := World.create(s)
	var got: Array[StringName] = []
	world.observer = func(what: StringName, data: Dictionary) -> void:
		for d in tr.handle(world, what, data):
			got.append(d.id)
	tr.reset_world(world)
	var sim := Simulation.new()
	for y in 120:
		sim.step(world)
		for d in tr.new_year(world):
			got.append(d.id)
	print("за 120 лет получено: %s" % [got])
	# Сценарные события.
	world.log_event(&"great", "Врата бездны в регионе Тест закрыты — их запечатал свет.")
	_expect(tr.is_unlocked(&"portal_closed"), "закрытие врат не засчитано")
	world.count(&"survived_great_plague")
	_expect(tr.is_unlocked(&"survive_plague"), "чума не засчитана")
	tr.handle(world, &"ui", {"key": &"chronicle_export"})
	_expect(tr.is_unlocked(&"chronicler"), "событие интерфейса не засчитано")
	# Прогресс годового условия и повторное срабатывание.
	var crises := 0
	for d in tr.defs:
		if d.id == &"crises_3" and not tr.is_unlocked(d.id):
			world.counters[&"crises_survived"] = 0
			world.count(&"crises_survived")
			_expect(absf(tr.get_progress(d) - 1.0 / 3.0) < 0.01, "прогресс счётчика")
			crises = 1
	var before := tr.unlocked.size()
	world.log_event(&"great", "Врата бездны в регионе Тест закрыты.")
	_expect(tr.unlocked.size() == before, "достижение получено дважды")
	# Мир без войн: серия лет без войн.
	var peace := tr.defs.filter(func(d: AchievementDef) -> bool: return d.id == &"peace_100")[0] as AchievementDef
	if not tr.is_unlocked(&"peace_100"):
		for w in world.diplomacy.wars.duplicate():
			world.diplomacy.end_war(world, w, 0)
		tr.reset_world(world)
		world.year += 50
		tr.new_year(world)
		_expect(tr.get_progress(peace) >= 0.49, "серия мира не копится (%.2f)" % tr.get_progress(peace))
	# Профиль на диске.
	tr.save_profile()
	var tr2 := AchievementTracker.new(PROFILE)
	_expect(tr2.unlocked.size() == tr.unlocked.size() and tr2.is_unlocked(&"portal_closed"), "профиль не прочитался")
	_expect(not FileAccess.get_file_as_string(PROFILE).contains("\"owner\""), "")
	DirAccess.remove_absolute(PROFILE)
	print("достижений получено: %d из %d (серия кризисов: %d)" % [tr.unlocked.size(), tr.defs.size(), crises])
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
