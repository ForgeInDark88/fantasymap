class_name SettlerSystem
extends RefCounted
## Поселенцы (этап 12.C): когда державе тесно (давление населения) и влияние
## упёрлось в свой предел, из ближнего к выбранному месту города уходят люди —
## пешком к краю влияния (деревня) или, если по суше расти некуда, из своей
## гавани морем к ничьему берегу (колония). Идут по карте (профиль «settler»);
## рядом с чудовищами и кочевниками на них могут напасть, вражеское войско —
## перехватить. Дошли — основывают поселение (InfluenceSystem.found).

## Наибольшее число групп в пути у державы: 1 + города / 3.
const PER_CITIES := 3
## Шанс решиться в год (при прочих условиях).
const CHANCE := 0.35
## Шанс в год отправить колонистов за море (когда по суше расти некуда).
const COLONY_CHANCE := 0.15
## Сколько мест на фронте рассмотреть.
const SAMPLES := 16
## Город отдаёт поселенцев, только если в нём жителей не меньше cost_pop + это.
const MIN_CITY_POP := 400.0
## Дольше в пути — рассеялись.
const MAX_DAYS := 720
## Опасность в пути проверяется раз в столько суток.
const DANGER_DAYS := 30
## Вражеское войско ближе (базовых клеток) — перехват.
const CATCH_RANGE := 2


## Решение державы в её год (из InfluenceSystem.tick).
func consider(world: World, nation: Nation, pressure: float) -> void:
	if pressure < 0.5 or nation.city_ids.is_empty():
		return
	var heap := nation.frontier
	if heap == null:
		return
	var out := 0
	for s in world.settlers:
		if s.alive and s.nation == nation.id:
			out += 1
	if out >= 1 + nation.city_ids.size() / PER_CITIES:
		return
	# Свободная земля в пределах влияния ещё есть — сначала её.
	var free_in_reach := false
	while not heap.is_empty() and world.owner[heap.top_item()] != -1:
		heap.pop()
	if not heap.is_empty() and heap.top_priority() <= 0.0:
		free_in_reach = true
	if free_in_reach or world.rng.randf() > CHANCE:
		return
	var site := _land_site(world, nation, heap)
	var kind := &"village"
	if site < 0:
		# За море — как прежние колонии: долго некуда расти, тесно, и не каждый год.
		if nation.stalled_years < 5 or pressure < 0.75 or world.rng.randf() > COLONY_CHANCE:
			return
		site = _sea_site(world, nation)
		kind = &"colony"
	if site < 0:
		return
	var def := SettlementDB.find(kind)
	if nation.stock[Goods.GOLD] < def.cost_gold or nation.stock[Goods.WOOD] < def.cost_wood:
		return
	var from := _from_city(world, nation, site, def.cost_pop, kind == &"colony")
	if from == null:
		return
	var s := Settler.new()
	s.nation = nation.id
	s.from_city = from.id
	s.target = site
	s.kind = kind
	s.people = def.cost_pop
	s.reason = &"crowded" if pressure > 0.85 else &"land"
	s.m = Mover.new(from.cell, &"settler")
	s.m.nation = nation.id
	s.born = ArmySystem.today(world)
	if not MovementSystem.send(world, s.m, site, PackedInt32Array([nation.id])):
		return
	nation.stock[Goods.GOLD] -= def.cost_gold
	nation.stock[Goods.WOOD] -= def.cost_wood
	# Люди уходят из державы в дорогу (и вернутся в её число — на новой земле).
	var ri := nation.race.index
	var people := minf(def.cost_pop, nation.pop[ri] * 0.5)
	nation.pop[ri] -= people
	s.people = people
	from.population = maxf(1.0, from.population - people)
	s.id = world.settlers.size()
	world.settlers.append(s)
	world.count(&"settlers_sent")


## Лучшее место у края влияния: ничья клетка фронта чуть дальше предела.
## Дешёвые проверки — у всех проб, дорогие (удалённость от других поселений и
## от идущих поселенцев) — по убыванию оценки, пока одно место не подойдёт.
func _land_site(world: World, nation: Nation, heap: MinHeap) -> int:
	var size := heap.size()
	if size == 0:
		return -1
	var cands: Array[Vector2] = []  # (оценка, клетка)
	for k in SAMPLES:
		var i := world.rng.randi_range(0, size - 1)
		var c := heap.item_at(i)
		if heap.priority_at(i) <= 0.0 or world.owner[c] != -1 or not world.map.is_land(c) or not world.can_place_city(c):
			continue
		var score := world.site_score(nation.race, c) - heap.priority_at(i) * 0.05
		if world.map.river[c] > 0 or world.deposit[c] > 0:
			score += 0.2
		cands.append(Vector2(score, c))
	# По убыванию оценки; при равной — меньшая клетка (порядок не зависит от сортировки).
	cands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x or (a.x == b.x and a.y < b.y))
	for v in cands:
		var c := int(v.y)
		if InfluenceSystem.site_ok(world, c) and not _taken(world, c):
			return c
	return -1


## Ничейный прибрежный край за морем (как прежние колонии ExpansionSystem).
func _sea_site(world: World, nation: Nation) -> int:
	var ports := PackedInt32Array()
	for id in nation.city_ids:
		var city := world.cities[id]
		if city.buildings.has(&"harbor"):
			ports.append(city.cell)
	if ports.is_empty():
		return -1
	var map := world.map
	var max_range := map.width * 0.4 * nation.effect(&"naval_mult")
	var best := -1
	var best_score := -INF
	for s in 40:
		var region := world.regions[world.rng.randi_range(0, world.regions.size() - 1)]
		if not region.owner_counts.is_empty() or not region.coastal or region.cells.size() < world.gai(15):
			continue
		var center := Vector2(map.cell_pos(region.center))
		var dist := INF
		for port in ports:
			dist = minf(dist, center.distance_to(Vector2(map.cell_pos(port))))
		if dist > max_range or not InfluenceSystem.site_ok(world, region.center) or _taken(world, region.center):
			continue
		var score := world.site_score(nation.race, region.center) - dist / max_range
		if score > best_score:
			best_score = score
			best = region.center
	return best


