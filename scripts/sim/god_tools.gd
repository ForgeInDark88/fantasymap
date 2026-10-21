class_name GodTools
## Вмешательства игрока («панель Бога»). Чистые функции над World —
## интерфейс только выбирает инструмент и клетку.

## Создать государство расы race в регионе клетки. Ничья земля региона
## заселяется; если регион чей-то — он отделяется в новое государство.
static func create_nation(world: World, race: RaceDef, cell: int, announce: bool = true) -> Nation:
	var region := world.region_at(cell)
	if region == null:
		return null
	var owner := world.owner[cell]
	var nation: Nation
	if owner >= 0:
		nation = world.split_off(world.nations[owner], PackedInt32Array([region.id]), race)
		if not nation.alive:
			return null
	else:
		nation = world.found_nation(race)
		for c in region.cells:
			if world.owner[c] == -1:
				world.set_owner(c, nation.id)
		if nation.cell_count == 0:
			nation.alive = false
			return null
		nation.pop[race.index] = nation.capacity[race.index] * 0.4
		nation.stock[Goods.WOOD] = 40.0
		nation.stock[Goods.STONE] = 20.0
		nation.stock[Goods.GOLD] = 80.0
		nation.stock[Goods.FOOD] = nation.population / 1000.0
		nation.army = nation.population * 0.03 * race.military
		nation.stability = 0.8
	if nation.capital_city < 0:
		var site := cell if world.owner[cell] == nation.id and world.can_place_city(cell) else region.center
		if world.owner[site] == nation.id and world.city_cell[site] < 0:
			var city := world.add_city(nation, site, race, true)
			city.population = maxf(800.0, nation.population * 0.08)
	if announce:
		world.log_event(&"nation", "По воле богов в регионе %s возникло государство %s (%s)." % [
			region.name, nation.name, race.display_name], PackedInt32Array([nation.id]))
	return nation


static func trigger_event(world: World, simulation: Simulation, event: EventDef, cell: int) -> bool:
	var nation := world.nation_at(cell)
	if nation == null or event == null:
		return false
	# Боги не ждут удачного случая: событие происходит без условий о населении.
	var saved_min := event.min_population
	event.min_population = 0.0
	var ok := simulation.events.apply(world, nation, event)
	event.min_population = saved_min
	return ok


static func declare_war(world: World, attacker: int, target: int) -> War:
	if attacker < 0 or target < 0 or attacker == target:
		return null
	var d := world.diplomacy
	if d.war_between(attacker, target) != null:
		return null
	d.pair(attacker, target).truce_until = -1
	var war := d.declare_war(world, attacker, target, &"divine")
	world.log_event(&"war", "По воле богов %s объявляет войну государству %s." % [
		world.nations[attacker].name, world.nations[target].name], PackedInt32Array([attacker, target]))
	return war


static func spawn_hero(world: World, cell: int) -> Hero:
	var nation := world.nation_at(cell)
	var region := world.region_at(cell)
	if nation == null or region == null:
		return null
	return HeroSystem.spawn(world, nation, region, true)


## Поднять мятеж в регионе клетки: народ региона провозглашает своё государство.
static func incite_rebellion(world: World, cell: int) -> Nation:
	var region := world.region_at(cell)
	var owner := world.owner[cell]
	if region == null or owner < 0:
		return null
	var old := world.nations[owner]
	var people := world.region_majority_race(region, owner)
	var race := RaceDB.by_index(people) if people != World.NO_RACE else old.race
	var rebel := world.split_off(old, PackedInt32Array([region.id]), race)
	if not rebel.alive:
		return null
	world.log_event(&"rebellion", "По наущению богов регион %s восстаёт против %s: провозглашено %s." % [
		region.name, old.short_name, rebel.name], PackedInt32Array([old.id, rebel.id]))
	world.diplomacy.declare_war(world, rebel.id, old.id, &"independence")
	return rebel


