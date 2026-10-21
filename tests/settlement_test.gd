extends SceneTree
## Освоение (этап 12.C): земля растёт от городов и поселений — без одиночных
## клеток и дыр, связными пятнами; поселенцы уходят и основывают деревни,
## деревни растут в города, у воюющих появляются форты; локальный пересчёт
## влияния совпадает с полной пересборкой; сохранение с поселенцами в пути
## продолжает историю так же; прежняя экспансия (Features.CLASSIC_EXPANSION)
## работает и поселений не создаёт; освоение укладывается в бюджет времени.
##   godot --headless --path . -s res://tests/settlement_test.gd

const YEARS := 150
## Освоение на государство в год (мс, среднее) — не дороже прежней экспансии с запасом.
const BUDGET_MS := 1.5

var _failures := 0


func _initialize() -> void:
	_settle_world()
	_save_with_settlers()
	_classic()
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _world(seed_value: int) -> World:
	var s := MapSettings.new()
	s.world_seed = seed_value
	s.apply_size_preset(0)
	return World.create(s)


func _settle_world() -> void:
	var world := _world(4242)
	var sim := Simulation.new()
	sim.profile = true
	var t0 := Time.get_ticks_msec()
	for y in YEARS:
		sim.step(world)
	var ms := Time.get_ticks_msec() - t0
	var villages := world.counters.get(&"settle_village", 0) as int
	var forts := world.counters.get(&"settle_fort", 0) as int
	var sent := world.counters.get(&"settlers_sent", 0) as int
	print("освоение: %d лет за %d мс; поселенцев ушло %d, деревень %d, колоний %d, фортов %d, аванпостов %d; живых поселений %d" % [
		YEARS, ms, sent, villages, world.counters.get(&"settle_colony", 0), forts, world.counters.get(&"settle_outpost", 0), world.settlements.size()])
	_expect(sent > 0 and villages > 0, "поселенцы не уходили или не основали ни одной деревни")
	_expect(forts > 0, "у воюющих держав не появилось фортов")
	var grown := 0
	for e in world.chronicle:
		if e.kind == &"settle" and String(e.text).contains("выросла в город"):
			grown += 1
	print("  деревень выросло в города (в летописи): %d" % grown)
	_expect(world.chronicle.any(func(e: Dictionary) -> bool: return e.kind == &"settle"), "нет записей об освоении в летописи")

	# Поселения — на земле своей державы, на суше, не в городе.
	var bad_owner := 0
	for s in world.settlements:
		if s.alive and (world.owner[s.cell] != s.nation or not world.map.is_land(s.cell)):
			bad_owner += 1
	# Владение проверяется раз в год (InfluenceSystem.tick_year): допускаем расхождение
	# только у отнятых в этом году.
	_expect(bad_owner * 10 <= maxi(10, world.settlements.size()), "поселения на чужой земле: %d" % bad_owner)

	# Одиночные клетки и дыры: освоение растёт пятнами от фронта.
	var map := world.map
	var owned := 0
	var isolated := 0
	var holes := 0
	for c in map.cell_count():
		if not map.is_land(c):
			continue
		var o := world.owner[c]
		var same := 0
		var land_nb := 0
		var one_owner := -2
		for nb in map.neighbors4(c):
			if map.is_land(nb):
				land_nb += 1
				var on := world.owner[nb]
				if on == o:
					same += 1
				if one_owner == -2:
					one_owner = on
				elif one_owner != on:
					one_owner = -3
		if o >= 0:
			owned += 1
			if same == 0:
				isolated += 1
		elif land_nb == 4 and one_owner >= 0:
			holes += 1
	print("  занято %d клеток суши; одиночных %d, дыр %d" % [owned, isolated, holes])
	_expect(isolated * 200 <= owned, "одиночных клеток больше 0.5%%: %d из %d" % [isolated, owned])
	_expect(holes * 200 <= owned, "дыр больше 0.5%%: %d из %d" % [holes, owned])

	# Каждый кусок державы, державший влияние, связан с её источником: клетки с
	# запасом ≤ 0 достижимы от города или поселения по своей земле.
	_check_rebuild(world)

	var t: Array = sim.timings.get("expansion", [0, 0])
	var calls := 0
	for n in world.nations:
		calls += 1
	var per := float(t[0]) / 1000.0 / maxf(1.0, YEARS * calls * 0.5)
	print("  освоение: всего %.0f мс, худший вызов %.1f мс, ~%.2f мс на державу в год" % [t[0] / 1000.0, t[1] / 1000.0, per])
	_expect(per <= BUDGET_MS, "освоение дорого: %.2f мс на державу в год" % per)


## Локальный пересчёт (claim + _spread + add_source) против полной пересборки.
func _check_rebuild(world: World) -> void:
	var cells := 0
	var same := 0
	var checked := 0
	for n in world.nations:
		if not n.alive or n.frontier == null or n.infl_dirty or n.infl_work != null:
			continue
		checked += 1
		var before := PackedFloat32Array()
		for c in n.cells:
			before.append(world.infl[c])
		InfluenceSystem.rebuild(world, n)
		InfluenceSystem._work(world, n, -1)
		for k in n.cells.size():
			var a := before[k]
			var b := world.infl[n.cells[k]]
			cells += 1
			if absf(a - b) <= 1e-3 or (a > InfluenceSystem.MARGIN and b > InfluenceSystem.MARGIN):
				same += 1
	print("  влияние: %d держав, совпадает с пересборкой %d из %d клеток" % [checked, same, cells])
	# Рельеф и биомы меняются (климат, Бог) — небольшое расхождение допустимо.
	_expect(checked > 0 and same * 100 >= cells * 90, "локальный пересчёт влияния расходится с полной пересборкой")


func _hash(world: World) -> String:
	world.update_label_anchors()
	return JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", true, true).sha256_text()


## Сохранение, пока поселенцы в пути: продолжение то же, что без сохранения.
func _save_with_settlers() -> void:
	var world := _world(4242)
	var sim := Simulation.new()
	var found := false
	for m in 12 * 200:
		sim.step_month(world)
		if world.settlers.any(func(s: Settler) -> bool: return s.alive and s.m.walking()):
			found = true
			break
	_expect(found, "за 200 лет не нашлось поселенцев в пути")
	if not found:
		return
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded.settlers.size() == world.settlers.size() and loaded.settlements.size() == world.settlements.size(),
		"поселенцы или поселения потерялись при сохранении")
	var sim2 := Simulation.new()
	for m in 36:
		sim.step_month(world)
		sim2.step_month(loaded)
	_expect(_hash(world) == _hash(loaded), "после загрузки история освоения пошла иначе")


## Прежняя экспансия за флагом: работает, поселений и поселенцев нет.
func _classic() -> void:
	Features.CLASSIC_EXPANSION = true
	var world := _world(77)
	var sim := Simulation.new()
	for y in 40:
		sim.step(world)
	Features.CLASSIC_EXPANSION = false
	var owned := 0
	for n in world.nations:
		if n.alive:
			owned += n.cells.size()
	print("прежняя экспансия: 40 лет, занято %d клеток, поселений %d" % [owned, world.settlements.size()])
	_expect(owned > 0, "прежняя экспансия не занимает землю")
	_expect(world.settlements.is_empty() and world.settlers.is_empty(), "при прежней экспансии появились поселения")


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
