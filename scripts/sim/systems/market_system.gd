class_name MarketSystem
extends RefCounted
## Рынок и общество (этап 11.D). Поверх прежних ресурсов (еда, дерево, камень,
## металл, золото) — товары рынка (data/goods): у каждого государства свой
## рынок с запасами и ценами.
##   • Производство — от земель (по краям: биомы, побережье, реки,
##     месторождения; кэш World.region_goods), × заселённость, × рабский труд;
##     ремесло (оружие) — из металла.
##   • Спрос — у сословий (знать, горожане, крестьяне, рабы) и армии.
##   • Учёт за год: запас + произведённое → потреблено (не больше спроса),
##     остаток портится (spoil) и идёт в запас. Караваны (CaravanSystem)
##     вывозят и ввозят. В итоге по миру: произведено = потреблено + прирост
##     запасов + испорчено + в пути + разграблено (tests/economy_test.gd).
##   • Цена — от спроса и предложения × индекс цен (инфляция: золота больше,
##     чем «держит» хозяйство, — цены растут, реальные налоги падают).
##   • Сословия дрейфуют (торговля и города растят горожан, рабство — рабов);
##     рабство отменяют республики и просвещённые, вводят воинственные;
##     восстания рабов. Итог — эффекты государства (&"market"): налоги,
##     производство, стабильность, сила армии (кони, оружие).
## Ход — раз в год в «свой» день государства (после экономики).

const CLASS_IDS: Array[StringName] = [&"nobles", &"burghers", &"peasants", &"slaves"]
const CLASS_NAMES := ["знать", "горожане", "крестьяне", "рабы"]
const NOBLES := 0
const BURGHERS := 1
const PEASANTS := 2
const SLAVES := 3
## Пошлины (доля стоимости товара в казну): вывоз — отправителю, ввоз — получателю.
const EXPORT_DUTY := 0.12
const IMPORT_DUTY := 0.06
## Караванов от государства за год и всего в пути по миру.
const CARAVANS_PER_NATION := 3
const MAX_CARAVANS := 200
## Караван выходит, если там дороже хотя бы во столько раз.
const TRADE_MARGIN := 1.3


## Массивы рынка нужного размера; первая инициализация — цены по базе, рабство по нравам.
static func ensure(world: World, nation: Nation) -> void:
	var n := MarketDB.size()
	if nation.market_price.size() == n:
		return
	var fresh := nation.market_price.is_empty()
	# Packed-массивы — значения: размер задаётся каждому полю отдельно.
	nation.market_stock.resize(n)
	nation.market_made.resize(n)
	nation.market_used.resize(n)
	nation.market_out.resize(n)
	nation.market_in.resize(n)
	nation.market_lost.resize(n)
	nation.market_demand.resize(n)
	var old := nation.market_price.size()
	nation.market_price.resize(n)
	for i in range(old, n):
		nation.market_price[i] = (MarketDB.all()[i] as GoodDef).base_price
	if fresh:
		var harsh := nation.race.has_trait(&"raiders") or nation.race.has_trait(&"demonic") or nation.race.has_trait(&"feared")
		var gov := nation.government.id if nation.government != null else &""
		nation.slavery = harsh or gov == &"necrocracy" or (gov in [&"empire", &"clans"] and world.rng.randf() < 0.4)


## Товары краёв (на весь край, единиц в год при полной заселённости): кэш —
## производное от карты; при смене биомов и рельефа пересчитываются только
## затронутые края (World.goods_dirty), при смене числа краёв — все.
static func region_goods(world: World) -> Array:
	var n := MarketDB.size()
	# Новые края (остров из пучины) — досчитать только их.
	if not world.region_goods.is_empty() and world.region_goods.size() < world.regions.size() \
			and (world.region_goods[0] as PackedFloat32Array).size() == n:
		for rid in range(world.region_goods.size(), world.regions.size()):
			world.region_goods.append(_goods_of(world, world.regions[rid]))
	if world.region_goods.size() != world.regions.size() or (not world.region_goods.is_empty() and (world.region_goods[0] as PackedFloat32Array).size() != n):
		world.region_goods.resize(world.regions.size())
		for region in world.regions:
			world.region_goods[region.id] = _goods_of(world, region)
		world.goods_dirty.clear()
	elif not world.goods_dirty.is_empty():
		for rid in world.goods_dirty:
			if rid < world.regions.size():
				world.region_goods[rid] = _goods_of(world, world.regions[rid])
		world.goods_dirty.clear()
	return world.region_goods


static func _goods_of(world: World, region: Region) -> PackedFloat32Array:
	var goods := MarketDB.all()
	var n := goods.size()
	var deposits := EconomyDB.deposits()
	var v := PackedFloat32Array()
	v.resize(n)
	for c in region.cells:
		var bid := BiomeDB.get_def(world.map.biome[c]).id
		var river := world.map.river[c] > 0
		var dep := world.deposit[c]
		for i in n:
			var g: GoodDef = goods[i]
			var x: float = g.biomes.get(bid, 0.0)
			if river:
				x += g.river
			if dep > 0 and g.deposit != &"" and deposits[dep - 1].id == g.deposit:
				x += g.deposit_amount
			v[i] += x
	if region.coastal:
		for i in n:
			v[i] += (goods[i] as GoodDef).coastal * region.cells.size() * 0.35
	return v


