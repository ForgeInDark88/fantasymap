class_name CaravanSystem
extends RefCounted
## Караваны (этап 11.D): товар идёт по дороге или морскому пути (RoadSystem)
## месяц за месяцем. Небезопасная дорога (Road.safety: разбойники, пираты,
## набеги) может стоить каравана; дорога, перерезанная войной, — тоже. Дошедший
## караван кладёт товар на рынок получателя; пошлины — казнам обеих сторон.
## Ход — раз в месяц в «свой» день каравана.

## Шанс в месяц потерять караван на дороге с безопасностью 0 (× (1 − safety)).
const ROB_CHANCE := 0.2


static func launch(world: World, road: Road, from_city: int, to_city: int, good: int, amount: float, price: float) -> Caravan:
	var from := world.cities[from_city]
	var to := world.cities[to_city]
	var nation := world.nations[from.nation_id]
	var c := Caravan.new()
	c.id = world.caravans.size()
	c.road = road.id
	c.from_city = from_city
	c.to_city = to_city
	c.from_nation = from.nation_id
	c.to_nation = to.nation_id
	c.good = good
	c.amount = amount
	c.price = price
	c.months = 1 + int(road.length / 18.0) + (1 if road.sea else 0)
	c.day = world.rng.randi_range(0, Simulation.DAYS - 1)
	nation.market_stock[good] -= amount
	nation.market_out[good] += amount
	nation.stock[Goods.GOLD] += amount * price * MarketSystem.EXPORT_DUTY
	world.caravans.append(c)
	world.count(&"caravans")
	return c


## Товары в пути (для учёта рынка).
static func in_transit(world: World) -> float:
	var sum := 0.0
	for c in world.caravans:
		if c.alive:
			sum += c.amount
	return sum


var _days: Array = []
var _days_key := Vector3i(-1, -1, -1)


func tick_day(world: World) -> void:
	if world.caravans.is_empty():
		return
	var key := Vector3i(world.get_instance_id() % 1000000007, world.caravans.size(), world.year * 12 + world.month)
	if key != _days_key:
		_days_key = key
		_days = WildDays.bucket(world.caravans)
	for c in _days[world.day]:
		if c.alive:
			_month(world, c)
	# Раз в месяц — уплотнение списка (дошедшие и разграбленные уходят).
	if world.day == Simulation.DAYS - 1:
		var keep: Array[Caravan] = []
		for c in world.caravans:
			if c.alive:
				c.id = keep.size()
				keep.append(c)
		world.caravans = keep


func _month(world: World, c: Caravan) -> void:
	var road: Road = world.roads[c.road] if c.road >= 0 and c.road < world.roads.size() else null
	var to := world.nations[c.to_nation] if c.to_nation >= 0 else null
	# Дорога пропала или между сторонами война — товар потерян.
	if road == null or not road.alive or to == null or not to.alive or world.diplomacy.war_between(c.from_nation, c.to_nation) != null:
		_lose(world, c, false)
		return
	if world.rng.randf() < (1.0 - road.safety) * ROB_CHANCE:
		_lose(world, c, true)
		return
	c.done += 1
	if c.done < c.months:
		return
	c.alive = false
	MarketSystem.ensure(world, to)
	to.market_stock[c.good] += c.amount
	to.market_in[c.good] += c.amount
	to.stock[Goods.GOLD] += c.amount * c.price * MarketSystem.IMPORT_DUTY
	world.market_totals["delivered"] = float(world.market_totals.get("delivered", 0.0)) + c.amount
	world.count(&"caravans_arrived")


static func _lose(world: World, c: Caravan, robbed: bool) -> void:
	c.alive = false
	c.robbed = robbed
	world.market_totals["robbed"] = float(world.market_totals.get("robbed", 0.0)) + c.amount
	world.count(&"caravans_robbed")
	var value := c.amount * c.price
	if robbed and value > 150.0 and world.rng.randf() < 0.3:
		var g: GoodDef = MarketDB.all()[c.good]
		world.log_event(&"caravan", "Разбойники разграбили караван с товаром «%s» на пути %s → %s." % [g.display_name,
			world.cities[c.from_city].name, world.cities[c.to_city].name], PackedInt32Array([c.from_nation, c.to_nation]))
