extends SceneTree
## Headless-проверка этапа 11.C (дикий мир):
##   • данные data/tribes, data/lairs, data/diseases корректны (народы, биомы);
##   • долгие прогоны: племена рождаются, кочуют, собираются в орды, вливаются
##     в государства или основывают свои; логова набегают и их разоряют;
##     поветрия идут по краям и кончаются, оставляя иммунитет; наречия рождаются;
##   • инварианты: ссылки на края и языки верны, болезнь не в «иммунном» крае;
##   • чума — частный случай: событие «Чума» начинает «Чёрный мор»;
##   • болезнь идёт по дорогам; инструменты Бога; режим «Опасности»;
##   • сохранение → загрузка посреди поветрия: одинаковое продолжение;
##   • производительность новых систем на огромной карте.
##   godot --headless --path . -s res://tests/wild_test.gd -- [годы]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 300
	_data()
	_long_run(years)
	_plague()
	_roads_and_immunity()
	_god_tools()
	_save_load()
	_performance()
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _data() -> void:
	var biomes := {}
	for b in BiomeDB.all():
		biomes[b.id] = true
	_expect(TribeDB.all().size() >= 6 and LairDB.all().size() >= 6 and DiseaseDB.all().size() >= 5, "мало данных дикого мира")
	for d in TribeDB.all():
		var t: TribeDef = d
		_expect(RaceDB.get_race(t.race) != null, "племя %s: нет народа %s" % [t.id, t.race])
		_expect(t.biomes.all(func(b: StringName) -> bool: return biomes.has(b)), "племя %s: неизвестный биом" % t.id)
		_expect(t.tribe_name.contains("{name}") and t.horde_name.contains("{name}"), "племя %s: имя без {name}" % t.id)
	var great := 0
	for d in LairDB.all():
		var l: LairDef = d
		_expect(not l.biomes.is_empty() and l.biomes.all(func(b: StringName) -> bool: return biomes.has(b)), "логово %s: биомы" % l.id)
		_expect(l.strength.x > 0.0 and l.strength.y >= l.strength.x, "логово %s: сила" % l.id)
		if l.great:
			great += 1
	_expect(great >= 2, "мало великих чудовищ")
	var plague := 0
	for d in DiseaseDB.all():
		var x: DiseaseDef = d
		_expect(x.months > 0 and x.lethality > 0.0 and x.lethality < 0.5, "болезнь %s: параметры" % x.id)
		for r in x.immune_races:
			_expect(RaceDB.get_race(r) != null, "болезнь %s: нет народа %s" % [x.id, r])
		if x.plague:
			plague += 1
	_expect(plague == 1 and DiseaseDB.find(DiseaseSystem.PLAGUE) != null, "нет чумы среди болезней")


func _check(world: World, where: String) -> void:
	for t in world.tribes:
		if t.alive:
			_expect(t.region >= 0 and t.region < world.regions.size() and t.def != null and t.strength > 0.0, "%s: племя неверно" % where)
	for l in world.lairs:
		if l.alive:
			_expect(l.home >= 0 and l.region >= 0 and l.home < world.regions.size() and l.region < world.regions.size(), "%s: логово вне карты" % where)
			_expect(world.region_of[l.cell] == l.home, "%s: логово не в своём крае" % where)
	var seen := {}
	for o in world.outbreaks:
		if not o.alive:
			continue
		_expect(o.regions.size() <= DiseaseSystem.MAX_REGIONS + 8, "%s: поветрие без предела" % where)
		for rid in o.regions:
			_expect(not seen.has(rid), "%s: два поветрия в одном крае" % where)
			seen[rid] = true
			_expect(int(o.regions[rid]) > 0 and int(o.regions[rid]) <= o.def.months, "%s: срок болезни" % where)
	for r in world.regions:
		_expect(r.language >= -1 and r.language < world.languages.size(), "%s: язык края" % where)
	for n in world.nations:
		if n.alive and n.language >= 0:
			_expect(n.language < world.languages.size(), "%s: язык государства" % where)
	var danger := LairSystem.danger_map(world)
	_expect(danger.size() == world.regions.size(), "%s: карта опасностей" % where)
	for d in danger:
		if d < 0.0 or d > 1.0:
			_expect(false, "%s: опасность вне 0..1" % where)
			break