## Туда уже идут другие поселенцы.
static func _taken(world: World, cell: int) -> bool:
	var p := world.map.cell_pos(cell)
	var r := world.gdi(InfluenceSystem.SPACING)
	for s in world.settlers:
		if s.alive:
			var q := world.map.cell_pos(s.target)
			if maxi(absi(p.x - q.x), absi(p.y - q.y)) < r:
				return true
	return false


## Ближний к месту город, где хватает жителей (за море — только гавань).
func _from_city(world: World, nation: Nation, site: int, cost: float, harbor: bool) -> City:
	var p := world.map.cell_pos(site)
	var best: City = null
	var best_d := 1 << 30
	for id in nation.city_ids:
		var city := world.cities[id]
		if not city.alive or city.population < cost + MIN_CITY_POP or (harbor and not city.buildings.has(&"harbor")):
			continue
		var q := world.map.cell_pos(city.cell)
		var d := maxi(absi(p.x - q.x), absi(p.y - q.y))
		if d < best_d:
			best_d = d
			best = city
	return best


func tick_day(world: World) -> void:
	if world.settlers.is_empty():
		return
	var today := ArmySystem.today(world)
	var any_dead := false
	for s in world.settlers:
		if not s.alive:
			any_dead = true
			continue
		var nation := world.nations[s.nation]
		var o := world.owner[s.target]
		if not nation.alive or today - s.born > MAX_DAYS or (o != -1 and o != s.nation):
			_lose(world, s, &"scattered")
			any_dead = true
			continue
		MovementSystem.advance(world, s.m)
		if s.m.arrived or (not s.m.walking() and s.cell == s.target):
			s.alive = false
			any_dead = true
			_arrive(world, s, nation)
			continue
		if not s.m.walking():
			# Путь пропал (земля изменилась) — пробуем заново, иначе расходятся.
			if not MovementSystem.send(world, s.m, s.target, PackedInt32Array([s.nation])):
				_lose(world, s, &"scattered")
				any_dead = true
			continue
		if (today - s.born) % DANGER_DAYS == DANGER_DAYS - 1 and _danger(world, s):
			any_dead = true
	if any_dead:
		var keep: Array[Settler] = []
		for s in world.settlers:
			if s.alive:
				s.id = keep.size()
				keep.append(s)
		world.settlers = keep


## Нападения в пути: чудовища и кочевники рядом (как засады на караваны),
## вражеское войско — перехват. true — группа погибла.
func _danger(world: World, s: Settler) -> bool:
	var p := world.map.cell_pos(s.cell)
	var reach := world.gdi(CATCH_RANGE)
	for a in world.armies:
		if a.alive and a.nation >= 0 and a.nation != s.nation and a.kind == &"land" \
				and world.diplomacy.war_between(a.nation, s.nation) != null:
			var q := world.map.cell_pos(a.cell)
			if maxi(absi(p.x - q.x), absi(p.y - q.y)) <= reach:
				_lose(world, s, &"caught")
				return true
	if world.rng.randf() < CaravanSystem.danger_at(world, s.cell):
		_lose(world, s, &"ambush")
		return true
	return false


func _lose(world: World, s: Settler, why: StringName) -> void:
	s.alive = false
	world.count(StringName("settlers_" + str(why)))
	if why != &"scattered" and s.nation >= 0 and world.nations[s.nation].alive:
		var n := world.nations[s.nation]
		var what := "перехватило вражеское войско" if why == &"caught" else "перебили в пути чудовища или кочевники"
		world.log_event(&"settle", "Поселенцев державы %s %s." % [n.short_name, what], PackedInt32Array([n.id]))
	elif why == &"scattered" and s.nation >= 0 and world.nations[s.nation].alive:
		# Рассеялись — люди вернулись в державу.
		world.nations[s.nation].pop[world.nations[s.nation].race.index] += s.people


func _arrive(world: World, s: Settler, nation: Nation) -> void:
	var st := InfluenceSystem.found(world, nation, s.kind, s.target, s.people)
	if st == null:
		nation.pop[nation.race.index] += s.people
		return
	var from := world.cities[s.from_city].name if s.from_city < world.cities.size() else "?"
	var region := world.region_at(s.target)
	var where := region.name if region != null and not region.name.is_empty() else "новых землях"
	if s.kind == &"colony":
		# Колония за морем сразу ставит городок (как прежде) — он и держит берег.
		if world.can_place_city(s.target) and world.city_cell[s.target] < 0:
			var city := world.add_city(nation, s.target, nation.race, false)
			city.population = maxf(300.0, s.people)
			st.alive = false
			nation.stalled_years = 0
			InfluenceSystem.add_source(world, nation, city.cell, InfluenceSystem.city_reach(world, nation, city))
			world.log_event(&"colony", "%s основывает за морем колонию %s в краю %s (поселенцы из %s)." % [
				nation.name, city.name, where, from], PackedInt32Array([nation.id]))
			return
	world.log_event(&"settle", "Поселенцы из %s основали деревню %s в краю %s." % [from, st.name, where],
			PackedInt32Array([nation.id]))
