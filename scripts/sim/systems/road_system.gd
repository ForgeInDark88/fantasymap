class_name RoadSystem
extends RefCounted
## Дороги и торговые пути: граф между городами (World.roads, World.city_roads).
##
## Раз в год (в день государства) казна может проложить дорогу от одного из
## городов к ближайшему городу — своему или торгового партнёра: стоимость
## считается вдоль пути по рельефу (горы, болота, джунгли дороже, на реках —
## мосты), порты связываются морскими путями. Дорога приносит обоим концам
## торговый доход (больше — у крупных городов, короче и безопаснее путь),
## перекрёстки растут быстрее. Разбойники и пираты снижают безопасность,
## война перекрывает пути между врагами (блокада). Связанный дорогами со
## столицей регион лояльнее (меньше штраф за удалённость), а дорога к
## осаждаемому городу ускоряет осаду.

## Шанс в год заняться дорогами.
const BUILD_CHANCE := 0.35
## Дальше этого (в базовых клетках по прямой; × grid_scale) дорогу не тянут; морской путь — дальше.
## Длина дороги (Road.length) — тоже в базовых клетках.
const MAX_LAND := 34
const MAX_SEA := 70
## Не больше стольких дорог у одного города.
const MAX_PER_CITY := 4
## Цена пути: золото и камень за единицу длины (мост — ещё камень).
const GOLD_PER_LEN := 1.2
const STONE_PER_LEN := 0.5
const BRIDGE_STONE := 8.0
## Доход дороги в год: TRADE_K × √(жителей A × жителей B) / 1000 / (1 + длина / 25).
const TRADE_K := 1.2
## Стоимость шага по биомам (на воде сухопутной дороги нет).
const BIOME_COST := {Biome.PLAINS: 1.0, Biome.STEPPE: 1.0, Biome.FOREST: 1.6, Biome.JUNGLE: 2.5, Biome.SWAMP: 3.0,
	Biome.DESERT: 1.5, Biome.TUNDRA: 1.4, Biome.SNOW: 2.5, Biome.HILLS: 2.0, Biome.MOUNTAINS: 4.0}
## Восстановление безопасности в год и потери от пиратов.
const SAFETY_RECOVER := 0.06
const PIRATE_CHANCE := 0.03


## Раз в сколько лет пересчитывать дороги государства (со сдвигом по id):
## доход, восстановление безопасности и стройка — за весь период сразу.
const PERIOD := 2