## Поднять (delta > 0) или опустить (delta < 0) землю кистью радиуса radius.
## Возвращает true, если что-то изменилось (рендеру нужно перерисовать карту).
static func reshape(world: World, cell: int, radius: int, delta: float) -> bool:
	var map := world.map
	var center := map.cell_pos(cell)
	var changed := false
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := center.x + dx
			var y := center.y + dy
			if not map.in_bounds(x, y):
				continue
			var d := sqrt(float(dx * dx + dy * dy))
			if d > radius + 0.5:
				continue
			var i := map.index_of(x, y)
			var amount := delta * (1.0 - d / (radius + 1.0))
			# Вода «поднимается» быстрее, чтобы остров вырос за несколько кликов.
			if map.elevation[i] < 0.0 and delta > 0.0:
				amount *= 2.5
			if set_elevation(world, i, map.elevation[i] + amount):
				changed = true
	if changed:
		world.ownership_version += 1
		world.terrain_version += 1
	return changed


## Меняет высоту клетки и всё, что от неё зависит: биом, воду/сушу, регион,
## добычу, владельца (ушедшая под воду земля теряет хозяина и город).
static func set_elevation(world: World, i: int, e: float) -> bool:
	var map := world.map
	e = clampf(e, -1.0, 1.0)
	var was_land := map.is_land(i)
	var will_land := e >= 0.0
	if is_equal_approx(e, map.elevation[i]):
		return false
	if world.region_of[i] >= 0:
		world.goods_dirty[world.region_of[i]] = true
	var owner := world.owner[i]
	if owner >= 0:
		world.set_owner(i, -1)
	map.elevation[i] = e
	# Рельеф (и стоимость пути) сменился; суша ↔ вода — и морские пути (Pathfinder).
	world.terrain_version += 1
	if was_land != will_land:
		world.coast_version += 1
		world.coast_cells.append(i)
	if will_land:
		map.biome[i] = MapGenerator.classify_land(e, map.temperature[i], map.moisture[i])
		if not was_land:
			map.river[i] = 0
			_attach_to_region(world, i)
			world.owner_texels[i * 4 + 2] = 255
	else:
		map.biome[i] = Biome.SEA
		map.river[i] = 0
		for r in world.ruins:
			if r.cell == i:
				r.cell = -1  # руины ушли под воду
		world.cell_race[i] = World.NO_RACE
		world.deposit[i] = 0
		if was_land:
			_detach_from_region(world, i)
			world.owner_texels[i * 4 + 2] = 0
	world.refresh_cell_yield(i)
	if will_land and owner >= 0:
		world.set_owner(i, owner)
	return true


static func _attach_to_region(world: World, i: int) -> void:
	var rid := -1
	for nb in world.map.neighbors4(i):
		if world.region_of[nb] >= 0:
			rid = world.region_of[nb]
			break
	if rid < 0:
		# Новый остров — новый регион.
		var region := Region.new()
		region.id = world.regions.size()
		region.center = i
		region.coastal = true
		world.regions.append(region)
		rid = region.id
	var cells := world.regions[rid].cells
	cells.insert(cells.bsearch(i), i)  # клетки региона держим упорядоченными
	world.region_of[i] = rid
	var v := rid + 1
	world.region_texels[i * 4] = v & 0xff
	world.region_texels[i * 4 + 1] = (v >> 8) & 0xff


static func _detach_from_region(world: World, i: int) -> void:
	var rid := world.region_of[i]
	if rid >= 0:
		var region := world.regions[rid]
		var idx := region.cells.find(i)
		if idx >= 0:
			region.cells.remove_at(idx)
		if region.center == i and not region.cells.is_empty():
			region.center = region.cells[0]
	world.region_of[i] = -1
	world.region_texels[i * 4] = 0
	world.region_texels[i * 4 + 1] = 0


## Озарение: текущее исследование завершается мгновенно (или открывается доступная технология).
static func insight(world: World, nation: Nation) -> TechDef:
	var t := TechDB.find(nation.researching) if nation.researching != &"" else null
	if t == null:
		for res in TechDB.all():
			if TechSystem.is_available(nation, res as TechDef):
				t = res
				break
	if t == null:
		return null
	TechSystem.unlock(world, nation, t, "")
	world.log_event(&"tech", "Озарение свыше: учёные государства %s постигли %s." % [nation.name, t.display_name.to_lower()],
			PackedInt32Array([nation.id]))
	return t


## Слияние культур: регион клетки перенимает культуру своего владельца.
static func assimilate(world: World, cell: int) -> bool:
	var region := world.region_at(cell)
	var o := world.owner[cell]
	if region == null or o < 0 or world.nations[o].culture < 0 or region.culture == world.nations[o].culture:
		return false
	CultureSystem.assimilate(world, world.nations[o], region)
	return true


