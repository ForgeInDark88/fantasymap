extends SceneTree
## Headless-проверка сохранения/загрузки: мир после 60 лет сохраняется в JSON,
## загружается, совпадает по ключевым данным и продолжает симулироваться так же,
## как оригинал (детерминизм ГСЧ).
##   godot --headless --path . -s res://tests/save_test.gd -- [seed]

var _failures := 0
## Разделы, появившиеся после формата v1 (этапы 7+): сравниваются после продолжения
## истории и вырезаются при имитации старого сохранения.
const NEW_KEYS: Array[String] = ["religions", "cultures", "societies", "orgs", "legacies", "roads", "climate", "counters", "caves", "ruins", "crisis", "lore"]
const NEW_NATION_KEYS: Array[String] = ["religion", "unity", "effects", "techs", "researching", "research", "tech_seen",
	"culture", "culture_level", "intel", "legacy", "home", "tdirty"]
const NEW_REGION_KEYS: Array[String] = ["faith", "culture", "assim"]
const NEW_HERO_KEYS: Array[String] = ["parents", "children", "lineage", "artifact_id", "order", "god", "chosen", "awits", "pl"]


static func _as_v1(d: Dictionary) -> Dictionary:
	d.version = 1
	for k in NEW_KEYS:
		d.erase(k)
	for n in d.nations:
		for k in NEW_NATION_KEYS:
			n.erase(k)
	for r in d.regions:
		for k in NEW_REGION_KEYS:
			r.erase(k)
	for h in d.heroes:
		for k in NEW_HERO_KEYS:
			h.erase(k)
	return d


func _initialize() -> void:
	var s := MapSettings.new()
	var args := OS.get_cmdline_user_args()
	s.world_seed = int(args[0]) if args.size() > 0 else 77
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 60:
		sim.step(world)
	for i in 5:
		sim.step_month(world)

	var path := "user://saves/_test.json"
	var t0 := Time.get_ticks_msec()
	_expect(SaveSystem.save_world(world, path) == OK, "сохранение не записано")
	var t1 := Time.get_ticks_msec()
	var loaded := SaveSystem.load_world(path)
	var t2 := Time.get_ticks_msec()
	_expect(loaded != null, "сохранение не загружено")
	if loaded == null:
		_finish()
		return
	var size := FileAccess.open(path, FileAccess.READ).get_length()
	print("Запись %d мс, чтение %d мс, файл %.1f КБ" % [t1 - t0, t2 - t1, size / 1024.0])

	_expect(loaded.date_text() == world.date_text(), "дата не совпала")
	_expect(loaded.owner == world.owner, "владельцы клеток не совпали")
	_expect(loaded.region_of == world.region_of, "регионы не совпали")
	_expect(loaded.cities.size() == world.cities.size(), "число городов")
	_expect(loaded.heroes.size() == world.heroes.size(), "число героев")
	_expect(loaded.diplomacy.wars.size() == world.diplomacy.wars.size(), "число войн")
	_expect(loaded.chronicle.size() == world.chronicle.size(), "летопись")
	for k in world.nations.size():
		var a := world.nations[k]
		var b := loaded.nations[k]
		_expect(a.name == b.name and a.alive == b.alive and a.cell_count == b.cell_count, "государство %d" % k)
		_expect(absf(a.population - b.population) < 1.0, "население %s" % a.name)
		_expect(a.yields == b.yields, "добыча %s" % a.name)
		_expect(a.borders == b.borders, "границы %s" % a.name)
		_expect(absf(a.food_bonus - b.food_bonus) < 1e-4 and a.sources == b.sources, "бонусы %s" % a.name)
	for k in world.regions.size():
		_expect(world.regions[k].owner_counts == loaded.regions[k].owner_counts, "счётчики региона %d" % k)

	# Повторное сохранение загруженного мира даёт ту же структуру (числа — с точностью
	# до последнего бита double: парсер JSON не всегда восстанавливает его точно).
	var again := SaveSystem.to_dict(loaded)
	_expect(again.cells.owner == SaveSystem.to_dict(world).cells.owner and again.nations.size() == world.nations.size(), "повторная запись отличается")

	# Оба мира продолжают жить одинаково.
	for y in 15:
		sim.step(world)
		sim.step(loaded)
	_expect(loaded.owner == world.owner, "после 15 лет карты разошлись")
	_expect(loaded.chronicle_total == world.chronicle_total, "после 15 лет летописи разошлись")
	var da := SaveSystem.to_dict(world)
	var db := SaveSystem.to_dict(loaded)
	for key in NEW_KEYS:
		if JSON.stringify(da.get(key)) != JSON.stringify(db.get(key)):
			# Что именно разошлось (раздел — массив или словарь).
			var va: Variant = da[key]
			var vb: Variant = db[key]
			var ks: Array = va.keys() if va is Dictionary else range(mini(va.size(), vb.size()))
			for i in ks:
				var ea := JSON.stringify(va.get(i) if va is Dictionary else va[i])
				var eb := JSON.stringify(vb.get(i) if vb is Dictionary else vb[i])
				if ea != eb:
					print(key, " ", i, ": ", ea.left(300), "\n  ", eb.left(300))
		_expect(JSON.stringify(da.get(key)) == JSON.stringify(db.get(key)), "после 15 лет разошлось: " + key)
	_expect(JSON.stringify(da.regions.map(func(r): return r.faith)) == JSON.stringify(db.regions.map(func(r): return r.faith)), "после 15 лет разошлась вера регионов")
	_expect(JSON.stringify(da.regions.map(func(r): return [r.culture, r.assim])) == JSON.stringify(db.regions.map(func(r): return [r.culture, r.assim])), "после 15 лет разошлась культура регионов")
	_expect(JSON.stringify(da.nations.map(func(n): return n.techs)) == JSON.stringify(db.nations.map(func(n): return n.techs)), "после 15 лет разошлись технологии")

	# Старое сохранение (формат v1, без новых систем) загружается и живёт дальше.
	var old := _as_v1(SaveSystem.to_dict(world))
	var restored := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(JSON.stringify(SaveSystem.exact(old), "", false, true))))
	_expect(restored != null and restored.owner == world.owner, "сохранение v1 не загрузилось")
	if restored != null:
		for y in 3:
			sim.step(restored)
		_expect(restored.nations.size() >= world.nations.size(), "мир из v1 не живёт")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_finish()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _finish() -> void:
	print("save_test: %s" % ("OK" if _failures == 0 else "%d ошибок" % _failures))
	quit(1 if _failures > 0 else 0)
