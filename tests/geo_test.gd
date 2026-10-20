extends SceneTree
## Headless-проверка этапа 9 (география, мир, экономика): дороги и торговые
## пути — согласованность графа, блокада, стоимость пути по рельефу; долгий
## прогон на разных картах; детерминизм.
##   godot --headless --path . -s res://tests/geo_test.gd -- [годы]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 300
	for cfg in [[51, 0, 10], [707, 2, 26]]:
		var s := MapSettings.new()
		s.world_seed = cfg[0]
		s.apply_size_preset(cfg[1])
		s.nation_count = cfg[2]
		var world := World.create(s)
		var sim := Simulation.new()
		for y in years:
			sim.step(world)
			if y % 50 == 49:
				_check_roads(world)
		var alive := world.roads.filter(func(r: Road) -> bool: return r.alive)
		var traffic := 0.0
		for r in alive:
			traffic += r.traffic
		print("seed %d: дорог %d (морских %d), оборот %.0f" % [cfg[0], alive.size(),
			alive.filter(func(r: Road) -> bool: return r.sea).size(), traffic])
		_expect(alive.size() > world.nations.filter(func(n: Nation) -> bool: return n.alive).size(), "дорог почти нет")
		_expect(traffic > 0.0, "торговли по дорогам нет")
		_expect(not world.volcanoes.is_empty(), "нет вулканов")
		_check_accounting(world)
		_check_caves(world)
	_scripted_roads()
	_scripted_underground()
	_scripted_ruins()
	_scripted_crises()
	_scripted_climate()
	_expect(_digest(17) == _digest(17), "этап 9 недетерминирован")
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _scripted_roads() -> void:
	var s := MapSettings.new()
	s.world_seed = 19
	var w := World.create(s)
	var sim := Simulation.new()
	for y in 30:
		sim.step(w)
	# Путь через воду для сухопутной дороги невозможен; горы дороже равнин.
	var land := -1
	var water := -1
	for i in w.map.cell_count():
		if land < 0 and w.map.biome[i] == Biome.PLAINS:
			land = i
		if water < 0 and w.map.biome[i] == Biome.OCEAN:
			water = i
	_expect(RoadSystem.measure(w, land, water).x < 0.0, "дорога прошла по воде")
	# Дорога по воле Бога и блокада на войне.
	var cities := w.cities.filter(func(c: City) -> bool: return c.alive)
	var road := GodTools.road_from(w, cities[0].cell)
	_expect(road != null and RoadSystem._connected(w, road.a, road.b), "дорога не проложена")
	if road != null:
		var na := w.cities[road.a].nation_id
		var nb := w.cities[road.b].nation_id
		if na != nb and na >= 0 and nb >= 0:
			if w.diplomacy.war_between(na, nb) == null:
				w.diplomacy.declare_war(w, na, nb, &"territory")
			RoadSystem.new()._trade(w, w.nations[na])
			_expect(road.traffic == 0.0, "блокада не закрыла путь между врагами")
	_check_roads(w)


func _scripted_climate() -> void:
	var s := MapSettings.new()
	s.world_seed = 23
	var w := World.create(s)
	var sim := Simulation.new()
	for y in 20:
		sim.step(w)
	for v in w.volcanoes:
		_expect(w.map.biome[v] == Biome.MOUNTAINS or w.map.biome[v] == Biome.SNOW or w.map.biome[v] == Biome.HILLS, "вулкан не в горах")
	# Извержение: пепельная зима — урожай ниже.
	_expect(GodTools.eruption(w, w.volcanoes[0]), "извержение не случилось")
	_expect(w.ash_until > w.year and w.scars.any(func(sc: Dictionary) -> bool: return sc.kind == "ash"), "нет пепла")
	sim.step(w)
	_expect(w.zone_harvest[0] < 1.0 and w.zone_harvest[1] < 1.0, "пепельная зима не снизила урожай")
	# Засуха по воле Бога.
	GodTools.drought(w, w.cities.filter(func(c: City) -> bool: return c.alive)[0].cell)
	# Сильный сдвиг климата — биомы в нескольких регионах меняются, учёт не ломается.
	var before := w.map.biome.duplicate()
	w.temp_shift = 0.12
	w.moist_shift = -0.1
	var climate := ClimateSystem.new()
	for y in 4:
		while w.year % ClimateSystem.DRIFT_PERIOD != 0:
			w.year += 1
		climate.tick_year(w)
		w.year += 1
	_expect(before != w.map.biome, "биомы не сдвинулись при сильном сдвиге климата")
	_check_accounting(w)


