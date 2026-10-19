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
