extends SceneTree
## Headless-проверка этапа 11.B (армии, флоты, полководцы):
##   • инварианты в долгом прогоне: армия не теряется и не раздваивается (одна
##     армия на государство в войне), стоит в существующем регионе, ссылки
##     полководцев и армий согласованы, доля сил в (0, 1];
##   • война двух соседей: армии собираются, идут, бьются, фронт движется
##     (осада растёт, регионы переходят);
##   • сохранение → загрузка с армиями в походе: одинаковое продолжение;
##   • инструменты Бога: создать, уничтожить, флот, бунт;
##   • производительность на огромной карте с 50 государствами.
##   godot --headless --path . -s res://tests/army_test.gd -- [годы]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 200
	_long_run(years)
	_front()
	_save_load()
	_god_tools()
	_performance()
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _check(world: World, where: String) -> void:
	var seen := {}
	for a in world.armies:
		if not a.alive:
			continue
		if a.kind == &"pirates":
			_expect(a.nation < 0 and a.own_strength > 0.0, "%s: пираты неверны" % where)
			continue
		_expect(a.nation >= 0 and world.nations[a.nation].alive, "%s: армия павшего государства" % where)
		_expect(a.region >= 0 and a.region < world.regions.size() and a.cell == world.regions[a.region].center, "%s: армия вне карты" % where)
		_expect(a.share > 0.0 and a.share <= 1.0, "%s: доля сил %.2f" % [where, a.share])
		var key := "%d:%d:%s" % [a.nation, a.war, a.kind]
		_expect(a.war < 0 or not seen.has(key), "%s: армия раздвоилась (%s)" % [where, key])
		seen[key] = true
		if a.general >= 0:
			_expect(int(world.generals[a.general].army) == a.id, "%s: полководец не знает своей армии" % where)
		if a.war >= 0:
			var war: War = null
			for w in world.diplomacy.wars:
				if w.id == a.war:
					war = w
			if war != null:
				_expect(war.side_of(a.nation) != 0, "%s: армия не участника войны" % where)
	for g in world.generals:
		if int(g.army) >= 0:
			_expect(int(g.army) < world.armies.size() and world.armies[int(g.army)].general == int(g.id), "%s: армия не знает полководца" % where)


var total_conquests := 0


func _long_run(years: int) -> void:
	for cfg in [[2024, 1], [9, 0]]:
		var s := MapSettings.new()
		s.world_seed = cfg[0]
		s.apply_size_preset(cfg[1])
		var world := World.create(s)
		var sim := Simulation.new()
		var max_armies := 0
		var marching := 0
		for y in years:
			sim.step(world)
			max_armies = maxi(max_armies, world.armies.size())
			for a in world.armies:
				if a.alive and a.state == &"march":
					marching += 1
			if y % 25 == 24:
				_check(world, "seed %d, год %d" % [cfg[0], world.year])
		var wars := world.diplomacy.past_wars.size() + world.diplomacy.wars.size()
		var battles := 0
		for w in world.diplomacy.past_wars + world.diplomacy.wars:
			battles += w.battles
		var conquests := world.chronicle.filter(func(e: Dictionary) -> bool: return e.kind == &"conquest").size()
		print("seed %d: войн %d, битв %d, захватов %d, полководцев %d, пиратов %d, наибольшее число армий %d" % [cfg[0], wars, battles,
			conquests, world.generals.size(), world.counters.get(&"pirates", 0), max_armies])
		_expect(battles > 0 and marching > 0, "армии не воюют")
		total_conquests += conquests
	_expect(total_conquests > 0, "армии не берут регионы")