func _scripted_underground() -> void:
	var s := MapSettings.new()
	s.world_seed = 29
	var a := World.create(s)
	var b := World.create(s)
	_expect(a.caves.size() >= 8, "мало пещер")
	_expect(a.caves.map(func(c: Cave) -> String: return "%d:%d:%s" % [c.cell, c.depth, c.kind]) ==
			b.caves.map(func(c: Cave) -> String: return "%d:%d:%s" % [c.cell, c.depth, c.kind]), "пещеры недетерминированы")
	var sim := Simulation.new()
	for y in 60:
		sim.step(a)
	_check_caves(a)
	var armies := 0.0
	for n in a.nations:
		armies += n.army
	if UndergroundSystem.invasion(a):
		var after := 0.0
		for n in a.nations:
			after += n.army
		_expect(after < armies and a.counters.get(&"invasions", 0) >= 1, "нашествие из глубин ничего не сделало")
	var owned: Cave = null
	for c in a.caves:
		if c.owner >= 0 and a.region_of[c.cell] >= 0:
			owned = c
	if owned != null:
		_expect(UndergroundSystem.sapping(a, PackedInt32Array([owned.owner]), a.region_of[owned.cell]), "подкоп не найден")


func _scripted_ruins() -> void:
	var s := MapSettings.new()
	s.world_seed = 31
	var w := World.create(s)
	var sim := Simulation.new()
	for y in 40:
		sim.step(w)
	# Разрушенный город оставляет руины (крупный — всегда).
	var city: City = null
	for c in w.cities:
		if c.alive and not c.is_capital and c.tier() >= 1:
			city = c
	var before := w.ruins.size()
	if city != null:
		w.destroy_city(city)
		_expect(w.ruins.size() == before + 1 and w.ruins[w.ruins.size() - 1].cell == city.cell, "город не оставил руин")
	# Древние руины по воле Бога; герой исследует их.
	var cell: int = w.cities.filter(func(c: City) -> bool: return c.alive)[0].cell
	var ruin := GodTools.ancient_ruin(w, cell)
	_expect(ruin != null and ruin.kind == &"temple", "руины не открылись")
	if ruin != null:
		var nation := w.nations[w.owner[cell]] if w.owner[cell] >= 0 else w.nations[0]
		var hero := HeroSystem.spawn(w, nation, w.region_at(cell), true)
		hero.level = 20
		hero.intellect = 1.0
		hero.cell = cell
		var wealth := ruin.wealth
		for i in 60:
			if ruin.wealth < wealth or not hero.alive:
				break
			RuinSystem.hero_explore(w, hero)
		_expect(ruin.wealth < wealth or not hero.alive, "герой так и не исследовал руины")
	# Проклятый герой получает трон в глухих руинах, если они есть.
	var remote := RuinSystem.remote_ruin(w)
	var h2 := HeroSystem.spawn(w, w.nations[0], w.regions[0], true)
	h2.die(w)
	var throne := Fate.curse(w, h2)
	if remote != null and throne != null:
		_expect(throne.cell == remote.cell, "трон не в руинах")
	for y in 20:
		sim.step(w)
	for r in w.ruins:
		if r.cell >= 0 and not w.map.is_land(r.cell):
			_expect(false, "руины в воде")
			break