func tick(world: World, nation: Nation) -> void:
	if (world.year + nation.id) % PERIOD != 0:
		return
	var rng := world.rng
	_trade(world, nation)
	if nation.city_ids.is_empty() or rng.randf() > BUILD_CHANCE * PERIOD:
		return
	# Город с наименьшим числом дорог (новые города сначала).
	var from: City = null
	for id in nation.city_ids:
		var c := world.cities[id]
		# Порту морской путь положен сверх лимита дорог.
		if world.city_roads.get(c.id, PackedInt32Array()).size() >= MAX_PER_CITY \
				and not (c.buildings.has(&"harbor") and not _has_sea_route(world, c.id)):
			continue
		if from == null or world.city_roads.get(c.id, PackedInt32Array()).size() < world.city_roads.get(from.id, PackedInt32Array()).size() \
				or (world.city_roads.get(c.id, PackedInt32Array()).size() == world.city_roads.get(from.id, PackedInt32Array()).size() and c.population > from.population):
			from = c
	if from == null:
		return
	var best: City = null
	var best_d := INF
	var sea := false
	var fp := world.map.cell_pos(from.cell)
	var port := from.buildings.has(&"harbor")
	# Порт без морского пути ищет заморского партнёра.
	var wants_sea := port and not _has_sea_route(world, from.id) and rng.randf() < 0.6
	var sea_best: City = null
	var sea_d := INF
	# Кандидаты: свои города, города торговых партнёров и (для порта) все порты мира.
	var candidates := PackedInt32Array(nation.city_ids)
	for p in nation.trade_partners:
		candidates.append_array(world.nations[p].city_ids)
	if port:
		candidates.append_array(_ports(world))
	for cid in candidates:
		var c := world.cities[cid]
		if not c.alive or c == from or _connected(world, from.id, c.id):
			continue
		var full: bool = world.city_roads.get(c.id, PackedInt32Array()).size() >= MAX_PER_CITY
		if full and not (c.buildings.has(&"harbor") and not _has_sea_route(world, c.id)):
			continue
		var d := Vector2(world.map.cell_pos(c.cell) - fp).length()
		# Морские пути — к любому мирному порту; сухопутные — к своим и торговым партнёрам.
		var foreign := c.nation_id != nation.id
		var by_sea := port and c.buildings.has(&"harbor") \
				and (not foreign or world.diplomacy.war_between(nation.id, c.nation_id) == null) and d <= world.gd(MAX_SEA)
		if by_sea and d > world.gd(8.0) and d < sea_d:
			sea_d = d
			sea_best = c
		if full or (foreign and not nation.trade_partners.has(c.nation_id)):
			continue
		if d > world.gd(MAX_LAND):
			continue
		if d < best_d:
			best_d = d
			best = c
	if wants_sea and sea_best != null:
		best = sea_best
		best_d = sea_d
		sea = true
	if best == null:
		return
	var path := measure(world, from.cell, best.cell) if not sea else Vector2(-1.0, 0.0)
	if path.x < 0.0:
		if not (port and best.buildings.has(&"harbor")):
			return
		sea = true
	var length := (best_d * 1.2 if sea else path.x) / world.grid_scale
	var bridges := 0 if sea else int(path.y)
	var gold := length * GOLD_PER_LEN
	var stone := (0.0 if sea else length * STONE_PER_LEN) + bridges * BRIDGE_STONE
	if nation.stock[Goods.GOLD] < gold + 40.0 or nation.stock[Goods.STONE] < stone:
		return
	nation.stock[Goods.GOLD] -= gold
	nation.stock[Goods.STONE] -= stone
	var road := build(world, from, best, sea, length, bridges)
	if from.tier() >= 2 and best.tier() >= 2 and world.rng.randf() < 0.35:
		world.log_event(&"trade", "%s прокладывает %s %s — %s%s." % [nation.name, "морской путь" if sea else "дорогу",
			from.name, best.name, (" (мостов: %d)" % bridges) if bridges > 0 else ""], PackedInt32Array([nation.id]))
	road.safety = 1.0


static func build(world: World, from: City, to: City, sea: bool, length: float, bridges: int) -> Road:
	var r := Road.new()
	r.id = world.roads.size()
	r.a = from.id
	r.b = to.id
	r.sea = sea
	r.length = length
	r.bridges = bridges
	r.built_year = world.year
	world.roads.append(r)
	world.road_version += 1
	for c in [from.id, to.id]:
		var list: PackedInt32Array = world.city_roads.get(c, PackedInt32Array())
		list.append(r.id)
		world.city_roads[c] = list
	return r


## Цена сухопутного пути по прямой (шаги по клеткам): x — длина, y — мостов; x < 0 — путь через воду.
static func measure(world: World, a: int, b: int) -> Vector2:
	var map := world.map
	var pa := map.cell_pos(a)
	var pb := map.cell_pos(b)
	var steps := maxi(absi(pb.x - pa.x), absi(pb.y - pa.y))
	var length := 0.0
	var bridges := 0
	var was_river := false
	for i in steps + 1:
		var t := float(i) / maxf(1.0, steps)
		var c := map.index_of(roundi(lerpf(pa.x, pb.x, t)), roundi(lerpf(pa.y, pb.y, t)))
		var biome := map.biome[c]
		if Biome.is_water(biome):
			return Vector2(-1.0, 0.0)
		length += BIOME_COST.get(biome, 1.5)
		var river := map.river[c] > 0
		if river and not was_river:
			bridges += 1
		was_river = river
	return Vector2(length, bridges)


