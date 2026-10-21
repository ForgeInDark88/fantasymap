extends SceneTree
## «Дым»-прогон всех систем (этапы 1–11): долгая история на нескольких seed и
## размерах карты без ошибок и без вырождения мира — не все погибли, никто не
## захватил весь мир, нет вечной чумы, население живо; в конце — сохранение
## и загрузка совпадают и мир живёт дальше одинаково.
##   godot --headless --path . -s res://tests/all_systems_smoke.gd -- [годы] [размеры через запятую] [seed через запятую]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 500
	var sizes := Array(args[1].split(",")).map(func(x: String) -> int: return int(x)) if args.size() > 1 else [0, 1, 2]
	var seeds := Array(args[2].split(",")).map(func(x: String) -> int: return int(x)) if args.size() > 2 else [101, 2024, 77777]
	for k in seeds.size():
		var s := MapSettings.new()
		s.world_seed = seeds[k]
		s.apply_size_preset(sizes[k % sizes.size()])
		var t0 := Time.get_ticks_msec()
		var world := World.create(s)
		var sim := Simulation.new()
		var worst := 0
		for y in years:
			var ts := Time.get_ticks_usec()
			sim.step(world)
			worst = maxi(worst, Time.get_ticks_usec() - ts)
			if y % 100 == 99:
				_check_alive(world, "seed %d, год %d" % [seeds[k], world.year])
		var ms := Time.get_ticks_msec() - t0
		print("seed %d (%dx%d): %d лет за %.1f с (год %.1f мс, худший %.0f мс); %s" % [seeds[k], s.width, s.height, years,
			ms / 1000.0, float(ms) / years, worst / 1000.0, _summary(world)])
		_check_roundtrip(world, sim)
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _summary(world: World) -> String:
	var alive := world.nations.filter(func(n: Nation) -> bool: return n.alive)
	var pop := 0.0
	for n in alive:
		pop += n.population
	var battles := 0
	for w in world.diplomacy.past_wars + world.diplomacy.wars:
		battles += w.battles
	return ("государств %d (всего %d), население %s, вер %d, техн. %d, путей %d, руин %d, кризисов %d, эпох %d, героев %d, армий %d, битв %d, полководцев %d" +
		", племён %d, логов %d, поветрий %d, языков %d, караванов дошло %d, займов %d, наёмников %d, послов %d, лазутчиков %d, телепортов %d") % [
		alive.size(), world.nations.size(), "%.1f млн" % (pop / 1e6), ReligionSystem.alive_count(world),
		alive.reduce(func(a: int, n: Nation) -> int: return maxi(a, n.techs.size()), 0),
		world.roads.filter(func(r: Road) -> bool: return r.alive).size(), world.ruins.size(),
		world.crisis_history.size() + (0 if world.crisis.is_empty() else 1), world.eras.size(), world.heroes.size(),
		world.armies.filter(func(a: Army) -> bool: return a.alive).size(), battles, world.generals.size(),
		TribeSystem.alive_tribes(world).size(), LairSystem.alive_lairs(world).size(), world.counters.get(&"outbreaks", 0),
		world.languages.filter(func(l: Language) -> bool: return l.alive).size(), world.counters.get(&"caravans_arrived", 0),
		world.counters.get(&"loans", 0), world.counters.get(&"mercs_hired", 0), world.counters.get(&"envoys", 0),
		world.counters.get(&"spies_sent", 0), world.counters.get(&"teleports", 0)]


## Мир не выродился.
func _check_alive(world: World, where: String) -> void:
	var alive := world.nations.filter(func(n: Nation) -> bool: return n.alive)
	_expect(alive.size() >= 3, "%s: почти все государства погибли (%d)" % [where, alive.size()])
	var owned := 0
	var biggest := 0
	var plague := 0
	var pop := 0.0
	for n in alive:
		owned += n.cell_count
		biggest = maxi(biggest, n.cell_count)
		pop += n.population
		if n.modifiers.any(func(m: Dictionary) -> bool: return m.id == &"plague"):
			plague += 1
	_expect(owned > 0 and biggest < owned * 0.6, "%s: одно государство захватило мир (%d из %d клеток)" % [where, biggest, owned])
	_expect(plague <= alive.size() / 2, "%s: вечная чума (%d из %d держав)" % [where, plague, alive.size()])
	_expect(pop > 10000.0, "%s: население вымерло" % where)
	# Армии: только у живых государств, в существующих регионах; число — по войнам, а не лавиной.
	var armies := 0
	for a in world.armies:
		if not a.alive:
			continue
		# Идущие домой после войны — не в счёт (распустятся дома).
		if a.state != &"home":
			armies += 1
		if a.kind != &"pirates" and (a.nation < 0 or not world.nations[a.nation].alive or a.region < 0 or a.region >= world.regions.size()):
			_expect(false, "%s: армия вне мира (%s)" % [where, a.label(world) if a.nation >= 0 else "?"])
			return
	_expect(armies <= 4 * world.diplomacy.wars.size() + PirateSystem.MAX + 8, "%s: армий слишком много (%d при %d войнах)" % [where, armies, world.diplomacy.wars.size()])
	# Этап 12.B: все юниты — в клетках карты, сухопутные на суше (или на кораблях), флоты на воде.
	for u in MovementTest.units(world):
		var m: Mover = u[1]
		if m.cell < 0 or m.cell >= world.map.cell_count():
			_expect(false, "%s: %s вне карты" % [where, u[2]])
			return
		var prof := MoveDB.profile(m.profile)
		if prof.water_only == world.map.is_land(m.cell) and (prof.water_only or not prof.can_sail):
			_expect(false, "%s: %s в непроходимой клетке" % [where, u[2]])
			return
	for n in alive:
		if n.stability < 0.0 or n.stability > 1.0 or is_nan(n.population) or n.army < 0.0:
			_expect(false, "%s: некорректное состояние %s" % [where, n.name])
			return


## Сохранение → загрузка: совпадает и живёт дальше одинаково.
func _check_roundtrip(world: World, sim: Simulation) -> void:
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded != null and loaded.owner == world.owner, "загрузка не совпала с сохранением")
	if loaded == null:
		return
	var sim2 := Simulation.new()
	for y in 5:
		sim.step(world)
		sim2.step(loaded)
	_expect(loaded.chronicle_total == world.chronicle_total and loaded.owner == world.owner, "после загрузки история разошлась")


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
