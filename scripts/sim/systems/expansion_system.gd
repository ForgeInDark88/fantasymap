class_name ExpansionSystem
extends RefCounted
## Мирная экспансия на ничьи соседние клетки.
##
## Государство копит «очки экспансии» (больше при высоком давлении населения
## и стабильности, растёт с периметром ~ √площади) и тратит их на клетки:
## стоимость клетки зависит от биома и расы (RaceDef.expansion_cost), так что
## дворфы легко занимают горы, а эльфы почти не выходят из лесов.

## Множитель скорости экспансии.
const RATE := 1.8
## Сколько промахов подряд (клетка занята или вода) допустимо за год.
const MAX_MISSES := 20
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]


func tick(world: World, nation: Nation) -> void:
	var n := nation.cells.size()
	if n == 0:
		return
	var race := nation.race
	var map := world.map
	var rng := world.rng
	var cap := nation.total_capacity()
	var pressure := clampf(nation.population / cap, 0.0, 1.2) if cap > 0.0 else 1.0
	# Масштаб сетки: клеток в периметре × scale, а клетка — 1/scale² площади: очков × scale.
	var gs := world.grid_scale
	var rate := RATE * sqrt(n) * gs * race.expansion * nation.effect(&"expansion_mult") * (0.2 + pressure) * (0.4 + nation.stability * 0.6)
	nation.expansion_points = minf(nation.expansion_points + rate, rate * 3.0 + 4.0 * (gs * gs))

	var claimed := 0
	# Кому расти некуда — лишь изредка «прощупывает» границу (иначе тратим время впустую).
	var attempts := 10 * gs if nation.stalled_years >= 3 else mini(int(rate * 4.0) + 6, 120 * gs * gs)
	# Много промахов подряд — свободной земли у границы почти нет, дальше не ищем.
	var misses := 0
	while attempts > 0 and nation.expansion_points > 0.0 and misses < MAX_MISSES * gs:
		attempts -= 1
		misses += 1
		var c := nation.cells[rng.randi_range(0, n - 1)]
		var d := DIRS[rng.randi_range(0, 7)]
		var x := c % map.width + d.x
		var y := c / map.width + d.y
		if not map.in_bounds(x, y):
			continue
		var nb := map.index_of(x, y)
		if world.owner[nb] != -1 or not map.is_land(nb):
			continue
		var cost := race.expansion_cost(map.biome[nb])
		if map.river[nb] > 0:
			cost *= 0.85
		if cost > nation.expansion_points:
			# Дорогая клетка: иногда копим на неё, иногда ищем дешевле.
			if rng.randf() < 0.3:
				break
			continue
		world.set_owner(nb, nation.id)
		misses = 0
		nation.expansion_points -= cost
		n += 1
		claimed += 1
	# Расти некуда: копится «земельный голод» (повод для войн) и тяга к колониям.
	nation.stalled_years = nation.stalled_years + 1 if claimed == 0 else 0
	if nation.stalled_years >= 5 and pressure > 0.75 and rng.randf() < 0.06:
		_try_colonize(world, nation)


## Колония за морем: из портового города — в ничейный прибрежный регион.
func _try_colonize(world: World, nation: Nation) -> void:
	var ports := PackedInt32Array()
	for id in nation.city_ids:
		var city := world.cities[id]
		if city.buildings.has(&"harbor"):
			ports.append(city.cell)
	if ports.is_empty() or nation.stock[Goods.WOOD] < 40.0 or nation.stock[Goods.GOLD] < 60.0:
		return
	var map := world.map
	var max_range := map.width * 0.4 * nation.effect(&"naval_mult")
	var best: Region = null
	var best_score := -INF
	for s in 40:
		var region := world.regions[world.rng.randi_range(0, world.regions.size() - 1)]
		if not region.owner_counts.is_empty() or not region.coastal or region.cells.size() < world.gai(15):
			continue
		var center := Vector2(map.cell_pos(region.center))
		var dist := INF
		for port in ports:
			dist = minf(dist, center.distance_to(Vector2(map.cell_pos(port))))
		if dist > max_range:
			continue
		var score := world.site_score(nation.race, region.center) - dist / max_range
		if score > best_score:
			best_score = score
			best = region
	if best == null or not world.can_place_city(best.center):
		return
	nation.stock[Goods.WOOD] -= 40.0
	nation.stock[Goods.GOLD] -= 60.0
	# Колонисты занимают ближайшие к центру клетки региона.
	var center_pos := Vector2(map.cell_pos(best.center))
	var cells := Array(best.cells)
	cells.sort_custom(func(a: int, b: int) -> bool:
		return Vector2(map.cell_pos(a)).distance_squared_to(center_pos) < Vector2(map.cell_pos(b)).distance_squared_to(center_pos))
	for c in cells.slice(0, world.gai(25)):
		if world.owner[c] == -1:
			world.set_owner(c, nation.id)
	var city := world.add_city(nation, best.center, nation.race, false)
	city.population = 300.0
	nation.stalled_years = 0
	world.log_event(&"colony", "%s основывает за морем колонию %s в регионе %s." % [nation.name, city.name, best.name],
			PackedInt32Array([nation.id]))
