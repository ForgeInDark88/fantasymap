class_name GodTools
## Вмешательства игрока («панель Бога»). Чистые функции над World —
## интерфейс только выбирает инструмент и клетку.

## Создать государство расы race в регионе клетки. Ничья земля региона
## заселяется; если регион чей-то — он отделяется в новое государство.
static func create_nation(world: World, race: RaceDef, cell: int, announce: bool = true) -> Nation:
	var region := world.region_at(cell)
	if region == null:
		return null
	var owner := world.owner[cell]
	var nation: Nation
	if owner >= 0:
		nation = world.split_off(world.nations[owner], PackedInt32Array([region.id]), race)
		if not nation.alive:
			return null
	else:
		nation = world.found_nation(race)
		for c in region.cells:
			if world.owner[c] == -1:
				world.set_owner(c, nation.id)
		if nation.cell_count == 0:
			nation.alive = false
			return null
		nation.pop[race.index] = nation.capacity[race.index] * 0.4
		nation.stock[Goods.WOOD] = 40.0
		nation.stock[Goods.STONE] = 20.0
		nation.stock[Goods.GOLD] = 80.0
		nation.stock[Goods.FOOD] = nation.population / 1000.0
		nation.army = nation.population * 0.03 * race.military
		nation.stability = 0.8
	if nation.capital_city < 0:
		var site := cell if world.owner[cell] == nation.id and world.can_place_city(cell) else region.center
		if world.owner[site] == nation.id and world.city_cell[site] < 0:
			var city := world.add_city(nation, site, race, true)
			city.population = maxf(800.0, nation.population * 0.08)
	if announce:
		world.log_event(&"nation", "По воле богов в регионе %s возникло государство %s (%s)." % [
			region.name, nation.name, race.display_name], PackedInt32Array([nation.id]))
	return nation


static func trigger_event(world: World, simulation: Simulation, event: EventDef, cell: int) -> bool:
	var nation := world.nation_at(cell)
	if nation == null or event == null:
		return false
	# Боги не ждут удачного случая: событие происходит без условий о населении.
	var saved_min := event.min_population
	event.min_population = 0.0
	var ok := simulation.events.apply(world, nation, event)
	event.min_population = saved_min
	return ok


static func declare_war(world: World, attacker: int, target: int) -> War:
	if attacker < 0 or target < 0 or attacker == target:
		return null
	var d := world.diplomacy
	if d.war_between(attacker, target) != null:
		return null
	d.pair(attacker, target).truce_until = -1
	var war := d.declare_war(world, attacker, target, &"divine")
	world.log_event(&"war", "По воле богов %s объявляет войну государству %s." % [
		world.nations[attacker].name, world.nations[target].name], PackedInt32Array([attacker, target]))
	return war


static func spawn_hero(world: World, cell: int) -> Hero:
	var nation := world.nation_at(cell)
	var region := world.region_at(cell)
	if nation == null or region == null:
		return null
	return HeroSystem.spawn(world, nation, region, true)


## Поднять мятеж в регионе клетки: народ региона провозглашает своё государство.
static func incite_rebellion(world: World, cell: int) -> Nation:
	var region := world.region_at(cell)
	var owner := world.owner[cell]
	if region == null or owner < 0:
		return null
	var old := world.nations[owner]
	var people := world.region_majority_race(region, owner)
	var race := RaceDB.by_index(people) if people != World.NO_RACE else old.race
	var rebel := world.split_off(old, PackedInt32Array([region.id]), race)
	if not rebel.alive:
		return null
	world.log_event(&"rebellion", "По наущению богов регион %s восстаёт против %s: провозглашено %s." % [
		region.name, old.short_name, rebel.name], PackedInt32Array([old.id, rebel.id]))
	world.diplomacy.declare_war(world, rebel.id, old.id, &"independence")
	return rebel


