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
## Месяц текущего года: 0..11; день месяца: 0..29.
var month := 0
var day := 0
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
## Ёмкость клетки для её народа (кэш для карты населения; 0 — не заселена).
var cell_cap := PackedFloat32Array()
## id города в клетке (-1 — нет).
var city_cell := PackedInt32Array()
## Сколько городов ближе CITY_SPACING к клетке (0 — здесь можно основать город).
## Счётчик, а не флаг, чтобы при разрушении города (этап 4) просто вычесть.
var city_block := PackedByteArray()
## Растёт при каждом изменении границ — рендер по нему понимает, что пора обновиться.
var ownership_version := 0
## Метки для обходов карты без выделения памяти: клетка посещена, если mark[c] == stamp.
var mark := PackedInt32Array()
var _stamp := 0
## Какое-то государство потеряло последнюю клетку — cleanup_dead есть что делать.
var _maybe_dead := false
## Растёт при изменении рельефа (панель Бога) — рендер перерисовывает карту и регионы.
var terrain_version := 0

var diplomacy := Diplomacy.new()
var heroes: Array[Hero] = []
## Счётчики событий мира (ассимиляции, ереси, извержения…) — для тестов,
## статистики и достижений; см. count().
var counters: Dictionary[StringName, int] = {}

# --- Климат (ClimateSystem) ---
## Вулканы (клетки гор), следы бедствий на карте {cell, radius, kind, until},
## медленные сдвиги климата (температура и влажность) и урожайность поясов
## (север, умеренный, юг) в текущем году.
var volcanoes := PackedInt32Array()
var scars: Array[Dictionary] = []
var temp_shift := 0.0
var moist_shift := 0.0
var zone_harvest := PackedFloat32Array([1.0, 1.0, 1.0])
## Климатические беды поясов: пояс → {kind, until}; пепельная зима — до года ash_until.
var zone_events: Dictionary[int, Dictionary] = {}
var ash_until := -1
## Мировой кризис (CrisisSystem): пусто — нет; иначе {id, stage, stage_start, start,
## invader, titan_cell, titan_power, titan_name}. История кризисов и эпох.
var crisis: Dictionary = {}
var crisis_history: Array[Dictionary] = []
var last_crisis_end := -1000
var crisis_harvest := 1.0
var crisis_events: Dictionary = {}
var eras: Array[Dictionary] = []
## Артефакты-предметы (ArtifactSystem), роды героев, ордена и гильдии (этап 10.1).
var artifacts: Array[Artifact] = []
## Роды героев: {name, founder, year}.
var lineages: Array[Dictionary] = []
## Ещё не выросшие дети героев: {parents, name, race, class, karma, intellect, adult, cell, lineage}.
var hero_births: Array[Dictionary] = []
var orders: Array[HeroOrder] = []
## Руины (RuinSystem).
var ruins: Array[Ruin] = []
## Подземный мир: граф пещер (UndergroundSystem).
var caves: Array[Cave] = []
## Дороги и морские пути (граф между городами) и дороги каждого города.
var roads: Array[Road] = []
var city_roads: Dictionary[int, PackedInt32Array] = {}
## Тайные общества и культы, международные организации, наследия империй (этап 8).
var societies: Array[Society] = []
var orgs: Array[Organization] = []
var legacies: Array[Legacy] = []
## Культуры народов (CultureSystem).
var cultures: Array[Culture] = []
## Веры мира: стартовые (по data/religions) и рождённые в истории (ереси, новые веры).
var religions: Array[Religion] = []
## Странствующие (живые и не на троне) герои — чтобы не перебирать ежедневно всех павших.
var _wandering: Array[Hero] = []
## Те же герои, разложенные по «своему» дню месяца (id % 30); пересобирается при изменениях.
var _by_day: Array = []
var _by_day_dirty := true
## Источники силы, порталы, пустые троны, чудеса света.
var landmarks: Array[Landmark] = []
## Павшие герои, ждущие суда Судьбы (id героев).
var fate_queue := PackedInt32Array()
## Отложенные события (эпидемии, пришедшие от соседей): [nation_id, event_id].
var pending_events: Array = []
## Снимки статистики раз в HISTORY_STEP лет: {year, races: PackedFloat32Array, nations: {id: [население, клетки]}}.
var history: Array[Dictionary] = []
const HISTORY_STEP := 5

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
	ClimateSystem.place_volcanoes(world)
	UndergroundSystem.generate(world)
	return world


