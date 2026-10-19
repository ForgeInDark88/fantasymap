class_name UnrestSystem
extends RefCounted
## Лояльность регионов, восстания, гражданские войны и распад государств.
##
## Лояльность региона владельцу падает, если там живёт другой народ (сильнее —
## если расы враждуют), если регион далеко от столицы, недавно завоёван или
## государство в целом нестабильно. Нелояльный регион копит недовольство;
## когда оно переполняется — бунт:
##   • чужой народ отделяется и провозглашает своё государство (освободительная война);
##   • свой народ при слабой власти — гражданская война претендента;
##   • иначе бунт подавляют (ценой армии).
## Если стабильность годами держится у нуля, большое государство распадается.

## Раз в сколько лет пересчитывать лояльность (со сдвигом по id государства).
const PERIOD := 5


func tick(world: World, nation: Nation) -> void:
	if (world.year + nation.id) % PERIOD != 0 or nation.cell_count == 0:
		return
	var regions := _controlled_regions(world, nation)
	var capital_region := -1
	if nation.capital_city >= 0:
		capital_region = world.region_of[world.cities[nation.capital_city].cell]
	var cap_pos := world.map.cell_pos(world.cities[nation.capital_city].cell) if nation.capital_city >= 0 else Vector2i(nation.centroid())
	var rebels: Region = null
	for rid in regions:
		var region := world.regions[rid]
		region.loyalty = _loyalty(world, nation, region, rid == capital_region, cap_pos)
		if region.pacified_until > world.year:
			region.unrest = 0.0
			continue
		if region.loyalty < 0.35:
			region.unrest += (0.35 - region.loyalty) * PERIOD * 0.15
		else:
			region.unrest *= 0.6
		if region.unrest >= 1.0 and rid != capital_region and (rebels == null or region.unrest > rebels.unrest):
			rebels = region
	if rebels != null and world.rng.randf() < 0.35:
		_revolt(world, nation, rebels, capital_region)
		return
	_check_collapse(world, nation, regions, capital_region)


func _controlled_regions(world: World, nation: Nation) -> PackedInt32Array:
	var result := PackedInt32Array()
	for rid in nation.region_counts:
		if world.regions[rid].controller() == nation.id:
			result.append(rid)
	return result


func _loyalty(world: World, nation: Nation, region: Region, is_capital: bool, cap_pos: Vector2i) -> float:
	var loyalty := 0.35 + nation.stability * 0.55
	if is_capital:
		loyalty += 0.3
	var people := world.region_majority_race(region, nation.id)
	if people != World.NO_RACE and people != nation.race.index:
		var relation := nation.race.relation_to(RaceDB.by_index(people))
		loyalty -= 0.3 - relation * 0.2
	var dist := Vector2(world.map.cell_pos(region.center) - cap_pos).length()
	loyalty -= minf(0.25, dist / (world.map.width * 0.3) * 0.15)
	var since := world.year - region.conquered_year
	if since < 40:
		loyalty -= 0.25 * (1.0 - since / 40.0)
	if nation.overlord >= 0:
		loyalty -= 0.05
	return clampf(loyalty, 0.0, 1.0)