func tick(world: World, nation: Nation) -> void:
	ensure(world, nation)
	var goods := MarketDB.all()
	var n := goods.size()
	var rg := region_goods(world)
	var cap := 0.0
	for c in nation.capacity:
		cap += c
	var occupancy := clampf(nation.population / maxf(1.0, cap), 0.15, 1.2)
	var slaves := nation.classes[SLAVES]
	var work := (0.85 + minf(nation.tech, 40.0) * 0.005) * (1.0 + slaves * 0.6)
	var pop_k := nation.population / 1000.0
	var army_k := nation.army / 1000.0
	var staple_sum := 0.0
	var staple_n := 0
	var lux_sum := 0.0
	var lux_n := 0
	var mil_sum := 0.0
	var mil_n := 0
	var totals := world.market_totals
	# Земли: края по очереди, в каждом — все товары (доля края у государства).
	var land := PackedFloat32Array()
	land.resize(n)
	for rid in nation.region_counts:
		var k := float(nation.region_counts[rid]) / maxf(1.0, float(world.regions[rid].cells.size()))
		var v: PackedFloat32Array = rg[rid]
		for i in n:
			land[i] += v[i] * k
	for i in n:
		var g: GoodDef = goods[i]
		var made := land[i] * occupancy * work
		if g.crafted_from != &"":
			made += maxf(0.0, nation.income[Goods.index_of(g.crafted_from)]) * g.craft_ratio
		var demand := army_k * g.army_demand
		for k in 4:
			demand += pop_k * nation.classes[k] * float(g.demand.get(CLASS_IDS[k], 0.0))
		var avail := nation.market_stock[i] + made
		var used := minf(demand, avail)
		var rest := avail - used
		var lost := rest * g.spoil
		nation.market_stock[i] = rest - lost
		nation.market_made[i] = made
		nation.market_used[i] = used
		nation.market_lost[i] = lost
		nation.market_demand[i] = demand
		totals["made"] = float(totals.get("made", 0.0)) + made
		totals["used"] = float(totals.get("used", 0.0)) + used
		totals["lost"] = float(totals.get("lost", 0.0)) + lost
		# Цена: спрос к предложению (запас считается вполовину) × индекс цен.
		var ratio := (demand + 0.5) / (made + nation.market_stock[i] * 0.5 + 0.5)
		var target := g.base_price * nation.inflation * clampf(pow(ratio, 0.7), 0.3, 4.0)
		nation.market_price[i] = lerpf(nation.market_price[i], target, 0.5)
		var sat := used / demand if demand > 0.001 else 1.0
		if g.staple:
			staple_sum += sat
			staple_n += 1
		if g.luxury and demand > 0.001:
			lux_sum += sat
			lux_n += 1
		if g.military and demand > 0.001:
			mil_sum += sat
			mil_n += 1
	_society(world, nation)
	_inflation(nation, pop_k)
	var staple := staple_sum / maxf(1.0, float(staple_n))
	var lux := lux_sum / float(lux_n) if lux_n > 0 else 0.5
	var mil := mil_sum / float(mil_n) if mil_n > 0 else 0.5
	nation.set_effects(&"market", {
		"trade_mult": 1.0 + (nation.classes[BURGHERS] - 0.15),
		"production_mult": 1.0 + nation.classes[SLAVES] * 0.4,
		"stability": 0.03 * (staple - 0.85) + 0.01 * (lux - 0.5) - nation.classes[SLAVES] * 0.1,
		"army_mult": 0.95 + 0.08 * mil,
	})
	# Вывоз и ввоз — за год: ввоз копился с прошлого хода, вывоз — караваны этого хода.
	for i in n:
		nation.market_out[i] = 0.0
		nation.market_in[i] = 0.0
	_launch_caravans(world, nation)


