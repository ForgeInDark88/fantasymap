extends SceneTree
## Headless-проверка героев, великих деяний и Судьбы.
##   godot --headless --path . -s res://tests/heroes_test.gd

var _failures := 0


func _initialize() -> void:
	var s := MapSettings.new()
	s.world_seed = 33
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 40:
		sim.step(world)
	var nation: Nation = world.nations.filter(func(n: Nation) -> bool: return n.alive and n.cell_count > 50)[0]
	var region := world.region_at(nation.cells[0])
	var hero := HeroSystem.spawn(world, nation, region, true)
	_expect(hero != null and hero.karma >= -1.0 and hero.karma <= 1.0, "герой не создан")
	hero.level = 12

	# Остров нагов: герой становится правителем нагов.
	var ok := HeroSystem.naga_island(world, hero)
	_expect(ok, "остров нагов не поднят")
	var nagas := world.nations.filter(func(n: Nation) -> bool: return n.alive and n.race_id == &"nagas")
	_expect(nagas.size() == 1 and nagas[0].ruler_name == hero.name and hero.is_ruler, "наги без героя на троне")

	# Источники силы: не больше двух.
	var h2 := HeroSystem.spawn(world, nation, region, true)
	# (за 40 лет герои могли уже открыть источник сами)
	var existing := world.active_landmarks(&"source").size()
	for i in Landmark.MAX_SOURCES - existing:
		_expect(HeroSystem.power_source(world, h2, nation.cells[1 + i]) != null, "источник %d не создан" % (existing + i + 1))
	_expect(HeroSystem.power_source(world, h2, nation.cells[3]) == null, "создан третий источник")
	sim.step(world)
	_expect(nation.sources >= 1 or world.sources_of(nation.id) == 0, "государство не получает силу источника")

	# Портал: демоны воюют с соседями.
	var target: Nation = world.nations.filter(func(n: Nation) -> bool: return n.alive and n != nation and n.cell_count > 50)[0]
	var demons := HeroSystem.open_portal(world, target.cells[target.cells.size() / 2], h2)
	_expect(demons != null and demons.race.has_trait(&"demonic"), "портал не открыт")
	for y in 2:
		sim.step(world)
	_expect(demons.alive == false or not world.diplomacy.wars_of(demons.id).is_empty(), "демоны ни с кем не воюют")

	# Судьба: смерть → очередь; проклятие → трон; второй шанс → жив.
	var h3 := HeroSystem.spawn(world, nation, region, true)
	h3.level = 8
	h3.die(world)
	_expect(world.fate_queue.has(h3.id), "павший герой не попал на суд")
	var throne := Fate.curse(world, h3)
	_expect(throne != null and throne.active and h3.fate == &"cursed" and not world.fate_queue.has(h3.id), "проклятие не сработало")
	var h4 := HeroSystem.spawn(world, nation, region, true)
	h4.die(world)
	_expect(Fate.second_chance(world, h4) and h4.alive, "второй шанс не вернул героя")
	var h5 := HeroSystem.spawn(world, nation, region, true)
	h5.die(world)
	Fate.ignore(world, h5)
	_expect(h5.fate == &"rest" and not h5.alive, "покой не назначен")

	# Ум: умный слабак не полезет на стража, безрассудный — полезет.
	var probe := HeroSystem.spawn(world, nation, region, true)
	probe.level = 5
	probe.intellect = 1.0
	var smart_goes := 0
	for i in 200:
		smart_goes += int(probe.dares(probe.power() * 1.3, world.rng))
	probe.intellect = 0.0
	probe.level = 1
	var fool_goes := 0
	for i in 200:
		fool_goes += int(probe.dares(probe.power() * 1.3, world.rng))
	_expect(smart_goes == 0 and fool_goes > 30, "ум не влияет на решения (умный %d, глупец %d из 200)" % [smart_goes, fool_goes])

	# Сильный герой идёт к трону: забирает оружие, гибнет — или, оценив стража, отступает.
	var h6 := HeroSystem.spawn(world, nation, region, true)
	h6.level = 20
	h6.goal_cell = throne.cell
	for m in 36:
		sim.step_month(world)
		if not throne.active or not h6.alive or h6.goal_cell < 0:
			break
	_expect(not throne.active or not h6.alive or h6.goal_cell < 0, "герой так и не дошёл до трона")
	if not throne.active:
		_expect(not h6.artifact.is_empty(), "трон пуст, но оружие у героя не появилось")
	print("трон: %s, герой %s, оружие «%s»" % ["взят" if not throne.active else "стоит", "жив" if h6.alive else "пал", h6.artifact])

	for y in 30:
		sim.step(world)
	_check(world)
	var kinds := {}
	for e in world.chronicle:
		kinds[e.kind] = kinds.get(e.kind, 0) + 1
	print("летопись: ", kinds)
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _check(world: World) -> void:
	var counted := {}
	for i in world.owner.size():
		var o := world.owner[i]
		if world.map.is_land(i) != (world.region_of[i] >= 0):
			_fail("регион клетки не совпадает с сушей")
			return
		if o >= 0:
			counted[o] = counted.get(o, 0) + 1
	for n in world.nations:
		if counted.get(n.id, 0) != n.cell_count:
			_fail("cell_count у %s" % n.name)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)


func _fail(msg: String) -> void:
	_failures += 1
	printerr("FAIL: ", msg)
