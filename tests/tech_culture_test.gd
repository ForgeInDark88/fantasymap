extends SceneTree
## Headless-проверка технологий и культуры: данные (требования без циклов,
## расовые запреты), исследование и распространение, ассимиляция регионов и
## народов (учёт ёмкости не ломается), инструменты Бога, детерминизм.
##   godot --headless --path . -s res://tests/tech_culture_test.gd -- [годы]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 300
	_check_data()
	for cfg in [[31, 0, 10], [505, 2, 24]]:
		var s := MapSettings.new()
		s.world_seed = cfg[0]
		s.apply_size_preset(cfg[1])
		s.nation_count = cfg[2]
		var world := World.create(s)
		var sim := Simulation.new()
		for y in years:
			sim.step(world)
			if y % 100 == 99:
				_check(world)
		var assim: int = world.counters.get(&"assimilations", 0)
		var techs := 0
		for e in world.chronicle:
			if e.kind == &"tech":
				techs += 1
		var alive := world.nations.filter(func(n: Nation) -> bool: return n.alive)
		var avg := 0.0
		for n in alive:
			avg += n.techs.size()
		avg /= maxf(1.0, alive.size())
		print("seed %d: технологий в среднем %.1f, записей об открытиях %d, ассимиляций %d, культур %d" % [
			cfg[0], avg, techs, assim, world.cultures.size()])
		_expect(avg >= 2.0, "технологии почти не открываются")
		_expect(assim > 0, "культура ни разу не распространилась")

	# Инструменты Бога.
	var s2 := MapSettings.new()
	s2.world_seed = 12
	var w := World.create(s2)
	var sim2 := Simulation.new()
	for y in 30:
		sim2.step(w)
	var nation: Nation = w.nations.filter(func(n: Nation) -> bool: return n.alive)[0]
	var before := nation.techs.size()
	_expect(GodTools.insight(w, nation) != null and nation.techs.size() == before + 1, "озарение не дало технологию")
	var target := -1
	for n in w.nations:
		if not n.alive:
			continue
		for rid in n.region_counts:
			if w.regions[rid].culture != n.culture and w.regions[rid].controller() == n.id:
				target = w.regions[rid].center
	if target >= 0 and w.owner[target] >= 0:
		_expect(GodTools.assimilate(w, target) and w.region_at(target).culture == w.nations[w.owner[target]].culture,
				"слияние культур не сработало")
	_check(w)

	_expect(_digest(8) == _digest(8), "технологии и культура недетерминированы")
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _check_data() -> void:
	var all := TechDB.all()
	_expect(all.size() >= 20, "мало технологий")
	# Требования без циклов: каждую технологию можно открыть, открывая доступные по порядку.
	var known := {}
	var progress := true
	while progress:
		progress = false
		for res in all:
			var t := res as TechDef
			if known.has(t.id):
				continue
			var ok := true
			for r in t.requires:
				ok = ok and known.has(r)
			if ok:
				known[t.id] = true
				progress = true
	_expect(known.size() == all.size(), "есть недостижимые технологии (цикл в требованиях)")
	var necro := TechDB.find(&"necromancy")
	_expect(necro != null and necro.race_weight(RaceDB.get_race(&"humans")) == 0.0 and necro.race_weight(RaceDB.get_race(&"undead")) > 1.0,
			"некромантия не расовая")
	for b in EconomyDB.buildings():
		if b.requires_tech != &"":
			_expect(TechDB.find(b.requires_tech) != null, "постройка %s требует неизвестную технологию" % b.id)


func _check(world: World) -> void:
	for n in world.nations:
		if not n.alive:
			continue
		for t in n.techs:
			var def := TechDB.find(t)
			if def == null or def.race_weight(n.race) <= 0.0:
				_expect(false, "%s знает недоступную технологию %s" % [n.name, t])
				return
			for r in def.requires:
				if not n.techs.has(r):
					_expect(false, "%s знает %s без %s" % [n.name, t, r])
					return
		if n.culture < 0 or n.culture >= world.cultures.size():
			_expect(false, "у %s нет культуры" % n.name)
			return
		# Ёмкость земли по народам совпадает с клетками (ассимиляция не ломает учёт).
		var cap := PackedFloat32Array()
		cap.resize(RaceDB.count())
		for c in n.cells:
			var r := world.cell_race[c]
			if r != World.NO_RACE:
				cap[r] += world.cell_capacity(RaceDB.by_index(r), c)
		for r in cap.size():
			if absf(cap[r] - n.capacity[r]) > maxf(5.0, cap[r] * 0.01):
				_expect(false, "ёмкость народа %d у %s: %.0f ≠ %.0f" % [r, n.name, cap[r], n.capacity[r]])
				return
	for region in world.regions:
		if region.culture >= world.cultures.size() or region.assim < 0.0 or region.assim > 1.0001:
			_expect(false, "культура региона %d некорректна" % region.id)
			return


func _digest(seed: int) -> String:
	var s := MapSettings.new()
	s.world_seed = seed
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 80:
		sim.step(world)
	var parts: Array[String] = []
	for n in world.nations:
		parts.append(str(n.techs.keys()) + str(n.culture) + "%.4f" % n.research)
	for r in world.regions:
		parts.append("%d:%.4f" % [r.culture, r.assim])
	return "|".join(parts)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
