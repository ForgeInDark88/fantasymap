extends SceneTree
## Headless-проверка панели Бога: каждое вмешательство + симуляция после него
## не ломают учёт мира.
##   godot --headless --path . -s res://tests/god_tools_test.gd

var _failures := 0


func _initialize() -> void:
	var s := MapSettings.new()
	s.world_seed = 21
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 60:
		sim.step(world)

	# Создать государство на ничьей земле и в чужом регионе.
	var free_cell := -1
	var owned_cell := -1
	for i in world.map.cell_count():
		if world.map.is_land(i) and world.region_of[i] >= 0:
			if world.owner[i] == -1 and free_cell < 0 and world.regions[world.region_of[i]].cells.size() > 20:
				free_cell = i
			elif world.owner[i] >= 0 and owned_cell < 0 and world.city_cell[i] < 0:
				owned_cell = i
	var created := 0
	for cell in [free_cell, owned_cell]:
		if cell >= 0 and GodTools.create_nation(world, RaceDB.get_race(&"elves"), cell) != null:
			created += 1
	_expect(created >= 1, "create_nation не создал государство")

	# Событие, мятеж, война, герой.
	var some := world.nations.filter(func(n: Nation) -> bool: return n.alive and n.cell_count > 50)
	_expect(some.size() >= 2, "мало государств для проверки")
	var a: Nation = some[0]
	var b: Nation = some[1]
	_expect(GodTools.trigger_event(world, sim, EconomyDB.get_event(&"plague"), a.cells[0]) or a.race.has_trait(&"no_food"),
			"событие не применилось")
	_expect(GodTools.declare_war(world, a.id, b.id) != null, "война не объявлена")
	_expect(GodTools.spawn_hero(world, b.cells[0]) != null, "герой не призван")
	var rebel := GodTools.incite_rebellion(world, b.cells[b.cells.size() / 2])
	_expect(rebel != null, "мятеж не поднят")

	# Поднять и опустить землю (с городом под водой).
	var city_cell := world.cities[a.capital_city].cell if a.capital_city >= 0 else a.cells[0]
	_expect(GodTools.reshape(world, city_cell, 3, -2.0), "земля не опустилась")
	_expect(not world.map.is_land(city_cell), "клетка не ушла под воду")
	var sea := -1
	for i in world.map.cell_count():
		if world.map.biome[i] == Biome.OCEAN:
			sea = i
			break
	_expect(GodTools.reshape(world, sea, 2, 2.0), "земля не поднялась")
	_expect(world.map.is_land(sea) and world.region_of[sea] >= 0, "новая суша без региона")
	_check(world, "после вмешательств")
	for y in 60:
		sim.step(world)
	_check(world, "через 60 лет")

	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _check(world: World, when: String) -> void:
	var counted := {}
	for i in world.owner.size():
		var o := world.owner[i]
		if world.map.is_land(i) != (world.region_of[i] >= 0):
			_fail("%s: регион клетки %d не совпадает с сушей" % [when, i])
			return
		if o < 0:
			continue
		if not world.map.is_land(i):
			_fail("%s: государство владеет водой" % when)
			return
		counted[o] = counted.get(o, 0) + 1
		if world.nations[o].cells[world.cell_slot[i]] != i:
			_fail("%s: cell_slot рассогласован" % when)
			return
	for n in world.nations:
		if counted.get(n.id, 0) != n.cell_count:
			_fail("%s: cell_count у %s" % [when, n.name])
	for c in world.cities:
		if c.alive and (world.city_cell[c.cell] != c.id or world.owner[c.cell] != c.nation_id):
			_fail("%s: город %s рассогласован" % [when, c.name])
			return


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)


func _fail(msg: String) -> void:
	_failures += 1
	printerr("FAIL: ", msg)
