class_name WorldSeeder
extends RefCounted
## Размещает стартовые государства: для каждой расы ищет подходящие ей места
## (родные биомы, реки, побережье), разносит столицы подальше друг от друга
## и выращивает вокруг каждой небольшую территорию с учётом стоимости
## экспансии по биомам (эльфы держатся лесов, дворфы — гор и т.д.).

## Сколько случайных клеток-кандидатов оценивать при выборе столицы.
const SITE_SAMPLES := 2500
## Доля суши, которую в среднем занимает стартовое государство (× expansion расы).
const START_TERRITORY_SHARE := 0.009

var _world: World
var _map: WorldMap
var _rng: RandomNumberGenerator
var _land_cells := PackedInt32Array()
var _capitals: Array[Vector2i] = []


func seed_world(world: World) -> void:
	_world = world
	_map = world.map
	_rng = world.rng
	_prepare()

	var races := _pick_races()
	if races.is_empty() or _land_cells.is_empty():
		return
	var count := world.settings.nation_count
	# Минимальное расстояние между столицами — из расчёта равномерного раздела суши.
	var min_dist := sqrt(float(_land_cells.size()) / maxf(count, 1)) * 0.9

	# Порядок появления: по кругу по расам (каждая раса получает хотя бы одно
	# государство, если их хватает), внутри круга — случайно.
	var order: Array[RaceDef] = []
	while order.size() < count:
		var round_races := races.duplicate()
		_shuffle(round_races)
		for r in round_races:
			if order.size() < count:
				order.append(r)

	for race in order:
		var site := _pick_site(race, min_dist)
		if site < 0:
			continue
		_found_nation(race, site)
	world.update_label_anchors()


func _prepare() -> void:
	for i in _map.cell_count():
		if _map.is_land(i):
			_land_cells.append(i)
	_capitals.clear()


func _pick_races() -> Array[RaceDef]:
	var result: Array[RaceDef] = []
	var enabled := _world.settings.enabled_races
	for race in RaceDB.all():
		if (enabled.is_empty() and race.spawn_at_start) or enabled.has(race.id):
			result.append(race)
	return result


func _pick_site(race: RaceDef, min_dist: float) -> int:
	var dist := min_dist
	for relax in 6:
		var best := -1
		var best_score := -INF
		for s in SITE_SAMPLES:
			var cell := _land_cells[_rng.randi_range(0, _land_cells.size() - 1)]
			if _world.owner[cell] != -1:
				continue
			var p := _map.cell_pos(cell)
			# Не у самого края карты.
			var edge := 3 * _world.grid_scale
			if p.x < edge or p.y < edge or p.x >= _map.width - edge or p.y >= _map.height - edge:
				continue
			var ok := true
			for c in _capitals:
				if (c - p).length_squared() < dist * dist:
					ok = false
					break
			if not ok:
				continue
			var score := _world.site_score(race, cell) + _rng.randf() * 0.25
			if score > best_score:
				best_score = score
				best = cell
		if best >= 0:
			return best
		dist *= 0.75
	return -1


func _found_nation(race: RaceDef, capital_cell: int) -> void:
	var nation := _world.found_nation(race)
	_capitals.append(_map.cell_pos(capital_cell))

	var target := clampi(int(_land_cells.size() * START_TERRITORY_SHARE * race.expansion), _world.gai(8), _world.gai(600))
	var claimed := grow_territory(nation, capital_cell, target)
	_world.add_city(nation, capital_cell, race, true)
	_world.log_event(&"nation", "Основано государство %s (%s), столица — %s." % [
		nation.name, race.display_name, _world.cities[nation.capital_city].name], PackedInt32Array([nation.id]))

	# Второй город — в лучшем месте территории, подальше от столицы.
	if claimed.size() >= _world.gai(30):
		var cap_pos := _map.cell_pos(capital_cell)
		var best := -1
		var best_score := -INF
		for cell in claimed:
			var d := Vector2(_map.cell_pos(cell) - cap_pos).length() / _world.grid_scale
			if d < 5.0:
				continue
			var score := _world.site_score(race, cell) + minf(d, 12.0) * 0.05
			if score > best_score:
				best_score = score
				best = cell
		if best >= 0:
			_world.add_city(nation, best, race, false)
	_compute_start_stats(nation, claimed)


## «Дейкстра» от столицы по стоимости экспансии; занимает до target ничьих клеток суши.
## 8 соседей (диагональ ×√2) и случайный разброс стоимости шага дают округлые
## «рваные» границы вместо ромбов.
func grow_territory(nation: Nation, start: int, target: int) -> PackedInt32Array:
	var claimed := PackedInt32Array()
	var heap := MinHeap.new()
	var visited := {}
	var race := nation.race
	var w := _map.width
	heap.push(start, 0.0)
	while not heap.is_empty() and claimed.size() < target:
		var cost := heap.top_priority()
		var c := heap.pop()
		if visited.has(c):
			continue
		visited[c] = true
		if _world.owner[c] != -1 or not _map.is_land(c):
			continue
		_world.set_owner(c, nation.id)
		claimed.append(c)
		var cx := c % w
		var cy := c / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if (dx == 0 and dy == 0) or not _map.in_bounds(cx + dx, cy + dy):
					continue
				var nb := c + dy * w + dx
				if visited.has(nb) or _world.owner[nb] != -1 or not _map.is_land(nb):
					continue
				var step := race.expansion_cost(_map.biome[nb]) * _rng.randf_range(0.6, 1.5)
				if dx != 0 and dy != 0:
					step *= 1.41
				if _map.river[nb] > 0:
					step *= 0.85
				heap.push(nb, cost + step)
	return claimed


func _compute_start_stats(nation: Nation, _cells: PackedInt32Array) -> void:
	var race := nation.race
	# Земля заселена наполовину — дальше население растёт логистически (PopulationSystem).
	nation.pop[race.index] = nation.capacity[race.index] * 0.5
	var pop_k := nation.population / 1000.0
	nation.stock[Goods.FOOD] = pop_k * race.food_need
	nation.stock[Goods.WOOD] = 30.0
	nation.stock[Goods.STONE] = 20.0
	nation.stock[Goods.METAL] = 5.0
	nation.stock[Goods.GOLD] = 40.0 + pop_k * race.trade
	nation.army = nation.population * 0.025 * race.military
	nation.stability = 0.7 + _rng.randf() * 0.2
	# Население городов — доля от населения страны (столица крупнее); дальше считает CitySystem.
	for city_id in nation.city_ids:
		var city := _world.cities[city_id]
		city.population = nation.population * (0.08 if city.is_capital else 0.04)


func _shuffle(arr: Array) -> void:
	# Свой Фишер–Йетс на RNG мира: Array.shuffle() использует глобальный RNG и ломает детерминизм.
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
