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
	_scripted_roads()
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
