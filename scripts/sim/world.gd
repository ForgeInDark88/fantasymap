class_name World
extends "res://scripts/sim/world_territory.gd"
## Полное состояние мира: карта + государства + города + принадлежность клеток.
##
## Это «модель» симуляции: никакой отрисовки, никаких нод. Рендер читает
## owner_texels, интерфейс — списки nations/cities и летопись. Все изменения
## владельцев клеток проходят через set_owner(): он поддерживает списки клеток
## государств, их добычу, ёмкость земли и переселяет жителей вместе с клеткой.
## Части: WorldData (поля) → WorldGeo (география, добыча, климат) →
## WorldTerritory (владение клетками, границы, регионы, города) → World.


## Полный цикл создания мира: карта + стартовые государства. Синхронно —
## WorldState вызывает это в фоновом потоке, тесты — напрямую.
static func create(s: MapSettings) -> World:
	var world := World.new(MapGenerator.new().generate(s))
	WorldSeeder.new().seed_world(world)
	ClimateSystem.place_volcanoes(world)
	UndergroundSystem.generate(world)
	LanguageSystem.seed_world(world)
	TribeSystem.seed_world(world)
	LairSystem.seed_world(world)
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
