class_name EventSystem
extends RefCounted
## Случайные события из data/events: чума, голод, чудовища, драконы, герои,
## землетрясения, наводнения, Золотой век, вулканы. Эпидемии перекидываются
## на соседей на следующий год.



func tick(world: World, nation: Nation) -> void:
	_expire_modifiers(world, nation)
	# Один бросок на сумму шансов: событие в год редко больше одного, так дешевле,
	# чем бросать кость за каждое событие (их шанс от этого почти не меняется).
	var total := 0.0
	for e in EconomyDB.events():
		total += e.chance * CrisisSystem.event_mult(world, e.id)
	var roll := world.rng.randf()
	if roll >= total:
		return
	for e in EconomyDB.events():
		roll -= e.chance * CrisisSystem.event_mult(world, e.id)
		if roll < 0.0:
			apply(world, nation, e)
			return


## Эпидемии с прошлого года — до обхода государств.
func flush_pending(world: World) -> void:
	var pending := world.pending_events
	world.pending_events = []
	for item in pending:
		var nation := world.nations[item[0]]
		if nation.alive:
			apply(world, nation, EconomyDB.get_event(item[1]))


func apply(world: World, nation: Nation, e: EventDef) -> bool:
	if e == null or nation.population < e.min_population:
		return false
	for t in e.immune_traits:
		if nation.race.has_trait(t):
			return false
	if nation.modifiers.any(func(m: Dictionary) -> bool: return m.id == e.id):
		return false  # уже действует
	var region := _pick_region(world, nation, e)
	if region == null:
		return false
	var rng := world.rng
	var city := _region_city(world, region, nation.id)

	if e.stage_months > 0:
		# Растянутый удар: StageSystem применяет его помесячно по кривой.
		StageSystem.push(world, nation, e.stage_months, e.population_loss, e.army_loss, e.stability_change, e.gold_loss, e.food_loss, e.id)
	else:
		StageSystem.hit(world, nation, e.population_loss, e.army_loss, e.stability_change, e.gold_loss, e.food_loss)
	if e.causes_famine:
		nation.famine_years = maxi(nation.famine_years, 1)
	if e.destroys_buildings > 0 and city != null:
		for k in mini(e.destroys_buildings, city.buildings.size()):
			city.buildings.remove_at(rng.randi_range(0, city.buildings.size() - 1))
		CitySystem.recompute_building_effects(world, nation)
	var city_name := city.name if city != null else region.name
	if e.destroys_city_chance > 0.0 and city != null and not city.is_capital and rng.randf() < e.destroys_city_chance:
		world.destroy_city(city)
		city_name += " (город разрушен)"
	if e.lost_cells > 0:
		_devastate(world, nation, region, e.lost_cells)
	if e.gold_gain > 0.0:
		nation.stock[Goods.GOLD] += nation.population / 1000.0 * e.gold_gain
	if e.food_gain > 0.0:
		nation.stock[Goods.FOOD] += nation.population / 1000.0 * nation.race.food_need * e.food_gain
	match e.special:
		&"migration":
			if not _migration(world, nation, region):
				return false
		&"undead_rising":
			if not _undead_rising(world, nation, region):
				return false
		&"meteor":
			_meteor(world, region)
	if e.spawns_hero:
		# Запись в летопись делает сам HeroSystem.spawn.
		return HeroSystem.spawn(world, nation, region) != null
	if e.duration > 0:
		nation.modifiers.append({
			"id": e.id, "until": world.year + e.duration,
			"army_mult": e.army_mult, "growth_mult": e.growth_mult, "science_mult": e.science_mult,
		})
	# Чума — частный случай болезни: идёт по дорогам «Чёрным мором» (DiseaseSystem).
	if e.id == &"plague":
		DiseaseSystem.start(world, DiseaseDB.find(DiseaseSystem.PLAGUE), region.id)
	if e.spread_chance > 0.0:
		for other in nation.borders:
			if rng.randf() < e.spread_chance:
				world.pending_events.append([other, e.id])

	var hero := NameGenerator.person_name(nation.race, rng) if e.text.contains("{hero}") else ""
	var text := e.text.format({
		"nation": nation.name, "region": region.name, "city": city_name,
		"hero": hero, "ruler": nation.ruler_display(), "name": e.display_name,
	})
	world.log_event(e.chronicle_kind, text, PackedInt32Array([nation.id]))
	return true


