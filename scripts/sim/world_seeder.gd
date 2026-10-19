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
var _coastal := PackedByteArray()
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
	world.compute_label_anchors()


func _prepare() -> void:
	var n := _map.cell_count()
	_coastal.resize(n)
	for i in n:
		if not _map.is_land(i):
			continue
		_land_cells.append(i)
		for nb in _map.neighbors4(i):
			if _map.biome[nb] == Biome.OCEAN or _map.biome[nb] == Biome.SEA:
				_coastal[i] = 1
				break
	_capitals.clear()


func _pick_races() -> Array[RaceDef]:
	var result: Array[RaceDef] = []
	var enabled := _world.settings.enabled_races
	for race in RaceDB.all():
		if enabled.is_empty() or enabled.has(race.id):
			result.append(race)
	return result


## Привлекательность клетки для основания поселения расой race.
func site_score(race: RaceDef, cell: int) -> float:
	var b := _map.biome[cell]
	var score := race.affinity_by_biome[b] * 1.6 + BiomeDB.get_def(b).habitability * 0.7
	if _map.river[cell] > 0:
		score += 0.35
	if _coastal[cell] == 1:
		score += race.coast_affinity * 0.5
	# Окрестности тоже важны: столица посреди одинокой клетки леса — плохая идея.
	var p := _map.cell_pos(cell)
	var around := 0.0
	var samples := 0
	for dy in range(-3, 4, 3):
		for dx in range(-3, 4, 3):
			if _map.in_bounds(p.x + dx, p.y + dy):
				around += race.affinity_by_biome[_map.biome[_map.index_of(p.x + dx, p.y + dy)]]
				samples += 1
	return score + around / maxf(samples, 1) * 0.8


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
			if p.x < 3 or p.y < 3 or p.x >= _map.width - 3 or p.y >= _map.height - 3:
				continue
			var ok := true
			for c in _capitals:
				if (c - p).length_squared() < dist * dist:
					ok = false
					break
			if not ok:
				continue
			var score := site_score(race, cell) + _rng.randf() * 0.25
			if score > best_score:
				best_score = score
				best = cell
		if best >= 0:
			return best
		dist *= 0.75
	return -1


func _found_nation(race: RaceDef, capital_cell: int) -> void:
	var nation := _world.add_nation(race)
	nation.short_name = NameGenerator.unique(_world.used_names, NameGenerator.place_name.bind(race, _rng))
	var title := NameGenerator.state_title(race, nation.short_name, _rng)
	nation.name = title[0]
	nation.ruler_title = title[1]
	nation.ruler_name = NameGenerator.unique(_world.used_names, NameGenerator.person_name.bind(race, _rng))
	nation.color = _nation_color(nation.id)
	_capitals.append(_map.cell_pos(capital_cell))

	var target := clampi(int(_land_cells.size() * START_TERRITORY_SHARE * race.expansion), 8, 600)
	var claimed := grow_territory(nation, capital_cell, target)
	_world.add_city(nation, capital_cell, race, true)

	# Второй город — в лучшем месте территории, подальше от столицы.
	if claimed.size() >= 30:
		var cap_pos := _map.cell_pos(capital_cell)
		var best := -1
		var best_score := -INF
		for cell in claimed:
			var d := Vector2(_map.cell_pos(cell) - cap_pos).length()
			if d < 5.0:
				continue
			var score := site_score(race, cell) + minf(d, 12.0) * 0.05
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


func _compute_start_stats(nation: Nation, cells: PackedInt32Array) -> void:
	var race := nation.race
	var capacity := 0.0
	for i in cells:
		capacity += _world.cell_capacity(race, i)
	nation.population = capacity * 0.5
	nation.army = nation.population * 0.03 * race.military
	nation.wealth = nation.population * 0.01 * race.trade
	nation.stability = 0.7 + _rng.randf() * 0.2
	# Население городов — доля от населения страны (столица крупнее).
	for city_id in nation.city_ids:
		var city := _world.cities[city_id]
		city.population = nation.population * (0.12 if city.is_capital else 0.05)


## Различимые цвета: шаг по оттенку на «золотой угол», с вариацией насыщенности/яркости.
func _nation_color(id: int) -> Color:
	var hue := fposmod(0.13 + id * 0.618034, 1.0)
	var sat := 0.55 + 0.2 * float((id * 7) % 3) / 2.0
	var val := 0.82 + 0.13 * float((id * 5) % 2)
	return Color.from_hsv(hue, sat, val)


func _shuffle(arr: Array) -> void:
	# Свой Фишер–Йетс на RNG мира: Array.shuffle() использует глобальный RNG и ломает детерминизм.
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
