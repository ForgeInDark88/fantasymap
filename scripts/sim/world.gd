class_name World
extends RefCounted
## Полное состояние мира: карта + государства + города + принадлежность клеток.
##
## Это «модель» симуляции: никакой отрисовки, никаких нод. Рендер читает
## owner_texels, интерфейс — списки nations/cities и летопись. Все изменения
## владельцев клеток проходят через set_owner(): он поддерживает списки клеток
## государств, их добычу, ёмкость земли и переселяет жителей вместе с клеткой.

const NO_RACE := 255
## Сколько записей летописи хранить.
const CHRONICLE_LIMIT := 4000
## Минимальное расстояние между городами (в клетках, по Чебышёву).
const CITY_SPACING := 6

var map: WorldMap
var settings: MapSettings
var year := 0
var rng := RandomNumberGenerator.new()

var nations: Array[Nation] = []
var cities: Array[City] = []

## id государства-владельца для каждой клетки (-1 — ничья).
var owner := PackedInt32Array()
## То же в виде RGBA8 для шейдера: R,G — (id + 1) в 16 битах, B — суша (255) / вода (0).
var owner_texels := PackedByteArray()
## Позиция клетки в Nation.cells владельца (для удаления за O(1)).
var cell_slot := PackedInt32Array()
## Какой народ живёт в клетке (RaceDef.index; NO_RACE — никто).
## Народ остаётся на месте при смене владельца — так появляются многорасовые государства.
var cell_race := PackedByteArray()
## Месторождение в клетке: индекс в EconomyDB.deposits() + 1 (0 — нет).
var deposit := PackedByteArray()
## Добыча клетки в год: cell * Goods.COUNT + goods.
var cell_yield := PackedFloat32Array()
## id города в клетке (-1 — нет).
var city_cell := PackedInt32Array()
## Сколько городов ближе CITY_SPACING к клетке (0 — здесь можно основать город).
## Счётчик, а не флаг, чтобы при разрушении города (этап 4) просто вычесть.
var city_block := PackedByteArray()
## Растёт при каждом изменении границ — рендер по нему понимает, что пора обновиться.
var ownership_version := 0

## Летопись: {year, kind, text, nations: PackedInt32Array}.
var chronicle: Array[Dictionary] = []
## Общее число записей за всю историю (не уменьшается при обрезке старых).
var chronicle_total := 0

## Уже выданные имена (города, государства, правители) — чтобы не повторялись.
var used_names: Dictionary = {}


## Полный цикл создания мира: карта + стартовые государства. Синхронно —
## WorldState вызывает это в фоновом потоке, тесты — напрямую.
static func create(s: MapSettings) -> World:
	var world := World.new(MapGenerator.new().generate(s))
	WorldSeeder.new().seed_world(world)
	return world


func _init(world_map: WorldMap) -> void:
	map = world_map
	settings = world_map.settings
	rng.seed = hash(str(settings.world_seed) + ":world")
	var n := map.cell_count()
	owner.resize(n)
	owner.fill(-1)
	cell_slot.resize(n)
	cell_slot.fill(-1)
	city_cell.resize(n)
	city_cell.fill(-1)
	city_block.resize(n)
	cell_race.resize(n)
	cell_race.fill(NO_RACE)
	owner_texels.resize(n * 4)
	for i in n:
		owner_texels[i * 4 + 2] = 255 if map.is_land(i) else 0
		owner_texels[i * 4 + 3] = 255
	_place_deposits()
	_compute_cell_yields()


# ---------------------------------------------------------------------------
# Территория
# ---------------------------------------------------------------------------

## Передаёт клетку государству nation_id (-1 — сделать ничьей).
## Жители клетки переезжают вместе с ней в пропорции её доли в ёмкости земли.
func set_owner(cell: int, nation_id: int) -> void:
	var old := owner[cell]
	if old == nation_id:
		return
	var r := cell_race[cell]
	var moved := 0.0
	if old >= 0:
		var on := nations[old]
		_remove_cell(on, cell)
		if r != NO_RACE:
			var cap := cell_capacity(RaceDB.by_index(r), cell)
			if on.capacity[r] > 0.0:
				moved = on.pop[r] * clampf(cap / on.capacity[r], 0.0, 1.0)
			on.capacity[r] = maxf(0.0, on.capacity[r] - cap)
			on.pop[r] = maxf(0.0, on.pop[r] - moved)
	owner[cell] = nation_id
	var v := nation_id + 1
	owner_texels[cell * 4] = v & 0xff
	owner_texels[cell * 4 + 1] = (v >> 8) & 0xff
	if nation_id >= 0:
		var nn := nations[nation_id]
		if r == NO_RACE:
			# Ничейную землю заселяет народ нового владельца.
			r = nn.race.index
			cell_race[cell] = r
		_add_cell(nn, cell)
		nn.capacity[r] += cell_capacity(RaceDB.by_index(r), cell)
		nn.pop[r] += moved
	ownership_version += 1