## Переселенцы другого народа занимают часть клеток региона — государство становится многорасовым.
func _migration(world: World, nation: Nation, region: Region) -> bool:
	var rng := world.rng
	var candidates: Array[RaceDef] = []
	for r in RaceDB.all():
		if r != nation.race and r.spawn_at_start and nation.race.relation_to(r) > -0.4:
			candidates.append(r)
	if candidates.is_empty():
		return false
	var race := candidates[rng.randi_range(0, candidates.size() - 1)]
	var moved := 0
	for c in region.cells:
		if moved >= 12:
			break
		if world.owner[c] != nation.id or world.cell_race[c] == race.index:
			continue
		world.set_owner(c, -1)
		world.cell_race[c] = race.index
		world.set_owner(c, nation.id)
		nation.pop[race.index] += world.cell_cap[c] * 0.6
		moved += 1
	if moved == 0:
		return false
	world.log_event(&"nation", "%s переселились в регион %s государства %s." % [race.display_name, region.name, nation.short_name],
			PackedInt32Array([nation.id]))
	return true


## Мёртвые встают из могил: регион откалывается как государство нежити и воюет с прежним владельцем.
func _undead_rising(world: World, nation: Nation, region: Region) -> bool:
	var undead := RaceDB.get_race(&"undead")
	if undead == null or nation.race == undead or region.controller() != nation.id:
		return false
	var rebel := world.split_off(nation, PackedInt32Array([region.id]), undead)
	if not rebel.alive:
		return false
	rebel.army = maxf(rebel.army, 4000.0)
	world.diplomacy.declare_war(world, rebel.id, nation.id, &"independence")
	world.log_event(&"rebellion", "Мертвецы региона %s провозгласили %s." % [region.name, rebel.name], PackedInt32Array([nation.id, rebel.id]))
	return true


## Падение звезды: кратер-озеро в центре региона; иногда звезда оставляет источник силы.
func _meteor(world: World, region: Region) -> void:
	GodTools.reshape(world, region.center, 1, -1.5)
	if world.rng.randf() < 0.3:
		var cell := -1
		for c in region.cells:
			if world.map.is_land(c):
				cell = c
				break
		if cell >= 0:
			HeroSystem.power_source(world, null, cell)


func _pick_region(world: World, nation: Nation, e: EventDef) -> Region:
	var keys := nation.region_counts.keys()
	if keys.is_empty():
		return null
	for attempt in 6:
		var region := world.regions[keys[world.rng.randi_range(0, keys.size() - 1)]]
		if not e.requires_biomes.is_empty():
			var biome_id := BiomeDB.get_def(world.map.biome[region.center]).id
			if not e.requires_biomes.has(biome_id):
				continue
		if e.requires_river and not _has_river(world, region):
			continue
		return region
	return null


func _has_river(world: World, region: Region) -> bool:
	for c in region.cells:
		if world.map.river[c] > 0:
			return true
	return false


func _region_city(world: World, region: Region, owner_id: int) -> City:
	var best: City = null
	for c in region.cells:
		var id := world.city_cell[c]
		if id >= 0 and world.cities[id].nation_id == owner_id:
			if best == null or world.cities[id].population > best.population:
				best = world.cities[id]
	return best


## Опустошение: пограничные клетки региона становятся ничьими (города не трогаем).
func _devastate(world: World, nation: Nation, region: Region, count: int) -> void:
	var lost := 0
	for c in region.cells:
		if lost >= count:
			break
		if world.owner[c] != nation.id or world.city_cell[c] >= 0:
			continue
		for nb in world.map.neighbors4(c):
			if world.owner[nb] != nation.id:
				world.set_owner(c, -1)
				lost += 1
				break


func _expire_modifiers(world: World, nation: Nation) -> void:
	for i in range(nation.modifiers.size() - 1, -1, -1):
		if nation.modifiers[i].until <= world.year:
			nation.modifiers.remove_at(i)