func _long_run(years: int) -> void:
	var totals := {}
	for cfg in [[2024, 1], [101, 0], [77777, 2]]:
		var s := MapSettings.new()
		s.world_seed = cfg[0]
		s.apply_size_preset(cfg[1])
		var world := World.create(s)
		_expect(not world.tribes.is_empty() and not world.lairs.is_empty() and not world.languages.is_empty(), "мир без дикого края")
		var sim := Simulation.new()
		var max_outbreaks := 0
		for y in years:
			sim.step(world)
			max_outbreaks = maxi(max_outbreaks, DiseaseSystem.alive_outbreaks(world).size())
			if y % 50 == 49:
				_check(world, "seed %d, год %d" % [cfg[0], world.year])
		for k in [&"tribes", &"hordes", &"tribes_absorbed", &"tribe_states", &"tribe_raids", &"lairs", &"lair_raids", &"lairs_cleared",
				&"outbreaks", &"outbreaks_over", &"dialects", &"language_shifts"]:
			totals[k] = totals.get(k, 0) + world.counters.get(k, 0)
		print("seed %d: племён %d (живы %d), орд %d, вобрано %d, держав из орд %d; логов %d, разорено %d; поветрий %d; языков %d (наречий %d)" % [
			cfg[0], world.counters.get(&"tribes", 0), TribeSystem.alive_tribes(world).size(), world.counters.get(&"hordes", 0),
			world.counters.get(&"tribes_absorbed", 0), world.counters.get(&"tribe_states", 0), world.counters.get(&"lairs", 0),
			world.counters.get(&"lairs_cleared", 0), world.counters.get(&"outbreaks", 0),
			world.languages.filter(func(l: Language) -> bool: return l.alive).size(), world.counters.get(&"dialects", 0)])
		_expect(max_outbreaks <= DiseaseSystem.MAX_OUTBREAKS + 1, "слишком много поветрий сразу")
	_expect(totals[&"hordes"] > 0, "кочевники ни разу не собрались в орду")
	_expect(totals[&"tribes_absorbed"] + totals[&"tribe_states"] > 0, "племена не вливаются в государства и не основывают своих")
	_expect(totals[&"tribe_raids"] > 0 and totals[&"lair_raids"] > 0, "нет набегов")
	_expect(totals[&"lairs_cleared"] > 0, "логова никто не разоряет")
	_expect(totals[&"outbreaks"] > 0 and totals[&"outbreaks_over"] > 0, "поветрия не случаются или не кончаются")
	_expect(totals[&"dialects"] > 0, "наречия не рождаются")


## Событие «Чума» начинает «Чёрный мор», а тот приносит чуму соседям по дорогам.
func _plague() -> void:
	var s := MapSettings.new()
	s.world_seed = 31
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 30:
		sim.step(world)
	var big: Nation = null
	for n in world.nations:
		if n.alive and not n.race.has_trait(&"no_food") and (big == null or n.population > big.population):
			big = n
	var plague: EventDef = null
	for e in EconomyDB.events():
		if e.id == &"plague":
			plague = e
	var ok := GodTools.trigger_event(world, sim, plague, world.cities[big.capital_city].cell)
	_expect(ok, "событие чумы не случилось")
	var o: Outbreak = null
	for x in world.outbreaks:
		if x.alive and x.def.plague:
			o = x
	_expect(o != null, "чума не начала «Чёрный мор»")
	if o == null:
		return
	for m in 12:
		sim.step_month(world)
	_expect(o.peak >= 2 or o.nations.size() >= 2 or not world.pending_events.is_empty(), "чума не идёт дальше")