## Дорога от ближайшего к клетке города к ближайшему другому городу (даром).
static func road_from(world: World, cell: int) -> Road:
	var pos := Vector2(world.map.cell_pos(cell))
	var from: City = null
	for c in world.cities:
		if c.alive and (from == null or pos.distance_squared_to(Vector2(world.map.cell_pos(c.cell))) < pos.distance_squared_to(Vector2(world.map.cell_pos(from.cell)))):
			from = c
	if from == null:
		return null
	var fp := Vector2(world.map.cell_pos(from.cell))
	var to: City = null
	for c in world.cities:
		if c.alive and c != from and not RoadSystem._connected(world, from.id, c.id) \
				and (to == null or fp.distance_squared_to(Vector2(world.map.cell_pos(c.cell))) < fp.distance_squared_to(Vector2(world.map.cell_pos(to.cell)))):
			to = c
	if to == null:
		return null
	var path := RoadSystem.measure(world, from.cell, to.cell)
	var sea := path.x < 0.0
	var length := (fp.distance_to(Vector2(world.map.cell_pos(to.cell))) * 1.2 if sea else path.x) / world.grid_scale
	var road := RoadSystem.build(world, from, to, sea, length, 0 if sea else int(path.y))
	world.log_event(&"trade", "По воле богов %s связала %s и %s." % ["морская тропа" if sea else "дорога", from.name, to.name],
			PackedInt32Array([from.nation_id, to.nation_id]))
	return road


## Извержение ближайшего вулкана (до 15 клеток) или новой горы-вулкана под курсором.
static func eruption(world: World, cell: int) -> bool:
	var pos := Vector2(world.map.cell_pos(cell))
	var best := -1
	for v in world.volcanoes:
		if Vector2(world.map.cell_pos(v)).distance_to(pos) <= world.gd(15.0) and (best < 0 or Vector2(world.map.cell_pos(v)).distance_to(pos) < Vector2(world.map.cell_pos(best)).distance_to(pos)):
			best = v
	if best < 0:
		if world.map.biome[cell] != Biome.MOUNTAINS and world.map.biome[cell] != Biome.HILLS:
			return false
		world.volcanoes.append(cell)
		best = cell
	ClimateSystem.erupt(world, best)
	return true


## Засуха в климатическом поясе клетки.
static func drought(world: World, cell: int) -> void:
	var z := world.climate_zone(cell)
	world.zone_events[z] = {"kind": "drought", "until": world.year + 3}
	world.zone_harvest[z] = ClimateSystem.DROUGHT_HARVEST
	world.scars.append({"cell": cell, "radius": 8.0, "kind": "drought", "until": world.year + 3})
	world.log_event(&"climate", "По воле богов %s пришла великая сушь." % ClimateSystem.ZONE_NAMES[z])


## Древние руины по воле Бога: храм забытых богов в клетке.
static func ancient_ruin(world: World, cell: int) -> Ruin:
	var name := "Руины %s" % NameGenerator.place_name(RaceDB.all()[world.rng.randi_range(0, RaceDB.count() - 1)], world.rng)
	var r := RuinSystem.add(world, &"temple", cell, name, "древнее святилище, поднятое из небытия (%d г.)" % world.year)
	if r != null:
		r.wealth *= 2.0
		world.log_event(&"ruins", "Земля разверзлась в регионе %s: открылись древние руины — %s." % [world.region_label(cell, "диких землях"), name])
	return r


# --- Этап 10.1: артефакты, боги, роды, ордена ---

## Ближайший к клетке живой герой-странник (не дальше max_dist клеток).
static func nearest_hero(world: World, cell: int, max_dist: float = 25.0) -> Hero:
	var p := Vector2(world.map.cell_pos(cell))
	var best: Hero = null
	var best_d := max_dist
	for h in world.wandering_heroes():
		if h.alive and h.cell >= 0:
			var d := p.distance_to(Vector2(world.map.cell_pos(h.cell)))
			if d < best_d:
				best_d = d
				best = h
	return best