## Сословия, рабство, восстания рабов.
func _society(world: World, nation: Nation) -> void:
	var rng := world.rng
	var gov := nation.government.id if nation.government != null else &""
	var urban := 0.0
	for id in nation.city_ids:
		urban += world.cities[id].population
	urban /= maxf(1.0, nation.population)
	var roads := 0
	for id in nation.city_ids:
		roads += world.city_roads.get(id, PackedInt32Array()).size()
	var nobles := 0.07 if gov == &"oligarchy" else (0.05 if gov in [&"monarchy", &"empire", &"theocracy"] else 0.03)
	var burghers := clampf(0.06 + urban * 0.5 + minf(roads, 20) * 0.004, 0.04, 0.4)
	var slaves := 0.0
	if nation.slavery:
		slaves = 0.06 + (0.06 if nation.race.has_trait(&"raiders") or nation.race.has_trait(&"warlike") else 0.0) \
				+ (0.04 if not world.diplomacy.wars_of(nation.id).is_empty() else 0.0)
	var target := PackedFloat32Array([nobles, burghers, maxf(0.1, 1.0 - nobles - burghers - slaves), slaves])
	var sum := 0.0
	for k in 4:
		nation.classes[k] = lerpf(nation.classes[k], target[k], 0.1)
		sum += nation.classes[k]
	for k in 4:
		nation.classes[k] /= sum
	# Рабство: отменяют республики и просвещённые; вводят воинственные на войне.
	if nation.slavery and (gov == &"republic" or nation.tech > 18.0 or nation.race.has_trait(&"peaceful")) and rng.randf() < 0.03:
		nation.slavery = false
		world.count(&"abolitions")
		world.log_event(&"society", "%s отменяет рабство: невольники становятся крестьянами." % nation.name, PackedInt32Array([nation.id]))
	elif not nation.slavery and (nation.race.has_trait(&"warlike") or nation.race.has_trait(&"raiders")) \
			and not world.diplomacy.wars_of(nation.id).is_empty() and rng.randf() < 0.02:
		nation.slavery = true
		world.log_event(&"society", "%s обращает пленных в рабов." % nation.name, PackedInt32Array([nation.id]))
	if nation.classes[SLAVES] > 0.08 and nation.stability < 0.4 and rng.randf() < 0.15:
		nation.stability = maxf(0.0, nation.stability - 0.08)
		nation.army = maxf(0.0, nation.army * 0.95)
		nation.classes[PEASANTS] += nation.classes[SLAVES] * 0.5
		nation.classes[SLAVES] *= 0.5
		world.count(&"slave_revolts")
		world.log_event(&"society", "Восстание рабов в государстве %s: невольники бегут с полей и рудников." % nation.name,
			PackedInt32Array([nation.id]))


## Индекс цен: золота в казне больше, чем «держит» хозяйство, — цены растут.
static func _inflation(nation: Nation, pop_k: float) -> void:
	var economy := pop_k * 0.3 + 10.0
	var ratio := maxf(0.0, nation.stock[Goods.GOLD]) / (economy * 15.0)
	var target := clampf(0.9 + ratio * 0.3, 0.9, 2.5)
	nation.inflation = lerpf(nation.inflation, target, 0.08)


## Караваны: товар, что у соседа по дороге заметно дороже, — туда.
func _launch_caravans(world: World, nation: Nation) -> void:
	if world.caravans.size() >= MAX_CARAVANS:
		return
	var goods := MarketDB.all()
	var offers: Array = []
	for cid in nation.city_ids:
		for rid in world.city_roads.get(cid, PackedInt32Array()):
			var road := world.roads[rid]
			if not road.alive:
				continue
			var other_city := world.cities[road.other(cid)]
			if not other_city.alive or other_city.nation_id == nation.id or other_city.nation_id < 0:
				continue
			var other := world.nations[other_city.nation_id]
			if not other.alive or other.market_price.size() != goods.size() or world.diplomacy.war_between(nation.id, other.id) != null:
				continue
			for i in goods.size():
				var surplus := nation.market_stock[i] - nation.market_demand[i] * 0.3
				if surplus <= 1.0:
					continue
				var margin := other.market_price[i] / maxf(0.001, nation.market_price[i])
				if margin >= TRADE_MARGIN:
					offers.append([margin, rid, cid, other_city.id, i, surplus])
	if offers.is_empty():
		return
	offers.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var sent := 0
	var used := {}
	for o in offers:
		if sent >= CARAVANS_PER_NATION or world.caravans.size() >= MAX_CARAVANS:
			break
		var key := Vector2i(o[1], o[4])
		if used.has(key):
			continue
		used[key] = true
		var i: int = o[4]
		var other := world.nations[world.cities[o[3]].nation_id]
		var want := maxf(1.0, other.market_demand[i] - other.market_stock[i])
		var amount := minf(float(o[5]) * 0.4, want)
		if amount < 0.5 or nation.market_stock[i] < amount:
			continue
		CaravanSystem.launch(world, world.roads[o[1]], o[2], o[3], i, amount, nation.market_price[i])
		sent += 1


## Главный товар края (для режима «Товары»): индекс или -1.
static func main_good(world: World, region_id: int) -> int:
	var rg := region_goods(world)
	if region_id < 0 or region_id >= rg.size():
		return -1
	var v: PackedFloat32Array = rg[region_id]
	var best := -1
	var best_value := 0.0
	var goods := MarketDB.all()
	for i in v.size():
		var value := v[i] * (goods[i] as GoodDef).base_price
		if value > best_value:
			best_value = value
			best = i
	return best


## Средние по миру цены (для статистики и окна «Рынок»).
static func world_prices(world: World) -> PackedFloat32Array:
	var n := MarketDB.size()
	var sum := PackedFloat32Array()
	sum.resize(n)
	var count := 0
	for nation in world.nations:
		if nation.alive and nation.market_price.size() == n:
			count += 1
			for i in n:
				sum[i] += nation.market_price[i]
	for i in n:
		sum[i] = sum[i] / count if count > 0 else (MarketDB.all()[i] as GoodDef).base_price
	return sum
