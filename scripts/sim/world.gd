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
## Регионы (провинции) — постоянная нарезка суши, см. RegionGenerator.
var regions: Array[Region] = []
## Регион каждой клетки (-1 — вода).
var region_of := PackedInt32Array()
## Регион клетки для шейдера (RGBA8: R,G — id + 1), неизменен после создания мира.
var region_texels := PackedByteArray()

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

var diplomacy := Diplomacy.new()

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
	regions = RegionGenerator.new().generate(self)
	region_texels.resize(n * 4)
	for i in n:
		var v := region_of[i] + 1
		region_texels[i * 4] = v & 0xff
		region_texels[i * 4 + 1] = (v >> 8) & 0xff
		region_texels[i * 4 + 3] = 255


# ---------------------------------------------------------------------------
# Территория
# ---------------------------------------------------------------------------

## Передаёт клетку государству nation_id (-1 — сделать ничьей).
## Жители клетки переезжают вместе с ней в пропорции её доли в ёмкости земли;
## город в клетке переходит к новому владельцу. Поддерживает учёт регионов
## и длины общих границ между государствами.
func set_owner(cell: int, nation_id: int) -> void:
	var old := owner[cell]
	if old == nation_id:
		return
	_update_borders(cell, old, nation_id)
	_update_region(cell, old, nation_id)
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
	if city_cell[cell] >= 0:
		_transfer_city(cities[city_cell[cell]], nation_id)
	ownership_version += 1


## Длина общих границ: число пар соседних клеток разных владельцев.
func _update_borders(cell: int, old: int, new: int) -> void:
	for nb in map.neighbors4(cell):
		var o := owner[nb]
		if o < 0:
			continue
		if old >= 0 and o != old:
			_add_border(old, o, -1)
		if new >= 0 and o != new:
			_add_border(new, o, 1)


func _add_border(a: int, b: int, delta: int) -> void:
	for pair in [[a, b], [b, a]]:
		var borders := nations[pair[0]].borders
		var v: int = borders.get(pair[1], 0) + delta
		if v <= 0:
			borders.erase(pair[1])
		else:
			borders[pair[1]] = v


func _update_region(cell: int, old: int, new: int) -> void:
	var rid := region_of[cell]
	if rid < 0:
		return
	var region := regions[rid]
	if old >= 0:
		_dec(region.owner_counts, old)
		_dec(nations[old].region_counts, rid)
	if new >= 0:
		region.owner_counts[new] = region.owner_counts.get(new, 0) + 1
		nations[new].region_counts[rid] = nations[new].region_counts.get(rid, 0) + 1
		if region.name.is_empty():
			# Регион называет тот, кто первым его заселил, — на своём языке.
			region.name = NameGenerator.unique(used_names, NameGenerator.place_name.bind(nations[new].race, rng))
		if old >= 0:
			region.conquered_year = year


static func _dec(counts: Dictionary, key: int) -> void:
	var v: int = counts.get(key, 0) - 1
	if v <= 0:
		counts.erase(key)
	else:
		counts[key] = v


## Город сменил владельца вместе со своей клеткой.
func _transfer_city(city: City, new_owner: int) -> void:
	var old := city.nation_id
	if old >= 0:
		var on := nations[old]
		var idx := on.city_ids.find(city.id)
		if idx >= 0:
			on.city_ids.remove_at(idx)
		if on.capital_city == city.id:
			city.is_capital = false
			choose_capital(on)
	city.nation_id = new_owner
	if new_owner >= 0:
		var nn := nations[new_owner]
		nn.city_ids.append(city.id)
		if nn.capital_city < 0:
			city.is_capital = true
			nn.capital_city = city.id
	else:
		destroy_city(city)


## Новая столица — крупнейший из оставшихся городов (или -1, если городов нет).
func choose_capital(nation: Nation) -> void:
	nation.capital_city = -1
	var best: City = null
	for id in nation.city_ids:
		var c := cities[id]
		if best == null or c.population > best.population:
			best = c
	if best != null:
		best.is_capital = true
		nation.capital_city = best.id