## Даровать артефакт: ближайшему герою, иначе в сокровищницу владельца, иначе — лежит в земле.
static func gift_artifact(world: World, def: ArtifactDef, cell: int) -> Artifact:
	if def == null or not world.map.is_land(cell):
		return null
	var hero := nearest_hero(world, cell)
	var a := ArtifactSystem.create(world, def.id, null, "", "явлен по воле богов")
	if hero != null:
		ArtifactSystem.give(world, a, hero, "дарован богами")
		hero.add_deed(world, "получил от богов %s" % a.name)
		world.log_event(&"artifact", "По воле богов герою %s явлен предмет — %s." % [hero.display_name(), a.name])
	elif world.owner[cell] >= 0:
		ArtifactSystem.to_treasury(world, a, world.nations[world.owner[cell]], "явлен по воле богов")
		world.log_event(&"artifact", "По воле богов в сокровищнице %s явилась реликвия — %s." % [world.nations[world.owner[cell]].name, a.name],
				PackedInt32Array([world.owner[cell]]))
	else:
		ArtifactSystem.drop(world, a, cell)
		world.log_event(&"artifact", "По воле богов в краю %s скрыт предмет — %s. Кто найдёт его?" % [world.region_label(cell, "диких земель"), a.name])
	return a


## Милость бога державе под клеткой.
static func bless(world: World, god: GodDef, cell: int) -> bool:
	var o := world.owner[cell]
	if god == null or o < 0:
		return false
	GodSystem.grant_boon(world, world.nations[o], god)
	return true


## Бог избирает ближайшего героя.
static func choose_hero(world: World, god: GodDef, cell: int) -> Hero:
	var hero := nearest_hero(world, cell)
	if god == null or hero == null:
		return null
	GodSystem.make_chosen(world, hero, god)
	return hero


## Дитя героев: у ближайшего героя (с супругом — общее, иначе находится пара рядом) рождается ребёнок.
static func hero_child(world: World, cell: int) -> Dictionary:
	var hero := nearest_hero(world, cell)
	if hero == null:
		return {}
	var other: Hero = world.heroes[hero.spouse] if hero.spouse >= 0 and world.heroes[hero.spouse].alive else null
	if other == null:
		for h in world.wandering_heroes():
			if h != hero and h.alive and h.spouse < 0 and h.race == hero.race:
				other = h
				break
		if other == null:
			return {}
		hero.spouse = other.id
		other.spouse = hero.id
		world.log_event(&"lineage", "По воле богов герои %s и %s сочетались браком." % [hero.display_name(), other.display_name()])
	return LineageSystem.birth(world, hero, other)


## Ближайший герой основывает орден.
static func found_order(world: World, cell: int) -> HeroOrder:
	var hero := nearest_hero(world, cell)
	return OrderSystem.found(world, hero) if hero != null else null


# --- Этап 11.B: армии и флоты ---

static func nearest_army(world: World, cell: int, max_dist: float = 25.0, kind: StringName = &"") -> Army:
	var p := Vector2(world.map.cell_pos(cell))
	var best: Army = null
	var best_d := max_dist
	for a in world.armies:
		if a.alive and a.cell >= 0 and (kind == &"" or a.kind == kind):
			var d := p.distance_to(Vector2(world.map.cell_pos(a.cell)))
			if d < best_d:
				best_d = d
				best = a
	return best


## Создать армию владельца клетки (в его первой войне или гарнизоном) — в регионе клетки.
static func create_army(world: World, cell: int, kind: StringName = &"land") -> Army:
	var o := world.owner[cell]
	if o < 0 or world.region_of[cell] < 0:
		return null
	var n := world.nations[o]
	var wars := world.diplomacy.wars_of(o)
	n.army += 3000.0
	# Воля Бога: войско появляется прямо в выбранной клетке (допустимый телепорт — со вспышкой).
	var a := ArmySystem.create(world, n, wars[0].id if not wars.is_empty() else -1, kind, world.region_of[cell], cell)
	a.state = &"idle"
	MovementSystem.log_teleport(world, MoveDB.teleport(&"god"), cell, a.cell)
	world.log_event(&"battle", "По воле богов %s собирает %s в регионе %s." % [n.name, "флот" if kind == &"fleet" else "новое войско",
		world.region_label(cell, "диких земель")], PackedInt32Array([o]))
	return a


