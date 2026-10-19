class_name CitySystem
extends RefCounted
## Города: рост населения, основание новых городов, строительство построек.

## Стоимость основания города.
const FOUND_COST_WOOD := 25.0
const FOUND_COST_GOLD := 40.0
## Шанс в год попытаться что-нибудь построить.
const BUILD_CHANCE := 0.4


func tick(world: World, nation: Nation) -> void:
	_grow_cities(world, nation)
	# Бонусы взвешены населением городов, а оно меняется плавно — хватит раза в 10 лет.
	if (world.year + nation.id) % 10 == 0:
		recompute_building_effects(world, nation)
	_maybe_found_city(world, nation)
	if world.rng.randf() < BUILD_CHANCE:
		_try_build(world, nation)


## Горожане — доля населения страны, распределённая по «весу» городов
## (столица притягивает больше, постройки тоже добавляют привлекательности).
func _grow_cities(world: World, nation: Nation) -> void:
	var total_w := 0.0
	for id in nation.city_ids:
		total_w += _city_weight(world.cities[id])
	if total_w <= 0.0:
		return
	var urban := nation.population * nation.race.urban_share
	for id in nation.city_ids:
		var city := world.cities[id]
		var target := urban * _city_weight(city) / total_w
		city.population = lerpf(city.population, target, 0.12)


func _city_weight(city: City) -> float:
	return city.weight * (2.5 if city.is_capital else 1.0) * (1.0 + city.buildings.size() * 0.06)


func _maybe_found_city(world: World, nation: Nation) -> void:
	var race := nation.race
	if nation.cells.size() < race.cells_per_city * (nation.city_ids.size() + 1):
		return
	if nation.stock[Goods.WOOD] < FOUND_COST_WOOD or nation.stock[Goods.GOLD] < FOUND_COST_GOLD:
		return
	if world.rng.randf() > 0.3:
		return
	var site := find_city_site(world, nation, 40)
	if site < 0:
		return
	nation.stock[Goods.WOOD] -= FOUND_COST_WOOD
	nation.stock[Goods.GOLD] -= FOUND_COST_GOLD
	var settlers_race := RaceDB.by_index(world.cell_race[site]) if world.cell_race[site] != World.NO_RACE else race
	var city := world.add_city(nation, site, settlers_race, false)
	city.population = nation.population * 0.01
	world.log_event(&"city", "%s основывает город %s." % [nation.name, city.name], PackedInt32Array([nation.id]))


## Лучшая из samples случайных клеток территории, достаточно далёкая от других городов.
func find_city_site(world: World, nation: Nation, samples: int) -> int:
	var map := world.map
	var best := -1
	var best_score := -INF
	for s in samples:
		var cell := nation.cells[world.rng.randi_range(0, nation.cells.size() - 1)]
		if not world.can_place_city(cell):
			continue
		var r := world.cell_race[cell]
		var race := RaceDB.by_index(r) if r != World.NO_RACE else nation.race
		var score := world.site_score(race, cell)
		if map.river[cell] > 0 or world.deposit[cell] > 0:
			score += 0.2
		if score > best_score:
			best_score = score
			best = cell
	return best


## Выбирает случайный город и строит в нём случайную доступную постройку.
func _try_build(world: World, nation: Nation) -> void:
	if nation.city_ids.is_empty():
		return
	var rng := world.rng
	var city := world.cities[nation.city_ids[rng.randi_range(0, nation.city_ids.size() - 1)]]
	var options: Array[BuildingDef] = []
	for b in EconomyDB.buildings():
		if can_build(world, nation, city, b):
			options.append(b)
	if options.is_empty():
		return
	var b := options[rng.randi_range(0, options.size() - 1)]
	for goods_id in b.cost:
		nation.stock[Goods.index_of(goods_id)] -= b.cost[goods_id]
	city.buildings.append(b.id)
	recompute_building_effects(world, nation)
	if b.notable:
		world.log_event(&"building", "В городе %s (%s) построено: %s." % [city.name, nation.short_name, b.display_name],
				PackedInt32Array([nation.id]))


func can_build(world: World, nation: Nation, city: City, b: BuildingDef) -> bool:
	if city.buildings.has(b.id) or city.population < b.min_population:
		return false
	for other in b.excludes:
		if city.buildings.has(other):
			return false
	if b.requires_coast and not city.coastal:
		return false
	if not b.allowed_races.is_empty() and not b.allowed_races.has(nation.race_id):
		return false
	if not b.required_traits.is_empty():
		var ok := false
		for t in b.required_traits:
			if nation.race.has_trait(t):
				ok = true
				break
		if not ok:
			return false
	for goods_id in b.cost:
		if nation.stock[Goods.index_of(goods_id)] < b.cost[goods_id]:
			return false
	if b.required_biome_mask != 0 and (city.near_biomes & b.required_biome_mask) == 0:
		return false
	return true


## Суммирует эффекты построек государства. Процентные бонусы (еда, армия,
## наука, стабильность) взвешены долей горожан: казармы в столице значат
## больше, чем в деревне, а одинаковые постройки во всех городах дают ровно
## свой бонус, а не его кратное. Добыча (шахты, рынки) просто складывается.
static func recompute_building_effects(world: World, nation: Nation) -> void:
	nation.food_bonus = 0.0
	nation.stability_bonus = 0.0
	nation.army_bonus = 0.0
	nation.science_bonus = 0.0
	nation.building_production.fill(0.0)
	var urban := 0.0
	for id in nation.city_ids:
		urban += maxf(world.cities[id].population, 1.0)
	for id in nation.city_ids:
		var city := world.cities[id]
		var share := maxf(city.population, 1.0) / urban
		for building_id in city.buildings:
			var b := EconomyDB.get_building(building_id)
			if b == null:
				continue
			nation.food_bonus += b.food_bonus * share
			nation.stability_bonus += b.stability * share
			nation.army_bonus += b.army_bonus * share
			nation.science_bonus += b.science_bonus * share
			for goods_id in b.production:
				nation.building_production[Goods.index_of(goods_id)] += b.production[goods_id]