func _add_cell(nation: Nation, cell: int) -> void:
	cell_slot[cell] = nation.cells.size()
	nation.cells.append(cell)
	nation.sum_x += cell % map.width
	nation.sum_y += cell / map.width
	var base := cell * Goods.COUNT
	for g in Goods.COUNT:
		nation.yields[g] += cell_yield[base + g]


func _remove_cell(nation: Nation, cell: int) -> void:
	var slot := cell_slot[cell]
	var last_index := nation.cells.size() - 1
	var last := nation.cells[last_index]
	nation.cells[slot] = last
	cell_slot[last] = slot
	nation.cells.resize(last_index)
	cell_slot[cell] = -1
	nation.sum_x -= cell % map.width
	nation.sum_y -= cell / map.width
	var base := cell * Goods.COUNT
	for g in Goods.COUNT:
		nation.yields[g] -= cell_yield[base + g]


func nation_at(cell: int) -> Nation:
	var id := owner[cell]
	return nations[id] if id >= 0 else null


func city_at(cell: int) -> City:
	var id := city_cell[cell]
	return cities[id] if id >= 0 else null


func add_nation(race: RaceDef) -> Nation:
	var nation := Nation.new()
	nation.id = nations.size()
	nation.race = race
	nation.race_id = race.id
	nation.founded_year = year
	nations.append(nation)
	return nation


## Создаёт государство расы race с именем, формой правления, правителем и цветом
## (без территории — её назначают через set_owner).
func found_nation(race: RaceDef) -> Nation:
	var nation := add_nation(race)
	nation.short_name = NameGenerator.unique(used_names, NameGenerator.place_name.bind(race, rng))
	var title := NameGenerator.state_title(race, nation.short_name, rng)
	nation.name = title[0]
	nation.ruler_title = title[1]
	new_ruler(nation)
	nation.color = nation_color(nation.id)
	return nation


## Новый правитель: имя по языку расы, возраст и срок правления по продолжительности жизни.
func new_ruler(nation: Nation) -> void:
	var race := nation.race
	nation.ruler_name = NameGenerator.unique(used_names, NameGenerator.person_name.bind(race, rng))
	if race.lifespan <= 0:
		# Бессмертные (нежить) правят, пока их не уничтожат.
		nation.ruler_age = rng.randi_range(50, 500)
		nation.reign_left = rng.randi_range(150, 600)
	else:
		nation.ruler_age = int(race.lifespan * rng.randf_range(0.25, 0.45))
		nation.reign_left = maxi(3, int(race.lifespan * rng.randf_range(0.12, 0.5)))


## Различимые цвета: шаг по оттенку на «золотой угол», с вариацией насыщенности/яркости.
static func nation_color(id: int) -> Color:
	var hue := fposmod(0.13 + id * 0.618034, 1.0)
	var sat := 0.55 + 0.2 * float((id * 7) % 3) / 2.0
	var val := 0.82 + 0.13 * float((id * 5) % 2)
	return Color.from_hsv(hue, sat, val)


## Привлекательность клетки для поселения расой race: родной биом, пригодность,
## река, побережье и окрестности.
func site_score(race: RaceDef, cell: int) -> float:
	var b := map.biome[cell]
	var score := race.affinity_by_biome[b] * 1.6 + BiomeDB.get_def(b).habitability * 0.7
	if map.river[cell] > 0:
		score += 0.35
	if is_coastal(cell):
		score += race.coast_affinity * 0.5
	# Окрестности тоже важны: город посреди одинокой клетки леса — плохая идея.
	var p := map.cell_pos(cell)
	var around := 0.0
	var samples := 0
	for dy in range(-3, 4, 3):
		for dx in range(-3, 4, 3):
			if map.in_bounds(p.x + dx, p.y + dy):
				around += race.affinity_by_biome[map.biome[map.index_of(p.x + dx, p.y + dy)]]
				samples += 1
	return score + around / maxf(samples, 1) * 0.8


func add_city(nation: Nation, cell: int, race: RaceDef, is_capital: bool) -> City:
	var city := City.new()
	city.id = cities.size()
	city.cell = cell
	city.nation_id = nation.id
	city.race_id = race.id
	city.is_capital = is_capital
	city.founded_year = year
	city.name = NameGenerator.unique(used_names, NameGenerator.place_name.bind(race, rng))
	city.coastal = is_coastal(cell)
	city.weight = clampf(site_score(race, cell) * 0.5, 0.5, 2.0)
	city.near_biomes = biome_mask_near(cell, 2)
	cities.append(city)
	city_cell[cell] = city.id
	_mark_city_area(cell, 1)
	nation.city_ids.append(city.id)
	if is_capital:
		nation.capital_city = city.id
	return city