## Поднять (delta > 0) или опустить (delta < 0) землю кистью радиуса radius.
## Возвращает true, если что-то изменилось (рендеру нужно перерисовать карту).
static func reshape(world: World, cell: int, radius: int, delta: float) -> bool:
	var map := world.map
	var center := map.cell_pos(cell)
	var changed := false
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := center.x + dx
			var y := center.y + dy
			if not map.in_bounds(x, y):
				continue
			var d := sqrt(float(dx * dx + dy * dy))
			if d > radius + 0.5:
				continue
			var i := map.index_of(x, y)
			var amount := delta * (1.0 - d / (radius + 1.0))
			# Вода «поднимается» быстрее, чтобы остров вырос за несколько кликов.
			if map.elevation[i] < 0.0 and delta > 0.0:
				amount *= 2.5
			if set_elevation(world, i, map.elevation[i] + amount):
				changed = true
	if changed:
		world.ownership_version += 1
		world.terrain_version += 1
	return changed


## Меняет высоту клетки и всё, что от неё зависит: биом, воду/сушу, регион,
## добычу, владельца (ушедшая под воду земля теряет хозяина и город).
static func set_elevation(world: World, i: int, e: float) -> bool:
	var map := world.map
	e = clampf(e, -1.0, 1.0)
	var was_land := map.is_land(i)
	var will_land := e >= 0.0
	if is_equal_approx(e, map.elevation[i]):
		return false
	var owner := world.owner[i]
	if owner >= 0:
		world.set_owner(i, -1)
	map.elevation[i] = e
	if will_land:
		map.biome[i] = MapGenerator.classify_land(e, map.temperature[i], map.moisture[i])
		if not was_land:
			map.river[i] = 0
			_attach_to_region(world, i)
			world.owner_texels[i * 4 + 2] = 255
	else:
		map.biome[i] = Biome.SEA
		map.river[i] = 0
		for r in world.ruins:
			if r.cell == i:
				r.cell = -1  # руины ушли под воду
		world.cell_race[i] = World.NO_RACE
		world.deposit[i] = 0
		if was_land:
			_detach_from_region(world, i)
			world.owner_texels[i * 4 + 2] = 0
	world.refresh_cell_yield(i)
	if will_land and owner >= 0:
		world.set_owner(i, owner)
	return true


static func _attach_to_region(world: World, i: int) -> void:
	var rid := -1
	for nb in world.map.neighbors4(i):
		if world.region_of[nb] >= 0:
			rid = world.region_of[nb]
			break
	if rid < 0:
		# Новый остров — новый регион.
		var region := Region.new()
		region.id = world.regions.size()
		region.center = i
		region.coastal = true
		world.regions.append(region)
		rid = region.id
	var cells := world.regions[rid].cells
	cells.insert(cells.bsearch(i), i)  # клетки региона держим упорядоченными
	world.region_of[i] = rid
	var v := rid + 1
	world.region_texels[i * 4] = v & 0xff
	world.region_texels[i * 4 + 1] = (v >> 8) & 0xff


static func _detach_from_region(world: World, i: int) -> void:
	var rid := world.region_of[i]
	if rid >= 0:
		var region := world.regions[rid]
		var idx := region.cells.find(i)
		if idx >= 0:
			region.cells.remove_at(idx)
		if region.center == i and not region.cells.is_empty():
			region.center = region.cells[0]
	world.region_of[i] = -1
	world.region_texels[i * 4] = 0
	world.region_texels[i * 4 + 1] = 0


## Озарение: текущее исследование завершается мгновенно (или открывается доступная технология).
static func insight(world: World, nation: Nation) -> TechDef:
	var t := TechDB.find(nation.researching) if nation.researching != &"" else null
	if t == null:
		for res in TechDB.all():
			if TechSystem.is_available(nation, res as TechDef):
				t = res
				break
	if t == null:
		return null
	TechSystem.unlock(world, nation, t, "")
	world.log_event(&"tech", "Озарение свыше: учёные государства %s постигли %s." % [nation.name, t.display_name.to_lower()],
			PackedInt32Array([nation.id]))
	return t