## generate = false — пустой мир для загрузки сохранения (без месторождений и регионов).
func _init(world_map: WorldMap, generate: bool = true) -> void:
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
	mark.resize(n)
	cell_cap.resize(n)
	cell_race.resize(n)
	cell_race.fill(NO_RACE)
	owner_texels.resize(n * 4)
	for i in n:
		owner_texels[i * 4 + 2] = 255 if map.is_land(i) else 0
		owner_texels[i * 4 + 3] = 255
	deposit.resize(n)
	if not generate:
		return
	init_religions()
	_place_deposits()
	_compute_cell_yields()
	regions = RegionGenerator.new().generate(self)
	_fill_region_texels()


## Стартовые веры — по одной на каждый data/religions/*.tres.
func init_religions() -> void:
	religions.clear()
	for d in ReligionDB.all():
		religions.append(Religion.from_def(d as ReligionDef, religions.size()))


func _fill_region_texels() -> void:
	var n := map.cell_count()
	region_texels.resize(n * 4)
	for i in n:
		var v := region_of[i] + 1
		region_texels[i * 4] = v & 0xff
		region_texels[i * 4 + 1] = (v >> 8) & 0xff
		region_texels[i * 4 + 3] = 255


## Восстановление после загрузки: добыча по месторождениям и регионы по region_of.
func restore_geography(region_count: int) -> void:
	_compute_cell_yields()
	regions = RegionGenerator.new().rebuild(self, region_count)
	_fill_region_texels()


## Восстановление города после загрузки (без генерации имени и учёта владельца).
func restore_city(city: City) -> void:
	cities.append(city)
	if city.alive:
		city_cell[city.cell] = city.id
		_mark_city_area(city.cell, 1)


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
		var cap := cell_capacity(RaceDB.by_index(r), cell)
		cell_cap[cell] = cap
		nn.capacity[r] += cap
		nn.pop[r] += moved
	if city_cell[cell] >= 0:
		_transfer_city(cities[city_cell[cell]], nation_id)
	ownership_version += 1


## Длина общих границ: число пар соседних клеток разных владельцев.
func _update_borders(cell: int, old: int, new: int) -> void:
	# Соседи без выделения массива (горячий путь: каждая смена владельца клетки).
	var w := map.width
	var x := cell % w
	if x > 0:
		_border_pair(owner[cell - 1], old, new)
	if x < w - 1:
		_border_pair(owner[cell + 1], old, new)
	if cell >= w:
		_border_pair(owner[cell - w], old, new)
	if cell < owner.size() - w:
		_border_pair(owner[cell + w], old, new)


func _border_pair(o: int, old: int, new: int) -> void:
	if o < 0:
		return
	if old >= 0 and o != old:
		_add_border(old, o, -1)
	if new >= 0 and o != new:
		_add_border(new, o, 1)


func _add_border(a: int, b: int, delta: int) -> void:
	_add_border_one(nations[a].borders, b, delta)
	_add_border_one(nations[b].borders, a, delta)


static func _add_border_one(borders: Dictionary, key: int, delta: int) -> void:
	var v: int = borders.get(key, 0) + delta
	if v <= 0:
		borders.erase(key)
	else:
		borders[key] = v


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
		# Первые поселенцы приносят свою веру и культуру.
		ReligionSystem.ensure_faith(region, nations[new].state_religion)
		if region.culture < 0:
			region.culture = nations[new].culture
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
			nn.home_cell = city.cell
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
		nation.home_cell = best.cell