## Город разрушен: исчезает с карты, освобождает место для новых городов.
func destroy_city(city: City) -> void:
	if not city.alive:
		return
	city.alive = false
	city_cell[city.cell] = -1
	_mark_city_area(city.cell, -1)
	if city.nation_id >= 0:
		var nation := nations[city.nation_id]
		var idx := nation.city_ids.find(city.id)
		if idx >= 0:
			nation.city_ids.remove_at(idx)
		if nation.capital_city == city.id:
			city.is_capital = false
			choose_capital(nation)
	city.nation_id = -1


## Откалывает от old регионы region_ids в новое государство расы race
## (восстание, гражданская война, распад). Жители, города, часть армии и
## казны уходят вместе с землёй.
func split_off(old: Nation, region_ids: PackedInt32Array, race: RaceDef) -> Nation:
	var old_pop := old.population
	var nation := found_nation(race)
	nation.tech = old.tech
	for rid in region_ids:
		var region := regions[rid]
		region.unrest = 0.0
		region.conquered_year = year
		for c in region.cells:
			if owner[c] == old.id:
				set_owner(c, nation.id)
	if nation.cell_count == 0:
		nation.alive = false
		return nation
	choose_capital(nation)
	if nation.capital_city < 0:
		# Городов не было — столицей становится центр самого крупного региона.
		var site := regions[region_ids[0]].center
		if owner[site] != nation.id:
			site = nation.cells[0]
		if city_cell[site] < 0:
			var city := add_city(nation, site, race, true)
			city.population = 500.0
	var share := clampf(nation.population / maxf(old_pop, 1.0), 0.05, 0.9)
	nation.army = old.army * share * 1.2  # гарнизоны переходят на сторону мятежников
	old.army *= 1.0 - share
	for g in Goods.COUNT:
		nation.stock[g] = maxf(0.0, old.stock[g]) * share
		old.stock[g] -= nation.stock[g]
	nation.stability = 0.6
	CitySystem.recompute_building_effects(self, nation)
	CitySystem.recompute_building_effects(self, old)
	return nation


## Помечает погибшими государства без земли и вычищает их из дипломатии.
func cleanup_dead() -> void:
	for nation in nations:
		if nation.alive and nation.cell_count == 0:
			nation.alive = false
			nation.army = 0.0
			for id in nation.city_ids.duplicate():
				destroy_city(cities[id])
			diplomacy.forget_nation(self, nation.id)
			log_event(&"fall", "Государство %s пало." % nation.name, PackedInt32Array([nation.id]))


func region_at(cell: int) -> Region:
	var rid := region_of[cell]
	return regions[rid] if rid >= 0 else null


## Самый многочисленный народ региона (RaceDef.index или NO_RACE).
func region_majority_race(region: Region, owner_id: int = -2) -> int:
	# Однородному государству считать нечего — там живёт его народ.
	if owner_id >= 0 and nations[owner_id].primary_share() > 0.999:
		return nations[owner_id].race.index
	var counts := PackedInt32Array()
	counts.resize(RaceDB.count())
	var best := NO_RACE
	var best_count := 0
	for c in region.cells:
		if owner_id != -2 and owner[c] != owner_id:
			continue
		var r := cell_race[c]
		if r == NO_RACE:
			continue
		counts[r] += 1
		if counts[r] > best_count:
			best_count = counts[r]
			best = r
	return best


## Население части региона, принадлежащей государству: ёмкость его клеток × заселённость.
func region_population(region: Region, owner_id: int) -> float:
	if owner_id < 0:
		return 0.0
	var nation := nations[owner_id]
	var total := 0.0
	for c in region.cells:
		if owner[c] != owner_id:
			continue
		var r := cell_race[c]
		if r == NO_RACE or nation.capacity[r] <= 0.0:
			continue
		total += cell_capacity(RaceDB.by_index(r), c) * nation.pop[r] / nation.capacity[r]
	return total


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
	city.luck = clampf(exp(rng.randfn(0.0, 0.6)), 0.25, 5.0)
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
