extends SceneTree
## Headless-проверка этапа 2: данные рас, генератор имён, стартовые государства.
##   godot --headless --path . -s res://tests/world_test.gd

var _failures := 0


func _initialize() -> void:
	RaceDB.ensure_loaded()
	_check_race_data()
	_print_names()
	for seed_value in [1, 2, 3, 42]:
		_check_world(seed_value)
	_check_determinism()
	_check_huge()
	_check_race_filter()
	_check_regions(OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "")
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _check_race_data() -> void:
	var races := RaceDB.all()
	if races.size() < 7:
		_fail("ожидалось 7 рас, загружено %d" % races.size())
	for race in races:
		if race.icon == null:
			_fail("у расы %s нет иконки" % race.id)
		for key in race.biome_affinity:
			if BiomeDB.find_by_id(key) == null:
				_fail("раса %s: неизвестный биом %s" % [race.id, key])
		for key in race.relations:
			if RaceDB.get_race(key) == null:
				_fail("раса %s: неизвестная раса в отношениях %s" % [race.id, key])
		for t in race.traits:
			if RaceDB.get_trait(t) == null:
				_fail("раса %s: неизвестная особенность %s" % [race.id, t])
		if race.name_prefixes.is_empty() or race.place_suffixes.is_empty() or race.person_suffixes.is_empty():
			_fail("раса %s: пустой язык" % race.id)


func _print_names() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for race in RaceDB.all():
		var places: Array[String] = []
		var people: Array[String] = []
		for i in 6:
			places.append(NameGenerator.place_name(race, rng))
			people.append(NameGenerator.person_name(race, rng))
		var state := NameGenerator.state_title(race, places[0], rng)
		print("%-10s места: %s | имена: %s | %s, %s" % [race.id, ", ".join(places), ", ".join(people), state[0], state[1]])


func _check_world(seed_value: int) -> void:
	var s := MapSettings.new()
	s.world_seed = seed_value
	var t0 := Time.get_ticks_msec()
	var world := World.create(s)
	var elapsed := Time.get_ticks_msec() - t0
	var per_race := {}
	var aff_sum := 0.0
	for nation in world.nations:
		per_race[nation.race_id] = per_race.get(nation.race_id, 0) + 1
		var cap := world.cities[nation.capital_city]
		if world.owner[cap.cell] != nation.id:
			_fail("seed %d: столица %s не на территории %s" % [seed_value, cap.name, nation.name])
		if not world.map.is_land(cap.cell):
			_fail("seed %d: столица %s в воде" % [seed_value, cap.name])
		if nation.cell_count <= 0:
			_fail("seed %d: у %s нет территории" % [seed_value, nation.name])
		if nation.label_cell < 0 or world.owner[nation.label_cell] != nation.id:
			_fail("seed %d: подпись %s вне территории" % [seed_value, nation.name])
		aff_sum += nation.race.affinity_by_biome[world.map.biome[cap.cell]]
	var counted := 0
	for i in world.owner.size():
		if world.owner[i] >= 0:
			counted += 1
			if not world.map.is_land(i):
				_fail("seed %d: государство владеет водой" % seed_value)
				break
			var v := world.owner_texels[i * 4] + world.owner_texels[i * 4 + 1] * 256 - 1
			if v != world.owner[i]:
				_fail("seed %d: owner_texels рассогласован" % seed_value)
				break
	var total := 0
	for nation in world.nations:
		total += nation.cell_count
	if total != counted:
		_fail("seed %d: cell_count (%d) != реальных клеток (%d)" % [seed_value, total, counted])
	if world.nations.size() != s.nation_count:
		_fail("seed %d: создано %d государств вместо %d" % [seed_value, world.nations.size(), s.nation_count])
	if per_race.size() < mini(7, s.nation_count):
		_fail("seed %d: не все расы получили государство: %s" % [seed_value, per_race])
	print("seed=%d: %d государств, %d городов, %d мс, среднее сродство столиц %.2f, %s"
			% [seed_value, world.nations.size(), world.cities.size(), elapsed, aff_sum / maxf(world.nations.size(), 1), per_race])
	if seed_value == 1:
		for nation in world.nations:
			print("    %s (%s) — %s; столица %s; клеток %d; население %d; армия %d"
					% [nation.name, nation.race.display_name, nation.ruler_display(),
						world.cities[nation.capital_city].name, nation.cell_count, nation.population, nation.army])


func _check_determinism() -> void:
	var s := MapSettings.new()
	s.world_seed = 99
	s.apply_size_preset(0)
	var a := World.create(s)
	var b := World.create(s)
	if a.owner != b.owner or a.nations.size() != b.nations.size() or a.nations[0].name != b.nations[0].name:
		_fail("создание мира недетерминировано")


func _check_huge() -> void:
	var s := MapSettings.new()
	s.world_seed = 5
	s.apply_size_preset(3)
	s.nation_count = 40
	var t0 := Time.get_ticks_msec()
	var world := World.create(s)
	print("огромная карта %dx%d: %d государств за %d мс" % [s.width, s.height, world.nations.size(), Time.get_ticks_msec() - t0])
	if world.nations.size() != 40:
		_fail("на огромной карте создано %d государств вместо 40" % world.nations.size())


func _check_race_filter() -> void:
	var s := MapSettings.new()
	s.world_seed = 11
	s.apply_size_preset(0)
	s.nation_count = 5
	s.enabled_races = [&"dwarves", &"elves"]
	var world := World.create(s)
	for nation in world.nations:
		if not s.enabled_races.has(nation.race_id):
			_fail("фильтр рас: появилась раса %s" % nation.race_id)
	s.nation_count = 0
	if not World.create(s).nations.is_empty():
		_fail("nation_count = 0, а государства созданы")


func _check_regions(out_dir: String) -> void:
	var s := MapSettings.new()
	s.world_seed = 3
	var t0 := Time.get_ticks_msec()
	var world := World.new(MapGenerator.new().generate(s))
	var elapsed := Time.get_ticks_msec() - t0
	var sizes := PackedInt32Array()
	var total := 0
	for region in world.regions:
		sizes.append(region.cells.size())
		total += region.cells.size()
		if world.region_of[region.center] != region.id:
			_fail("центр региона %d вне региона" % region.id)
	sizes.sort()
	for i in world.map.cell_count():
		if world.map.is_land(i) != (world.region_of[i] >= 0):
			_fail("клетка %d: регион не совпадает с сушей" % i)
			break
	print("регионы: %d, клеток %d, медиана %d, мин %d, макс %d; мир без государств за %d мс" % [
		world.regions.size(), total, sizes[sizes.size() / 2], sizes[0], sizes[sizes.size() - 1], elapsed])
	if out_dir != "":
		var img := MapPainter.paint(world.map, MapMode.BIOMES)
		var rng := RandomNumberGenerator.new()
		var colors := PackedColorArray()
		for r in world.regions.size():
			colors.append(Color.from_hsv(rng.randf(), 0.5, 0.9))
		for i in world.map.cell_count():
			var r := world.region_of[i]
			if r >= 0:
				var p := world.map.cell_pos(i)
				img.set_pixelv(p, img.get_pixelv(p).lerp(colors[r], 0.55))
		img.save_png(out_dir.path_join("regions.png"))


func _fail(msg: String) -> void:
	_failures += 1
	printerr("FAIL: ", msg)
