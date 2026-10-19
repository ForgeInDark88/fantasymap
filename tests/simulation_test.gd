extends SceneTree
## Headless-проверка этапа 3: прогон симуляции, инварианты учёта клеток,
## рост населения, экспансия, города, постройки, скорость тика.
##   godot --headless --path . -s res://tests/simulation_test.gd -- [годы] [seed] [размер 0..3] [государств]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 400
	var s := MapSettings.new()
	s.world_seed = int(args[1]) if args.size() > 1 else 1
	s.apply_size_preset(int(args[2]) if args.size() > 2 else 1)
	if args.size() > 3:
		s.nation_count = int(args[3])
	var world := World.create(s)
	var sim := Simulation.new()
	var start_pop := _total_pop(world)
	var start_cells := _owned(world)
	var land := 0
	for i in world.map.cell_count():
		if world.map.is_land(i):
			land += 1

	var t0 := Time.get_ticks_usec()
	var worst := 0
	for y in years:
		var ts := Time.get_ticks_usec()
		sim.step(world)
		worst = maxi(worst, Time.get_ticks_usec() - ts)
		if y % 50 == 49:
			_report(world, land)
			_check_invariants(world)
	var avg_ms := (Time.get_ticks_usec() - t0) / 1000.0 / years
	print("тик: в среднем %.2f мс, худший %.2f мс (%d государств, карта %dx%d)" % [avg_ms, worst / 1000.0, world.nations.size(), s.width, s.height])

	if _total_pop(world) <= start_pop:
		_fail("население не выросло: %d → %d" % [start_pop, _total_pop(world)])
	if _owned(world) <= start_cells * 2:
		_fail("территории почти не выросли: %d → %d клеток" % [start_cells, _owned(world)])
	if world.cities.size() <= world.nations.size() * 2:
		_fail("новые города не основываются (%d)" % world.cities.size())
	var buildings := {}
	for city in world.cities:
		for b in city.buildings:
			buildings[b] = buildings.get(b, 0) + 1
	print("постройки: ", buildings)
	if buildings.is_empty():
		_fail("ничего не построено")
	var top := world.cities.duplicate()
	top.sort_custom(func(a: City, b: City) -> bool: return a.population > b.population)
	print("крупнейшие города: ", ", ".join(top.slice(0, 6).map(func(c: City) -> String:
		return "%s %.0f тыс. (%d построек)" % [c.name, c.population / 1000.0, c.buildings.size()])))
	var kinds := {}
	for e in world.chronicle:
		kinds[e.kind] = kinds.get(e.kind, 0) + 1
	print("летопись: %d записей %s" % [world.chronicle_total, kinds])
	for e in world.chronicle.slice(maxi(0, world.chronicle.size() - 8)):
		print("    год %d: %s" % [e.year, e.text])
	for n in world.nations:
		print("    %-28s %-10s клеток %4d, нас. %6.0f тыс. (своих %3d%%), городов %2d, армия %5d, стаб. %.2f, наука %.1f, запасы %s" % [
			n.name, n.race_id, n.cell_count, n.population / 1000.0, roundi(n.primary_share() * 100.0), n.city_ids.size(),
			n.army, n.stability, n.tech, Array(n.stock).map(func(v: float) -> int: return roundi(v))])
	if avg_ms > 8.0:
		_fail("тик слишком медленный: %.2f мс" % avg_ms)

	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _report(world: World, land: int) -> void:
	var owned := _owned(world)
	var line := "год %4d: занято %5.1f%% суши, население %7.0f тыс., городов %3d |" % [
		world.year, owned * 100.0 / land, _total_pop(world) / 1000.0, world.cities.size()]
	var by_race := {}
	for n in world.nations:
		by_race[n.race_id] = by_race.get(n.race_id, 0) + n.cell_count
	for r in by_race:
		line += " %s:%d" % [r, by_race[r]]
	print(line)


func _check_invariants(world: World) -> void:
	var counted := PackedInt32Array()
	counted.resize(world.nations.size())
	for i in world.owner.size():
		var o := world.owner[i]
		if o < 0:
			continue
		counted[o] += 1
		var nation := world.nations[o]
		if nation.cells[world.cell_slot[i]] != i:
			_fail("год %d: cell_slot рассогласован в клетке %d" % [world.year, i])
			return
		if world.owner_texels[i * 4] + world.owner_texels[i * 4 + 1] * 256 - 1 != o:
			_fail("год %d: owner_texels рассогласован" % world.year)
			return
	for nation in world.nations:
		if counted[nation.id] != nation.cell_count:
			_fail("год %d: у %s cell_count %d, а клеток %d" % [world.year, nation.name, nation.cell_count, counted[nation.id]])
		for r in nation.pop.size():
			if is_nan(nation.pop[r]) or nation.pop[r] < 0.0:
				_fail("год %d: население %s некорректно" % [world.year, nation.name])
		for g in Goods.COUNT:
			if is_nan(nation.stock[g]):
				_fail("год %d: запас %s у %s = NaN" % [world.year, Goods.NAMES[g], nation.name])


func _owned(world: World) -> int:
	var total := 0
	for n in world.nations:
		total += n.cell_count
	return total


func _total_pop(world: World) -> float:
	var total := 0.0
	for n in world.nations:
		total += n.population
	return total


func _fail(msg: String) -> void:
	_failures += 1
	printerr("FAIL: ", msg)