## Город разрушен: исчезает с карты, освобождает место для новых городов.
func destroy_city(city: City) -> void:
	if not city.alive:
		return
	RuinSystem.on_city_destroyed(self, city)
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
	var nation := found_nation(race, false)
	# Осколок великой державы наследует её память (до раздела — пока она цела).
	LegacySystem.on_split(self, old, nation)
	nation.tech = old.tech
	# Отколовшиеся исповедуют веру большинства своих земель и хранят их культуру.
	nation.state_religion = ReligionSystem.majority_faith(self, region_ids, old.state_religion)
	nation.culture = CultureSystem.majority_culture(self, region_ids, old.culture)
	nation.tech_seen = old.tech
	# Знания наследуются — кроме недоступных расе отколовшихся.
	for t in old.techs:
		var def := TechDB.find(t)
		if def != null and def.race_weight(race) > 0.0:
			nation.techs[t] = true
	TechSystem.apply_effects(nation)
	for rid in region_ids:
		var region := regions[rid]
		region.unrest = 0.0
		region.conquered_year = year
		# Утраченные земли прежний владелец считает своими ещё долго.
		region.claims[old.id] = year + WarSystem.CLAIM_YEARS
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


func add_landmark(kind: StringName, name: String, cell: int, hero_id: int) -> Landmark:
	ensure_region_name(region_at(cell))
	var lm := Landmark.new()
	lm.id = landmarks.size()
	lm.kind = kind
	lm.name = name
	lm.cell = cell
	lm.hero_id = hero_id
	lm.created_year = year
	landmarks.append(lm)
	return lm


func active_landmarks(kind: StringName) -> Array[Landmark]:
	var result: Array[Landmark] = []
	for lm in landmarks:
		if lm.active and lm.kind == kind:
			result.append(lm)
	return result


## Сколько источников силы контролирует государство.
## Живые герои не на троне. Павшие и воцарившиеся отсеиваются при обращении.
func wandering_heroes() -> Array[Hero]:
	# Сначала ищем первого выбывшего — чаще всего его нет, и массив не трогаем.
	var first := -1
	for i in _wandering.size():
		var h := _wandering[i]
		if not h.alive or h.is_ruler:
			first = i
			break
	if first < 0:
		return _wandering
	var k := first
	for i in range(first + 1, _wandering.size()):
		var h := _wandering[i]
		if h.alive and not h.is_ruler:
			_wandering[k] = h
			k += 1
	_wandering.resize(k)
	_by_day_dirty = true
	return _wandering


## Странствующие герои, действующие в этот день месяца (могут попасться павшие —
## проверяйте alive).
func heroes_acting_on(day_of_month: int) -> Array:
	if _by_day_dirty:
		var list := wandering_heroes()
		_by_day_dirty = false
		_by_day.resize(Simulation.DAYS)
		for d in Simulation.DAYS:
			_by_day[d] = []
		for h in list:
			_by_day[h.id % Simulation.DAYS].append(h)
	return _by_day[day_of_month]


## Герой (снова) странствует: появился или вернулся с того света.
func add_wandering(hero: Hero) -> void:
	if _wandering.has(hero):
		return
	# Порядок по id — тот же, что после загрузки сохранения (детерминизм).
	var i := _wandering.size()
	while i > 0 and _wandering[i - 1].id > hero.id:
		i -= 1
	_wandering.insert(i, hero)
	_by_day_dirty = true


func sources_of(nation_id: int) -> int:
	var count := 0
	for lm in landmarks:
		if lm.active and lm.kind == &"source" and owner[lm.cell] == nation_id:
			count += 1
	return count


## Народ клетки сменился (ассимиляция): ёмкость и часть жителей переходят
## к новому народу того же государства.
func convert_cell_race(cell: int, new_race: int) -> void:
	var old_race := cell_race[cell]
	if old_race == new_race:
		return
	var o := owner[cell]
	if o < 0 or old_race == NO_RACE:
		cell_race[cell] = new_race
		return
	var nation := nations[o]
	var old_cap := cell_capacity(RaceDB.by_index(old_race), cell)
	var moved := 0.0
	if nation.capacity[old_race] > 0.0:
		moved = nation.pop[old_race] * clampf(old_cap / nation.capacity[old_race], 0.0, 1.0)
	nation.capacity[old_race] = maxf(0.0, nation.capacity[old_race] - old_cap)
	nation.pop[old_race] = maxf(0.0, nation.pop[old_race] - moved)
	cell_race[cell] = new_race
	var cap := cell_capacity(RaceDB.by_index(new_race), cell)
	cell_cap[cell] = cap
	nation.capacity[new_race] += cap
	nation.pop[new_race] += moved