## Два соседа воюют: армии собираются, идут к цели, бьются и/или осаждают.
func _front() -> void:
	var s := MapSettings.new()
	s.world_seed = 77
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 40:
		sim.step(world)
	var a: Nation = null
	var b: Nation = null
	# Соседи в мире — не обязательно в этот год (все могут уже воевать): ищем несколько лет.
	for attempt in 10:
		for n in world.nations:
			if n.alive:
				for o in n.borders:
					if world.nations[o].alive and world.diplomacy.war_between(n.id, o) == null:
						a = n
						b = world.nations[o]
						break
			if a != null:
				break
		if a != null:
			break
		sim.step(world)
	if a == null:
		# Соседей так и нет — Бог создаёт государство в ничейном крае рядом с первым.
		var first := world.nations.filter(func(n: Nation) -> bool: return n.alive)[0] as Nation
		for rid in first.region_counts:
			for nb in world.regions[rid].neighbors:
				if a == null and world.regions[nb].owner_counts.is_empty() and world.regions[nb].cells.size() >= 4:
					var other := GodTools.create_nation(world, RaceDB.all()[0], world.regions[nb].center, false)
					if other != null:
						a = first
						b = other
	_expect(a != null, "нет соседей для войны")
	if a == null:
		return
	a.army = maxf(a.army, b.army * 2.5 + 5000.0)
	var war := world.diplomacy.declare_war(world, a.id, b.id, &"territory")
	var b_cells := b.cell_count
	var max_progress := 0.0
	var moved := false
	var start_region := -1
	for d in 360 * 4:
		sim.step_day(world)
		for x in ArmySystem.armies_of_war(world, war.id):
			if x.nation == a.id and x.kind == &"land":
				if start_region < 0:
					start_region = x.region
				elif x.region != start_region:
					moved = true
		max_progress = maxf(max_progress, war.siege_progress)
		if not war.active or war.end_year >= 0:
			break
	print("фронт: армия сдвинулась %s, наибольший прогресс осады %.2f, битв %d, у обороны клеток %d → %d" % [moved, max_progress, war.battles, b_cells, b.cell_count])
	_expect(moved or start_region == war.siege_region, "армия не идёт к цели")
	_expect(max_progress > 0.0 or b.cell_count < b_cells or war.battles > 0, "фронт не движется")
	_check(world, "фронт")


func _hash(world: World) -> String:
	world.update_label_anchors()  # подписи — только отображение (интерфейс обновляет их сам)
	return JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", true, true).sha256_text()


func _save_load() -> void:
	var s := MapSettings.new()
	s.world_seed = 4242
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	var ok := false
	for y in 300:
		sim.step_month(world)
		if world.armies.any(func(a: Army) -> bool: return a.alive and a.state == &"march" and not a.path.is_empty()):
			ok = true
			break
	_expect(ok, "не нашлось армии в походе")
	for d in 7:
		sim.step_day(world)
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded.armies.size() == world.armies.filter(func(a: Army) -> bool: return a.alive).size(), "армии не сохранились")
	ArmySystem.compact(world)
	var sim2 := Simulation.new()
	for d in 360 * 2:
		sim.step_day(world)
		sim2.step_day(loaded)
	_expect(_hash(world) == _hash(loaded), "после загрузки с армиями в походе история разошлась")


func _god_tools() -> void:
	var s := MapSettings.new()
	s.world_seed = 31
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	sim.step(world)
	var n := world.nations[0]
	var cell := world.cities[n.capital_city].cell
	var before := world.armies.size()
	var a := GodTools.create_army(world, cell)
	_expect(a != null and world.armies.size() == before + 1 and a.nation == n.id, "армия не создана")
	_expect(GodTools.destroy_army(world, cell) and not a.alive, "армия не уничтожена")
	var port: City = null
	for c in world.cities:
		if c.alive and c.buildings.has(&"harbor"):
			port = c
			break
	if port != null:
		var f := GodTools.launch_fleet(world, port.cell)
		_expect(f != null and f.kind == &"fleet", "флот не спущен")
	var big: Nation = null
	for x in world.nations:
		if x.alive and x.region_counts.size() >= 3 and (big == null or x.cell_count > big.cell_count):
			big = x
	if big != null:
		var far := -1
		for rid in big.region_counts:
			if world.regions[rid].cells.size() > 0 and rid != world.region_of[world.cities[big.capital_city].cell]:
				far = rid
				break
		var army := ArmySystem.create(world, big, -1, &"land", far)
		var nations := world.nations.size()
		var rebels := GodTools.mutiny(world, army.cell)
		_expect(rebels == null or (world.nations.size() == nations + 1 and not army.alive), "бунт армии не сработал")
	_check(world, "инструменты Бога")


func _performance() -> void:
	var s := MapSettings.new()
	s.world_seed = 5
	s.apply_size_preset(3)
	s.nation_count = 50
	var world := World.create(s)
	var sim := Simulation.new()
	sim.profile = true
	var years := 120
	var t0 := Time.get_ticks_usec()
	for y in years:
		sim.step(world)
	var total := (Time.get_ticks_usec() - t0) / 1000.0 / years
	var armies: float = sim.timings.get("armies", [0, 0])[0] / 1000.0 / years
	var worst: float = sim.timings.get("armies", [0, 0])[1] / 1000.0
	var wars := world.diplomacy.past_wars.size() + world.diplomacy.wars.size()
	print("огромная карта, 50 государств: %.1f мс/год (армии %.2f мс/год, худший ход %.1f мс), войн %d, армий сейчас %d" % [
		total, armies, worst, wars, world.armies.size()])
	_expect(worst < 20.0, "ход армий дольше бюджета кадра")
	_expect(total / 12.0 < 6.0, "месяц симуляции дольше 6 мс")
	_check(world, "огромная карта")


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