static func destroy_army(world: World, cell: int) -> bool:
	var a := nearest_army(world, cell)
	if a == null:
		return false
	if a.nation >= 0:
		var n := world.nations[a.nation]
		n.army -= n.army * a.share * 0.6
	world.log_event(&"battle", "Гнев богов обрушился на войско: %s уничтожена." % a.label(world),
			PackedInt32Array([a.nation]) if a.nation >= 0 else PackedInt32Array())
	ArmySystem.disband(world, a)
	return true


static func launch_fleet(world: World, cell: int) -> Army:
	var o := world.owner[cell]
	if o < 0:
		return null
	var n := world.nations[o]
	for id in n.city_ids:
		if world.cities[id].buildings.has(&"harbor"):
			return create_army(world, world.cities[id].cell, &"fleet")
	return null


## Бунт армии: войско восстаёт, его край провозглашает свою державу.
static func mutiny(world: World, cell: int) -> Nation:
	var a := nearest_army(world, cell, 25.0, &"land")
	if a == null or a.nation < 0:
		return null
	var n := world.nations[a.nation]
	var rebels := incite_rebellion(world, a.cell)
	if rebels == null:
		return null
	var defect := n.army * a.share * 0.5
	n.army -= defect
	rebels.army += defect
	ArmySystem.disband(world, a)
	world.log_event(&"battle", "Войско государства %s подняло бунт и перешло на сторону мятежников — %s." % [n.name, rebels.name],
			PackedInt32Array([n.id, rebels.id]))
	return rebels


## Дикий мир (этап 11.C): племя в ничейном крае клетки.
static func spawn_tribe(world: World, cell: int) -> Tribe:
	return TribeSystem.spawn(world, null, cell)


## Логово (или великое чудовище) в крае клетки; вид — по биому края.
static func spawn_lair(world: World, cell: int, great: bool) -> Lair:
	var region := world.region_at(cell)
	if region == null:
		return null
	var biome := BiomeDB.get_def(world.map.biome[region.center]).id
	var pick: LairDef = null
	for d in LairDB.all():
		var def: LairDef = d
		if def.great == great and def.biomes.has(biome):
			pick = def
			break
	if pick == null:
		for d in LairDB.all():
			if (d as LairDef).great == great:
				pick = d
				break
	return LairSystem.spawn(world, pick, cell)


static func start_disease(world: World, cell: int, def: DiseaseDef) -> Outbreak:
	if world.region_of[cell] < 0:
		return null
	return DiseaseSystem.start(world, def, world.region_of[cell])


## Новое наречие языка края (и соседних краёв того же языка у того же владельца).
static func split_dialect(world: World, cell: int) -> int:
	var region := world.region_at(cell)
	if region == null or region.language < 0:
		return -1
	var ids := PackedInt32Array([region.id])
	for nb in region.neighbors:
		var r := world.regions[nb]
		if r.language == region.language and r.controller() == region.controller() and ids.size() < 4:
			ids.append(nb)
	var parent := region.language
	var id := LanguageSystem.new_dialect(world, parent, ids)
	world.log_event(&"language", "По воле богов в крае %s заговорили по-новому: %s (от: %s)." % [region.name,
		LanguageSystem.title(world, id), LanguageSystem.title(world, parent)])
	return id


## Рынок (этап 11.D): караван от ближайшего к клетке города — самым выгодным товаром.
static func send_caravan(world: World, cell: int) -> Caravan:
	var city := _nearest_city(world, cell)
	if city == null or city.nation_id < 0:
		return null
	var nation := world.nations[city.nation_id]
	MarketSystem.ensure(world, nation)
	var best: Array = []
	for rid in world.city_roads.get(city.id, PackedInt32Array()):
		var road := world.roads[rid]
		var other := world.cities[road.other(city.id)]
		if not road.alive or not other.alive or other.nation_id == nation.id or other.nation_id < 0:
			continue
		var o := world.nations[other.nation_id]
		MarketSystem.ensure(world, o)
		for i in MarketDB.size():
			if nation.market_stock[i] < 1.0:
				continue
			var margin := o.market_price[i] / maxf(0.001, nation.market_price[i])
			if best.is_empty() or margin > best[0]:
				best = [margin, road, other.id, i]
	if best.is_empty():
		return null
	var i: int = best[3]
	return CaravanSystem.launch(world, best[1], city.id, best[2], i, nation.market_stock[i] * 0.5, nation.market_price[i])