func count(key: StringName, amount: int = 1) -> void:
	counters[key] = counters.get(key, 0) + amount


## Смена биома суши (дрейф климата): добыча и ёмкость земли владельца пересчитываются.
func change_land_biome(cell: int, new_biome: int) -> void:
	if map.biome[cell] == new_biome or Biome.is_water(new_biome) or not map.is_land(cell):
		return
	var o := owner[cell]
	var base := cell * Goods.COUNT
	var r := cell_race[cell]
	var nation: Nation = nations[o] if o >= 0 else null
	if nation != null:
		for g in Goods.COUNT:
			nation.yields[g] -= cell_yield[base + g]
		if r != NO_RACE:
			nation.capacity[r] = maxf(0.0, nation.capacity[r] - cell_capacity(RaceDB.by_index(r), cell))
	map.biome[cell] = new_biome
	refresh_cell_yield(cell)
	if nation != null:
		for g in Goods.COUNT:
			nation.yields[g] += cell_yield[base + g]
		if r != NO_RACE:
			var cap := cell_capacity(RaceDB.by_index(r), cell)
			cell_cap[cell] = cap
			nation.capacity[r] += cap


## Климатический пояс клетки: 0 — север, 1 — умеренный, 2 — юг.
func climate_zone(cell: int) -> int:
	return clampi(int(float(cell / map.width) / map.height * 3.0), 0, 2)


## Урожайность в этом году у клетки (пояс × пепельная зима).
func harvest_at(cell: int) -> float:
	return zone_harvest[climate_zone(cell)] if cell >= 0 else 1.0


## Новая «метка» для обхода (см. mark).
func next_stamp() -> int:
	_stamp += 1
	return _stamp


## Снимок статистики для графиков.
func record_history() -> void:
	if year % HISTORY_STEP != 0:
		return
	var races := PackedFloat32Array()
	races.resize(RaceDB.count())
	var snapshot := {}
	# Открытия по расам: среднее число технологий у государств расы.
	var techs := PackedFloat32Array()
	techs.resize(RaceDB.count())
	var counts := PackedFloat32Array()
	counts.resize(RaceDB.count())
	for n in nations:
		if not n.alive:
			continue
		for r in n.pop.size():
			races[r] += n.pop[r]
		snapshot[n.id] = PackedFloat32Array([n.population, n.cell_count])
		techs[n.race.index] += n.techs.size()
		counts[n.race.index] += 1.0
	for r in techs.size():
		if counts[r] > 0.0:
			techs[r] /= counts[r]
	# Распространение религий: в скольких регионах вера — вера большинства.
	var faiths := {}
	for region in regions:
		var f := region.main_faith()
		if f >= 0:
			faiths[f] = faiths.get(f, 0) + 1
	history.append({"year": year, "races": races, "nations": snapshot, "techs": techs, "faiths": faiths})


## Дата для интерфейса и летописи.
const MONTH_NAMES: Array[String] = ["Морозень", "Снеговей", "Капельник", "Цветень", "Травень", "Светлень",
	"Зноень", "Жатвень", "Листопад", "Дождень", "Стылень", "Студень"]


func date_text() -> String:
	return "%d %s, %d г." % [day + 1, MONTH_NAMES[month].to_lower(), year]


## Помечает погибшими государства без земли и вычищает их из дипломатии.
func cleanup_dead() -> void:
	if not _maybe_dead:
		return
	_maybe_dead = false
	for nation in nations:
		if nation.alive and nation.cell_count == 0:
			nation.alive = false
			RuinSystem.on_nation_fell(self, nation, nation.home_cell)
			nation.army = 0.0
			for id in nation.city_ids.duplicate():
				destroy_city(cities[id])
			diplomacy.forget_nation(self, nation.id)
			for hid in nation.hero_ids.duplicate():
				heroes[hid].leave_service(self)
			for c in caves:
				if c.owner == nation.id:
					c.owner = -1
					c.city = false
			log_event(&"fall", "Государство %s пало." % nation.name, PackedInt32Array([nation.id]))


