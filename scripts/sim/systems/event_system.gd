class_name EventSystem
extends RefCounted
## Случайные события из data/events: чума, голод, чудовища, драконы, герои,
## землетрясения, наводнения, Золотой век, вулканы. Эпидемии перекидываются
## на соседей на следующий год.

## Отложенные события (эпидемии, пришедшие от соседей): [nation_id, event_id].
var _pending: Array = []


func tick(world: World, nation: Nation) -> void:
	_expire_modifiers(world, nation)
	for e in EconomyDB.events():
		if world.rng.randf() < e.chance:
			apply(world, nation, e)


## Эпидемии с прошлого года — до обхода государств.
func flush_pending(world: World) -> void:
	var pending := _pending
	_pending = []
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

	if e.population_loss > 0.0:
		for r in nation.pop.size():
			nation.pop[r] *= 1.0 - e.population_loss
		for id in nation.city_ids:
			world.cities[id].population *= 1.0 - e.population_loss
	nation.army *= 1.0 - e.army_loss
	nation.stability = clampf(nation.stability + e.stability_change, 0.0, 1.0)
	nation.stock[Goods.GOLD] -= maxf(0.0, nation.stock[Goods.GOLD]) * e.gold_loss
	nation.stock[Goods.FOOD] *= 1.0 - e.food_loss
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
	if e.spawns_hero:
		# Запись в летопись делает сам HeroSystem.spawn.
		return HeroSystem.spawn(world, nation, region) != null
	if e.duration > 0:
		nation.modifiers.append({
			"id": e.id, "until": world.year + e.duration,
			"army_mult": e.army_mult, "growth_mult": e.growth_mult, "science_mult": e.science_mult,
		})
	if e.spread_chance > 0.0:
		for other in nation.borders:
			if rng.randf() < e.spread_chance:
				_pending.append([other, e.id])

	var hero := NameGenerator.person_name(nation.race, rng) if e.text.contains("{hero}") else ""
	var text := e.text.format({
		"nation": nation.name, "region": region.name, "city": city_name,
		"hero": hero, "ruler": nation.ruler_display(), "name": e.display_name,
	})
	world.log_event(e.chronicle_kind, text, PackedInt32Array([nation.id]))
	return true


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