func _scripted_crises() -> void:
	var s := MapSettings.new()
	s.world_seed = 37
	var w := World.create(s)
	var sim := Simulation.new()
	for y in 30:
		sim.step(w)
	_expect(not w.eras.is_empty() and w.eras[0].name == "Эпоха Зари", "нет первой эпохи")
	for res in CrisisDB.all():
		var def := res as CrisisDef
		_expect(def.stage_years.size() == def.stage_names.size() and def.stage_effects.size() == def.stage_names.size(),
				"стадии кризиса %s описаны не полностью" % def.id)
		CrisisSystem.start(w, def)
		_expect(w.crisis.id == str(def.id), "кризис %s не начался" % def.id)
		var affected := w.nations.filter(func(n: Nation) -> bool: return n.alive and n.effect_sources.has(&"crisis")).size()
		_expect(affected > 0 or def.stage_effects[0].is_empty(), "кризис %s не действует на государства" % def.id)
		if def.special == &"invasion":
			_expect(int(w.crisis.invader) >= 0 and w.nations[int(w.crisis.invader)].alive, "Орда не высадилась")
		if def.unite:
			_expect(w.orgs.any(func(o: Organization) -> bool: return o.alive and o.def.basis == "crisis"), "Великий союз не собран")
		var total := 0
		for y in def.stage_years:
			total += y
		for y in total + 2:
			sim.step(w)
			if w.crisis.is_empty():
				break
			if def.special == &"titan" and int(w.crisis.titan_cell) >= w.map.cell_count():
				_expect(false, "титан ушёл с карты")
		_expect(w.crisis.is_empty(), "кризис %s не закончился" % def.id)
		_expect(not w.nations.any(func(n: Nation) -> bool: return n.alive and n.effect_sources.has(&"crisis")), "эффекты кризиса %s не сняты" % def.id)
		EraSystem.new().tick_year(w)
	_expect(w.crisis_history.size() == CrisisDB.all().size(), "история кризисов неполна")
	for i in w.eras.size() - 1:
		_expect(w.eras[i].end == w.eras[i + 1].start, "эпохи идут с разрывом")
	_check_accounting(w)


func _check_caves(world: World) -> void:
	if world.caves.is_empty():
		return
	var seen := {0: true}
	var queue: Array = [0]
	while not queue.is_empty():
		var id: int = queue.pop_back()
		for nb in world.caves[id].neighbors:
			if not world.caves[nb].neighbors.has(id):
				_expect(false, "несимметричный ход %d—%d" % [id, nb])
				return
			if not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	_expect(seen.size() == world.caves.size(), "подземный мир несвязен")
	for c in world.caves:
		if c.owner >= 0 and (c.owner >= world.nations.size() or not world.nations[c.owner].alive):
			_expect(false, "пещерой владеет павшее государство")
			return
		if c.entrance and c.depth != 1:
			_expect(false, "вход не на первой глубине")
			return


## Добыча и ёмкость земли государств совпадают с их клетками (дрейф биомов не ломает учёт).
func _check_accounting(world: World) -> void:
	for n in world.nations:
		if not n.alive:
			continue
		var y := PackedFloat32Array()
		y.resize(Goods.COUNT)
		var cap := PackedFloat32Array()
		cap.resize(RaceDB.count())
		for c in n.cells:
			for g in Goods.COUNT:
				y[g] += world.cell_yield[c * Goods.COUNT + g]
			var r := world.cell_race[c]
			if r != World.NO_RACE:
				cap[r] += world.cell_capacity(RaceDB.by_index(r), c)
		for g in Goods.COUNT:
			if absf(y[g] - n.yields[g]) > maxf(1.0, y[g] * 0.01):
				_expect(false, "добыча %d у %s: %.1f ≠ %.1f" % [g, n.name, y[g], n.yields[g]])
				return
		for r in cap.size():
			if absf(cap[r] - n.capacity[r]) > maxf(5.0, cap[r] * 0.01):
				_expect(false, "ёмкость народа %d у %s: %.0f ≠ %.0f" % [r, n.name, cap[r], n.capacity[r]])
				return


func _check_roads(world: World) -> void:
	var pairs := {}
	for r in world.roads:
		if r.a < 0 or r.a >= world.cities.size() or r.b < 0 or r.b >= world.cities.size() or r.a == r.b:
			_expect(false, "дорога %d с неверными концами" % r.id)
			return
		if r.safety < 0.0 or r.safety > 1.0 or r.length <= 0.0:
			_expect(false, "дорога %d: безопасность или длина вне пределов" % r.id)
			return
		for c in [r.a, r.b]:
			if not world.city_roads.get(c, PackedInt32Array()).has(r.id):
				_expect(false, "дорога %d не учтена у города %d" % [r.id, c])
				return
		if r.alive:
			var key := Vector2i(mini(r.a, r.b), maxi(r.a, r.b))
			if pairs.has(key):
				_expect(false, "две дороги между одними городами")
				return
			pairs[key] = true


func _digest(seed: int) -> String:
	var s := MapSettings.new()
	s.world_seed = seed
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 80:
		sim.step(world)
	var parts: Array[String] = []
	for r in world.roads:
		parts.append("%d-%d:%.3f:%.3f" % [r.a, r.b, r.length, r.safety])
	return "|".join(parts)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