# ---------------------------------------------------------------------------
# Земля и ресурсы
# ---------------------------------------------------------------------------

## Сколько жителей расы race может прокормить клетка.
func cell_capacity(race: RaceDef, cell: int) -> float:
	var b := map.biome[cell]
	if Biome.is_water(b):
		return 0.0
	var def := BiomeDB.get_def(b)
	var aff := race.affinity_by_biome[b]
	# Тем, кто не нуждается в еде, плодородие безразлично.
	var food := lerpf(0.6, 0.25 + def.fertility, clampf(race.food_need, 0.0, 1.0))
	var cap := 1000.0 * food * lerpf(0.35, 1.2, aff)
	if map.river[cell] > 0:
		cap *= 1.3
	if race.has_trait(&"farmers"):
		cap *= 1.0 + def.fertility * 0.3
	return cap


func is_coastal(cell: int) -> bool:
	for nb in map.neighbors4(cell):
		var b := map.biome[nb]
		if b == Biome.OCEAN or b == Biome.SEA:
			return true
	return false


## Битовая маска биомов (бит = индекс биома) в квадрате радиуса radius вокруг клетки.
func biome_mask_near(cell: int, radius: int) -> int:
	var p := map.cell_pos(cell)
	var mask := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if map.in_bounds(p.x + dx, p.y + dy):
				mask |= 1 << map.biome[map.index_of(p.x + dx, p.y + dy)]
	return mask


## Можно ли основать город в клетке (нет других городов ближе CITY_SPACING).
func can_place_city(cell: int) -> bool:
	return city_block[cell] == 0


func _mark_city_area(cell: int, delta: int) -> void:
	var p := map.cell_pos(cell)
	var r := CITY_SPACING
	for y in range(maxi(0, p.y - r), mini(map.height, p.y + r + 1)):
		for x in range(maxi(0, p.x - r), mini(map.width, p.x + r + 1)):
			var i := y * map.width + x
			city_block[i] = clampi(city_block[i] + delta, 0, 255)


func deposit_at(cell: int) -> DepositDef:
	var d := deposit[cell]
	return EconomyDB.deposits()[d - 1] if d > 0 else null


func _place_deposits() -> void:
	var n := map.cell_count()
	deposit.resize(n)
	var defs := EconomyDB.deposits()
	for i in n:
		if not map.is_land(i):
			continue
		var biome_id := BiomeDB.get_def(map.biome[i]).id
		for d in defs.size():
			var def := defs[d]
			var weight: float = def.biome_weights.get(biome_id, 0.0)
			if weight > 0.0 and rng.randf() < def.chance * weight:
				deposit[i] = d + 1
				break


func _compute_cell_yields() -> void:
	var n := map.cell_count()
	cell_yield.resize(n * Goods.COUNT)
	for i in n:
		var def := BiomeDB.get_def(map.biome[i])
		for g in Goods.COUNT:
			cell_yield[i * Goods.COUNT + g] = def.yield_of(g)
		var dep := deposit_at(i)
		if dep != null:
			cell_yield[i * Goods.COUNT + Goods.index_of(dep.goods)] += dep.amount


# ---------------------------------------------------------------------------
# Летопись и подписи
# ---------------------------------------------------------------------------

func log_event(kind: StringName, text: String, nation_ids: PackedInt32Array = PackedInt32Array()) -> void:
	chronicle.append({"year": year, "kind": kind, "text": text, "nations": nation_ids})
	chronicle_total += 1
	if chronicle.size() > CHRONICLE_LIMIT:
		chronicle = chronicle.slice(chronicle.size() - CHRONICLE_LIMIT)


## Точка подписи каждого государства: клетка у центра масс территории
## (или ближайшая к нему своя клетка, если центр вне территории).
func update_label_anchors() -> void:
	for nation in nations:
		var n := nation.cells.size()
		if n == 0:
			nation.label_cell = -1
			continue
		var c := nation.centroid()
		var ci := map.index_of(clampi(roundi(c.x), 0, map.width - 1), clampi(roundi(c.y), 0, map.height - 1))
		if owner[ci] == nation.id:
			nation.label_cell = ci
			continue
		var best := nation.cells[0]
		var best_d := INF
		for cell in nation.cells:
			var dx := float(cell % map.width) - c.x
			var dy := float(cell / map.width) - c.y
			var d := dx * dx + dy * dy
			if d < best_d:
				best_d = d
				best = cell
		nation.label_cell = best