## Болезнь идёт по дорогам; переболевший край не принимает её снова.
func _roads_and_immunity() -> void:
	var s := MapSettings.new()
	s.world_seed = 4242
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 60:
		sim.step(world)
	# Город с наибольшим числом дорог.
	var hub := -1
	var best := 0
	for cid in world.city_roads:
		var k: int = world.city_roads[cid].size()
		if world.cities[cid].alive and k > best:
			best = k
			hub = cid
	_expect(hub >= 0, "нет дорог")
	if hub < 0:
		return
	var origin := world.region_of[world.cities[hub].cell]
	var road_regions := {}
	for rid in world.city_roads[hub]:
		var road := world.roads[rid]
		if road.alive:
			road_regions[world.region_of[world.cities[road.other(hub)].cell]] = true
	var pox := DiseaseDB.find(&"pox")
	world.regions[origin].immune.erase(pox.id)
	var o := DiseaseSystem.start(world, pox, origin)
	_expect(o != null, "поветрие не началось")
	if o == null:
		return
	var reached := false
	for m in pox.months:
		sim.step_month(world)
		for rid in o.regions:
			if road_regions.has(rid):
				reached = true
	_expect(reached, "болезнь не пошла по дорогам")
	for m in pox.months * 3:
		sim.step_month(world)
	_expect(world.regions[origin].immune.get(pox.id, -1) > world.year, "переболевший край без иммунитета")
	_expect(not DiseaseSystem.can_infect(world, pox, world.regions[origin]), "иммунный край снова болеет")


func _god_tools() -> void:
	var s := MapSettings.new()
	s.world_seed = 7
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	sim.step(world)
	var wild := -1
	for r in world.regions:
		if r.owner_counts.is_empty() and r.cells.size() >= 4 and TribeSystem.tribe_in(world, r.id) == null:
			wild = r.center
			break
	if wild >= 0:
		var t := GodTools.spawn_tribe(world, wild)
		_expect(t != null and t.region == world.region_of[wild], "племя не создано")
	var n := world.nations[0]
	var cap := world.cities[n.capital_city].cell
	_expect(GodTools.spawn_tribe(world, cap) == null, "племя в чужом государстве")
	var l := GodTools.spawn_lair(world, cap, true)
	_expect(l != null and l.def.great and not l.name.is_empty(), "великое чудовище не пробудилось")
	var o := GodTools.start_disease(world, cap, DiseaseDB.find(&"pox"))
	_expect(o != null and o.regions.has(world.region_of[cap]), "поветрие не началось")
	var before := world.languages.size()
	var lang := GodTools.split_dialect(world, cap)
	_expect(lang == before and world.regions[world.region_of[cap]].language == lang and world.languages[lang].dialect, "наречие не родилось")
	for y in 3:
		sim.step(world)
	_check(world, "инструменты Бога")


func _hash(world: World) -> String:
	world.update_label_anchors()
	return JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", true, true).sha256_text()


func _save_load() -> void:
	var s := MapSettings.new()
	s.world_seed = 2024
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 40:
		sim.step(world)
	DiseaseSystem.start(world, DiseaseDB.find(&"red_cough"), world.region_of[world.cities[world.nations[0].capital_city].cell])
	for d in 47:
		sim.step_day(world)
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded.tribes.size() == TribeSystem.alive_tribes(world).size() and loaded.lairs.size() == LairSystem.alive_lairs(world).size()
		and loaded.outbreaks.size() == DiseaseSystem.alive_outbreaks(world).size() and loaded.languages.size() == world.languages.size(),
		"дикий мир не сохранился")
	ArmySystem.compact(world)
	var sim2 := Simulation.new()
	for d in 360 * 2:
		sim.step_day(world)
		sim2.step_day(loaded)
	_expect(_hash(world) == _hash(loaded), "после загрузки посреди поветрия история разошлась")


func _performance() -> void:
	var s := MapSettings.new()
	s.world_seed = 5
	s.apply_size_preset(3)
	s.nation_count = 40
	var world := World.create(s)
	var sim := Simulation.new()
	sim.profile = true
	var years := 100
	for y in years:
		sim.step(world)
	var line := "огромная карта, %d лет:" % years
	for k in ["tribes", "lairs", "diseases", "languages"]:
		var e: Array = sim.timings.get(k, [0, 0])
		var per_month: float = e[0] / 1000.0 / years / 12.0
		line += " %s %.3f мс/мес. (худший %.1f мс);" % [k, per_month, e[1] / 1000.0]
		# Этап 12.B: племена и чудовища ходят по карте каждые сутки — бюджет выше (всё равно ≪ кадра).
		var limit := 1.5 if k == "tribes" or k == "lairs" else 0.4
		_expect(per_month < limit, "%s дольше %.1f мс в месяц" % [k, limit])
		_expect(e[1] / 1000.0 < 10.0, "%s: худший вызов дольше 10 мс" % k)
	print(line)
	_check(world, "огромная карта")


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