static func spawn_mercs(world: World, cell: int) -> MercCompany:
	var m := MercSystem.spawn(world, _nearest_city(world, cell))
	if m != null:
		world.log_event(&"mercs", "У города %s собралась вольная %s." % [world.cities[world.city_cell[m.cell]].name if world.city_cell[m.cell] >= 0 else "?", m.name.to_lower()])
	return m


static func gold_rush(world: World, cell: int) -> bool:
	var n := world.nation_at(cell)
	if n == null:
		return false
	n.stock[Goods.GOLD] += maxf(500.0, n.population / 1000.0 * 4.0)
	world.log_event(&"debt", "В землях государства %s нашли богатые россыпи — золотая лихорадка!" % n.short_name, PackedInt32Array([n.id]))
	return true


static func toggle_slavery(world: World, cell: int) -> bool:
	var n := world.nation_at(cell)
	if n == null:
		return false
	n.slavery = not n.slavery
	world.log_event(&"society", ("%s по воле богов вводит рабство." if n.slavery else "%s по воле богов отменяет рабство.") % n.name,
		PackedInt32Array([n.id]))
	return true


static func forgive_debts(world: World, cell: int) -> int:
	var n := world.nation_at(cell)
	if n == null:
		return 0
	var before := world.loans.size()
	world.loans = world.loans.filter(func(l: Dictionary) -> bool: return int(l.debtor) != n.id)
	var k := before - world.loans.size()
	if k > 0:
		world.log_event(&"debt", "Долги государства %s прощены по воле богов (займов: %d)." % [n.short_name, k], PackedInt32Array([n.id]))
	return k


static func _nearest_city(world: World, cell: int) -> City:
	var p := Vector2(world.map.cell_pos(cell))
	var best: City = null
	var best_d := 30.0
	for c in world.cities:
		if c.alive:
			var d := p.distance_to(Vector2(world.map.cell_pos(c.cell)))
			if d < best_d:
				best_d = d
				best = c
	return best


## Дипломатия (этап 11.E): другой характер правителей.
static func change_personality(world: World, cell: int) -> PersonalityDef:
	var n := world.nation_at(cell)
	if n == null:
		return null
	DealSystem.ensure_personality(world, n)
	var all := PersonalityDB.all()
	var next: PersonalityDef = all[(all.find(n.personality) + 1) % all.size()]
	n.personality = next
	n.personality_ruler = n.ruler_name
	n.set_effects(&"personality", {"aggression_mult": next.aggression})
	world.log_event(&"deal", "По воле богов у государства %s новый нрав: %s." % [n.short_name, next.display_name.to_lower()], PackedInt32Array([n.id]))
	return next


static func false_rumor(world: World, cell: int) -> Dictionary:
	var n := world.nation_at(cell)
	if n == null:
		return {}
	return RumorSystem.spread(world, &"weak", n, null, -1, false)


static func move_capital(world: World, cell: int) -> bool:
	var id := world.city_cell[cell]
	if id < 0:
		var c := _nearest_city(world, cell)
		id = c.id if c != null else -1
	if id < 0:
		return false
	var city := world.cities[id]
	if city.nation_id < 0 or city.is_capital:
		return false
	var n := world.nations[city.nation_id]
	if n.capital_city >= 0:
		world.cities[n.capital_city].is_capital = false
	city.is_capital = true
	n.capital_city = city.id
	n.capital_year = world.year
	world.log_event(&"capital", "По воле богов %s переносит столицу в город %s." % [n.name, city.name], PackedInt32Array([n.id]))
	return true


## Государство from предлагает государству to первую возможную сделку.
static func force_deal(world: World, simulation: Simulation, from: int, to: int) -> bool:
	if from < 0 or to < 0 or from == to or not world.nations[from].alive or not world.nations[to].alive:
		return false
	for kind in DealSystem.KINDS:
		var offer := simulation.deals._offer(world, kind, world.nations[from], world.nations[to])
		if not offer.is_empty():
			return DealSystem.propose(world, offer)
	DealSystem.journal(world, &"none", from, to, false, "%s и %s: сделать нечего." % [world.nations[from].short_name, world.nations[to].short_name])
	return false