## Слияние культур: регион клетки перенимает культуру своего владельца.
static func assimilate(world: World, cell: int) -> bool:
	var region := world.region_at(cell)
	var o := world.owner[cell]
	if region == null or o < 0 or world.nations[o].culture < 0 or region.culture == world.nations[o].culture:
		return false
	CultureSystem.assimilate(world, world.nations[o], region)
	return true


## Дорога от ближайшего к клетке города к ближайшему другому городу (даром).
static func road_from(world: World, cell: int) -> Road:
	var pos := Vector2(world.map.cell_pos(cell))
	var from: City = null
	for c in world.cities:
		if c.alive and (from == null or pos.distance_squared_to(Vector2(world.map.cell_pos(c.cell))) < pos.distance_squared_to(Vector2(world.map.cell_pos(from.cell)))):
			from = c
	if from == null:
		return null
	var fp := Vector2(world.map.cell_pos(from.cell))
	var to: City = null
	for c in world.cities:
		if c.alive and c != from and not RoadSystem._connected(world, from.id, c.id) \
				and (to == null or fp.distance_squared_to(Vector2(world.map.cell_pos(c.cell))) < fp.distance_squared_to(Vector2(world.map.cell_pos(to.cell)))):
			to = c
	if to == null:
		return null
	var path := RoadSystem.measure(world, from.cell, to.cell)
	var sea := path.x < 0.0
	var length := fp.distance_to(Vector2(world.map.cell_pos(to.cell))) * 1.2 if sea else path.x
	var road := RoadSystem.build(world, from, to, sea, length, 0 if sea else int(path.y))
	world.log_event(&"trade", "По воле богов %s связала %s и %s." % ["морская тропа" if sea else "дорога", from.name, to.name],
			PackedInt32Array([from.nation_id, to.nation_id]))
	return road


## Извержение ближайшего вулкана (до 15 клеток) или новой горы-вулкана под курсором.
static func eruption(world: World, cell: int) -> bool:
	var pos := Vector2(world.map.cell_pos(cell))
	var best := -1
	for v in world.volcanoes:
		if Vector2(world.map.cell_pos(v)).distance_to(pos) <= 15.0 and (best < 0 or Vector2(world.map.cell_pos(v)).distance_to(pos) < Vector2(world.map.cell_pos(best)).distance_to(pos)):
			best = v
	if best < 0:
		if world.map.biome[cell] != Biome.MOUNTAINS and world.map.biome[cell] != Biome.HILLS:
			return false
		world.volcanoes.append(cell)
		best = cell
	ClimateSystem.erupt(world, best)
	return true


## Засуха в климатическом поясе клетки.
static func drought(world: World, cell: int) -> void:
	var z := world.climate_zone(cell)
	world.zone_events[z] = {"kind": "drought", "until": world.year + 3}
	world.zone_harvest[z] = ClimateSystem.DROUGHT_HARVEST
	world.scars.append({"cell": cell, "radius": 8.0, "kind": "drought", "until": world.year + 3})
	world.log_event(&"climate", "По воле богов %s пришла великая сушь." % ClimateSystem.ZONE_NAMES[z])


## Древние руины по воле Бога: храм забытых богов в клетке.
static func ancient_ruin(world: World, cell: int) -> Ruin:
	var name := "Руины %s" % NameGenerator.place_name(RaceDB.all()[world.rng.randi_range(0, RaceDB.count() - 1)], world.rng)
	var r := RuinSystem.add(world, &"temple", cell, name, "древнее святилище, поднятое из небытия (%d г.)" % world.year)
	if r != null:
		r.wealth *= 2.0
		world.log_event(&"ruins", "Земля разверзлась в регионе %s: открылись древние руины — %s." % [world.region_label(cell, "диких землях"), name])
	return r