func _revolt(world: World, nation: Nation, region: Region, capital_region: int) -> void:
	var people := world.region_majority_race(region, nation.id)
	var foreign := people != World.NO_RACE and people != nation.race.index
	if not foreign and nation.stability >= 0.35:
		_suppress(world, nation, region)
		return
	# К мятежу примыкают соседние недовольные регионы того же народа.
	var group := PackedInt32Array([region.id])
	var queue := [region.id]
	while not queue.is_empty() and group.size() < 6:
		var rid: int = queue.pop_front()
		for nb in world.regions[rid].neighbors:
			var other := world.regions[nb]
			if group.has(nb) or nb == capital_region or other.controller() != nation.id or other.unrest < 0.4:
				continue
			if world.region_majority_race(other, nation.id) != people:
				continue
			group.append(nb)
			queue.append(nb)
	# Безнадёжный бунт (горстка против сильной державы) давят в зародыше.
	var rebel_pop := 0.0
	for rid in group:
		rebel_pop += world.region_population(world.regions[rid], nation.id)
	if rebel_pop < nation.population * 0.04 and nation.stability >= 0.25:
		_suppress(world, nation, region)
		return
	var race := RaceDB.by_index(people) if foreign else nation.race
	var rebel := world.split_off(nation, group, race)
	if not rebel.alive:
		return
	var ids := PackedInt32Array([nation.id, rebel.id])
	if foreign:
		world.log_event(&"rebellion", "Восстание: %s региона %s сбрасывают власть государства %s и провозглашают %s." % [
			race.display_name, region.name, nation.short_name, rebel.name], ids)
	else:
		world.log_event(&"rebellion", "Гражданская война в государстве %s: %s провозглашает %s в регионе %s." % [
			nation.short_name, rebel.ruler_display(), rebel.name, region.name], ids)
	# Слабое государство отпускает мятежников без боя, иначе — война.
	if nation.stability >= 0.2:
		world.diplomacy.declare_war(world, rebel.id, nation.id, &"independence" if foreign else &"civil")


func _suppress(world: World, nation: Nation, region: Region) -> void:
	region.unrest = 0.0
	region.pacified_until = world.year + world.rng.randi_range(30, 60)
	nation.army *= 0.95
	world.log_event(&"rebellion", "Мятеж в регионе %s (%s) подавлен." % [region.name, nation.short_name],
			PackedInt32Array([nation.id]))


## Годы на дне стабильности → распад на несколько государств вокруг крупных городов.
func _check_collapse(world: World, nation: Nation, regions: PackedInt32Array, capital_region: int) -> void:
	if nation.stability >= 0.15 or regions.size() < 6:
		nation.collapse_years = 0
		return
	nation.collapse_years += PERIOD
	if nation.collapse_years < 10 or world.rng.randf() > 0.4:
		return
	# Центры обломков — крупнейшие города вне столичного региона.
	var seeds: Array[int] = []
	var cities := []
	for id in nation.city_ids:
		cities.append(world.cities[id])
	cities.sort_custom(func(a: City, b: City) -> bool: return a.population > b.population)
	var parts := clampi(regions.size() / 5, 2, 4)
	for city in cities:
		var rid := world.region_of[city.cell]
		if rid != capital_region and not seeds.has(rid) and regions.has(rid):
			seeds.append(rid)
			if seeds.size() >= parts - 1:
				break
	if seeds.is_empty():
		return
	# Регионы делятся между столицей и центрами обломков «волной» по соседству.
	var assign := {}
	var queue := []
	if capital_region >= 0:
		assign[capital_region] = -1
		queue.append(capital_region)
	for k in seeds.size():
		assign[seeds[k]] = k
		queue.append(seeds[k])
	while not queue.is_empty():
		var rid: int = queue.pop_front()
		for nb in world.regions[rid].neighbors:
			if regions.has(nb) and not assign.has(nb):
				assign[nb] = assign[rid]
				queue.append(nb)
	var names: Array[String] = []
	for k in seeds.size():
		var group := PackedInt32Array()
		for rid in assign:
			if assign[rid] == k:
				group.append(rid)
		var people := world.region_majority_race(world.regions[seeds[k]], nation.id)
		var race := RaceDB.by_index(people) if people != World.NO_RACE else nation.race
		var part := world.split_off(nation, group, race)
		if part.alive:
			names.append(part.name)
	nation.collapse_years = 0
	nation.stability = 0.5
	if not names.is_empty():
		world.log_event(&"collapse", "Распад государства %s: от него откололись %s." % [nation.name, ", ".join(names)],
				PackedInt32Array([nation.id]))