## Дать имя ещё не заселённому региону (для знаковых мест в диких землях).
func ensure_region_name(region: Region) -> void:
	if region != null and region.name.is_empty():
		var races := RaceDB.all()
		region.name = NameGenerator.unique(used_names, NameGenerator.place_name.bind(races[rng.randi_range(0, races.size() - 1)], rng))


## Название региона клетки для текстов (безымянному даётся имя), иначе fallback.
func region_label(cell: int, fallback: String) -> String:
	var region := region_at(cell) if cell >= 0 else null
	if region == null:
		return fallback
	ensure_region_name(region)
	return region.name


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
	nation.territory_dirty = true
	cell_slot[cell] = nation.cells.size()
	nation.cells.append(cell)
	nation.sum_x += cell % map.width
	nation.sum_y += cell / map.width
	var base := cell * Goods.COUNT
	for g in Goods.COUNT:
		nation.yields[g] += cell_yield[base + g]


func _remove_cell(nation: Nation, cell: int) -> void:
	nation.territory_dirty = true
	var slot := cell_slot[cell]
	var last_index := nation.cells.size() - 1
	var last := nation.cells[last_index]
	nation.cells[slot] = last
	cell_slot[last] = slot
	nation.cells.resize(last_index)
	cell_slot[cell] = -1
	if last_index == 0:
		_maybe_dead = true
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
func found_nation(race: RaceDef, own_culture: bool = true) -> Nation:
	var nation := add_nation(race)
	nation.short_name = NameGenerator.unique(used_names, NameGenerator.place_name.bind(race, rng))
	var title := NameGenerator.state_title(race, nation.short_name, rng)
	nation.name = title[0]
	nation.ruler_title = title[1]
	nation.government = PoliticsDB.government(StringName(title[2]))
	new_ruler(nation, true)
	nation.color = nation_color(nation.id)
	if not religions.is_empty():
		nation.state_religion = ReligionSystem.pick_for_race(self, race)
	if own_culture:
		nation.culture = CultureSystem.new_culture(self, nation).id
	return nation


## Новый правитель: имя по языку расы, черта характера, возраст и срок правления.
## new_dynasty — к власти приходит новый род (иначе — наследник прежнего).
func new_ruler(nation: Nation, new_dynasty: bool) -> void:
	var race := nation.race
	if new_dynasty or nation.dynasty.is_empty():
		nation.dynasty = NameGenerator.unique(used_names, NameGenerator.root.bind(race, rng))
		nation.dynasty_names.clear()
	# Наследники нередко получают имя предка — так появляются «Эдрик II».
	var name := ""
	if not nation.dynasty_names.is_empty() and rng.randf() < 0.35:
		var names := nation.dynasty_names.keys()
		name = names[rng.randi_range(0, names.size() - 1)]
	else:
		name = NameGenerator.unique(used_names, NameGenerator.person_name.bind(race, rng))
	nation.dynasty_names[name] = nation.dynasty_names.get(name, 0) + 1
	nation.ruler_name = name
	nation.ruler_number = nation.dynasty_names[name]
	nation.ruler_trait = PoliticsDB.random_ruler_trait(rng)
	var gov := nation.government
	if gov != null and gov.succession == "eternal" or race.lifespan <= 0:
		# Бессмертные (нежить) правят, пока их не уничтожат.
		nation.ruler_age = rng.randi_range(50, 500)
		nation.reign_left = rng.randi_range(200, 700)
	elif gov != null and gov.succession == "election":
		nation.ruler_age = rng.randi_range(maxi(20, race.lifespan / 3), maxi(25, race.lifespan / 2))
		nation.reign_left = gov.election_period
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
		nation.home_cell = city.cell
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


func refresh_cell_yield(i: int) -> void:
	var def := BiomeDB.get_def(map.biome[i])
	for g in Goods.COUNT:
		cell_yield[i * Goods.COUNT + g] = def.yield_of(g)
	var dep := deposit_at(i)
	if dep != null:
		cell_yield[i * Goods.COUNT + Goods.index_of(dep.goods)] += dep.amount


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
	chronicle.append({"year": year, "month": month, "day": day, "kind": kind, "text": text, "nations": nation_ids})
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