## Торговля по дорогам городов государства: половина дохода дороги — каждому концу.
func _trade(world: World, nation: Nation) -> void:
	var rng := world.rng
	var income := 0.0
	# Враги (для блокады) — один раз, а не через war_between на каждую дорогу.
	var enemies := {}
	for war in world.diplomacy.wars_of(nation.id):
		for m in war.members(-war.side_of(nation.id)):
			enemies[m] = true
	for id in nation.city_ids:
		for rid in world.city_roads.get(id, PackedInt32Array()):
			var road := world.roads[rid]
			if not road.alive:
				continue
			var ca := world.cities[road.a]
			var cb := world.cities[road.b]
			if not ca.alive or not cb.alive:
				road.alive = false
				world.road_version += 1
				continue
			# Безопасность восстанавливается; пираты нападают на морские пути.
			if road.a == id:
				road.safety = minf(1.0, road.safety + SAFETY_RECOVER * PERIOD)
				if road.sea and rng.randf() < PIRATE_CHANCE * PERIOD:
					road.safety = maxf(0.1, road.safety - 0.4)
					if rng.randf() < 0.3:
						world.log_event(&"trade", "Пираты грабят корабли на пути %s — %s." % [ca.name, cb.name],
								PackedInt32Array([ca.nation_id, cb.nation_id]))
			# Блокада: путь между воюющими закрыт.
			var other_nation := cb.nation_id if ca.nation_id == nation.id else ca.nation_id
			if other_nation != nation.id and enemies.has(other_nation):
				road.traffic = 0.0
				continue
			var value := TRADE_K * sqrt(ca.population * cb.population) / 1000.0 / (1.0 + road.length / 25.0) * road.safety
			if road.sea:
				value *= 1.2 * nation.effect(&"naval_mult")
			road.traffic = value
			income += value * 0.5
	nation.stock[Goods.GOLD] += income * nation.policy("trade_mult") * PERIOD


## Порты мира (кэш на год: гавани строятся не каждый день).
static var _ports_cache := PackedInt32Array()
static var _ports_key := Vector3i(-1, -1, -1)


static func _ports(world: World) -> PackedInt32Array:
	var key := Vector3i(world.year, world.cities.size(), world.get_instance_id() & 0x7fffffff)
	if key != _ports_key:
		_ports_key = key
		_ports_cache.clear()
		for c in world.cities:
			if c.alive and c.buildings.has(&"harbor"):
				_ports_cache.append(c.id)
	return _ports_cache


static func _has_sea_route(world: World, city_id: int) -> bool:
	for rid in world.city_roads.get(city_id, PackedInt32Array()):
		if world.roads[rid].alive and world.roads[rid].sea:
			return true
	return false


static func _connected(world: World, a: int, b: int) -> bool:
	for rid in world.city_roads.get(a, PackedInt32Array()):
		var r := world.roads[rid]
		if r.alive and r.other(a) == b:
			return true
	return false


## Число живых дорог города (перекрёстки растут быстрее).
static func road_count(world: World, city_id: int) -> int:
	var n := 0
	for rid in world.city_roads.get(city_id, PackedInt32Array()):
		if world.roads[rid].alive:
			n += 1
	return n


## Города государства, связанные дорогами со столицей (своими дорогами).
static func linked_to_capital(world: World, nation: Nation) -> Dictionary:
	var seen := {}
	if nation.capital_city < 0:
		return seen
	var queue: Array[int] = [nation.capital_city]
	seen[nation.capital_city] = true
	while not queue.is_empty():
		var c: int = queue.pop_back()
		for rid in world.city_roads.get(c, PackedInt32Array()):
			var r := world.roads[rid]
			var o := r.other(c)
			if r.alive and not seen.has(o) and world.cities[o].nation_id == nation.id:
				seen[o] = true
				queue.append(o)
	return seen


## Ограбление дорог у города (злые герои, чудовища).
static func rob_roads(world: World, city_id: int, amount: float) -> void:
	for rid in world.city_roads.get(city_id, PackedInt32Array()):
		var r := world.roads[rid]
		r.safety = maxf(0.05, r.safety - amount)
