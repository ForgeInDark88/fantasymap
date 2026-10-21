class_name PirateSystem
extends RefCounted
## Пираты (этап 11.B): флоты без государства у морских путей. Появляются у
## портов на морских дорогах, грабят казну порта и делают морские пути
## опасными, переходят от порта к порту; держава с сильным флотом их топит.
## Пират — Army вида &"pirates" (nation = -1), срок — state_until.

const MAX := 4
const SPAWN_CHANCE := 0.03
const STRENGTH := Vector2(1500.0, 6000.0)
## Сколько лет живёт пиратская вольница.
const YEARS := Vector2i(5, 15)
## Шанс в месяц грабежа и переезда к другому порту.
const RAID_CHANCE := 0.5
const MOVE_CHANCE := 0.3
const NAMES := ["Чёрный флаг", "Вольные кормчие", "Братство Прибоя", "Морские волки", "Красные паруса", "Сыны Шторма"]


static func pirates(world: World) -> Array[Army]:
	var res: Array[Army] = []
	for a in world.armies:
		if a.alive and a.kind == &"pirates":
			res.append(a)
	return res


## Порты на морских путях (id городов).
static func _sea_ports(world: World) -> PackedInt32Array:
	var res := PackedInt32Array()
	for road in world.roads:
		if road.alive and road.sea:
			for cid in [road.a, road.b]:
				var c := world.cities[cid]
				if c.alive and not res.has(cid):
					res.append(cid)
	return res


static func spawn(world: World, city: City) -> Army:
	var a := Army.new()
	a.id = world.armies.size()
	a.kind = &"pirates"
	a.nation = -1
	a.war = -1
	a.own_strength = world.rng.randf_range(STRENGTH.x, STRENGTH.y)
	a.region = world.region_of[city.cell]
	a.cell = city.cell
	a.state = &"idle"
	a.created_year = world.year
	a.state_until = world.year + world.rng.randi_range(YEARS.x, YEARS.y)
	a.target = city.id
	world.armies.append(a)
	world.log_event(&"pirates", "У берегов города %s подняли чёрный флаг пираты — «%s»." % [city.name,
		NAMES[world.rng.randi_range(0, NAMES.size() - 1)]], PackedInt32Array([city.nation_id]))
	world.count(&"pirates")
	return a


## Раз в месяц: появление, грабёж, переезд, гибель от флотов держав.
static func tick_month(world: World) -> void:
	var rng := world.rng
	var list := pirates(world)
	var born := list.size() < MAX and rng.randf() < SPAWN_CHANCE
	if list.is_empty() and not born:
		return
	var ports := _sea_ports(world)  # один раз на месяц
	if born:
		if not ports.is_empty():
			spawn(world, world.cities[ports[rng.randi_range(0, ports.size() - 1)]])
	for p in pirates(world):
		if world.year >= p.state_until:
			p.alive = false
			if rng.randf() < 0.3:
				world.log_event(&"pirates", "Пиратская вольница у края %s распалась." % world.region_label(p.cell, "моря"))
			continue
		var city: City = world.cities[p.target] if p.target >= 0 and p.target < world.cities.size() else null
		if city == null or not city.alive:
			_move(world, p, ports)
			continue
		var nation := world.nations[city.nation_id]
		# Держава с флотом (гаванью) бьёт пиратов, если сильнее.
		var navy := nation.army * ArmySystem.FLEET_SHARE * nation.effect(&"naval_mult") * (1.5 if city.buildings.has(&"shipyard") else 1.0)
		if city.buildings.has(&"harbor") and navy > p.own_strength * 1.2 and rng.randf() < 0.25:
			p.alive = false
			nation.army -= p.own_strength * 0.1
			world.log_event(&"pirates", "Флот государства %s потопил пиратов у города %s." % [nation.short_name, city.name], PackedInt32Array([nation.id]))
			world.count(&"pirates_sunk")
			continue
		if rng.randf() < RAID_CHANCE:
			var loot := minf(maxf(0.0, nation.stock[Goods.GOLD]) * 0.05, 150.0)
			nation.stock[Goods.GOLD] -= loot
			p.own_strength += loot * 2.0
			RoadSystem.rob_roads(world, city.id, 0.3)
			if rng.randf() < 0.04:
				world.log_event(&"pirates", "Пираты разорили гавань города %s (%s)." % [city.name, nation.short_name], PackedInt32Array([nation.id]))
		if rng.randf() < MOVE_CHANCE:
			_move(world, p, ports)


static func _move(world: World, p: Army, ports: PackedInt32Array) -> void:
	if ports.is_empty():
		p.alive = false
		return
	var city := world.cities[ports[world.rng.randi_range(0, ports.size() - 1)]]
	p.target = city.id
	p.region = world.region_of[city.cell]
	p.cell = city.cell
