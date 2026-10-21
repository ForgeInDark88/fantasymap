class_name TribeSystem
extends RefCounted
## Племена и кочевники (этап 11.C): народы без государства в ничейных краях
## (data/tribes). Оседлые племена растут на месте; кочевники бродят по
## ничейным краям и набегают на соседей. Окрепшие кочевники собираются в
## орду: орда грабит сильнее, отнимает край у слабого соседа или, найдя
## свободную землю, оседает и основывает государство — тем же путём, что и
## государства мира (World.found_nation, GodTools.create_nation).
## Государство, пришедшее в край племени, вбирает его (жители и воины) или
## вытесняет к соседям.
##
## Ход: каждое племя — раз в месяц в «свой» день (Tribe.day), рождение — раз в год.

## Сколько ничейных краёв на одно племя (предел числа племён) и шанс рождения в год.
const REGIONS_PER_TRIBE := 16
const MAX_TRIBES := 20
const SPAWN_CHANCE := 0.25
## Предел силы племени (воинов) и доля силы, уходящая в набег.
const MAX_STRENGTH := 30000.0
const RAID_SHARE := 0.03
## Шанс кочевникам перейти в соседний край за месяц.
const MOVE_CHANCE := 0.25
## Орда: набеги чаще, захват края у слабого соседа.
const HORDE_RAID_MULT := 2.5
const HORDE_CONQUER_CHANCE := 0.002
## Шанс в месяц, что окрепшая орда осядет и основывает государство.
const FOUND_CHANCE := 0.003
## Орда, не осевшая за столько лет, распадается обратно на кочевья.
const HORDE_YEARS := 30


## Племена при создании мира: в ничейных краях подходящих биомов.
static func seed_world(world: World) -> void:
	var wild := _wild_regions(world)
	var n := mini(MAX_TRIBES, maxi(2, wild.size() / (REGIONS_PER_TRIBE * 2)))
	for i in n:
		spawn(world, null, -1)


static func alive_tribes(world: World) -> Array[Tribe]:
	var res: Array[Tribe] = []
	for t in world.tribes:
		if t.alive:
			res.append(t)
	return res


static func _wild_regions(world: World) -> Array[Region]:
	var res: Array[Region] = []
	for r in world.regions:
		if r.cells.size() >= 4 and r.owner_counts.is_empty():
			res.append(r)
	return res


static func _biome_id(world: World, cell: int) -> StringName:
	return BiomeDB.get_def(world.map.biome[cell]).id


## Новое племя вида def (null — случайный) в крае клетки cell (-1 — подходящий ничейный край).
static func spawn(world: World, def: TribeDef, cell: int) -> Tribe:
	var rng := world.rng
	var region: Region = null
	if cell >= 0:
		region = world.region_at(cell)
		if region == null or not region.owner_counts.is_empty():
			return null
	if def == null:
		def = _pick_def(world, region)
	if def == null:
		return null
	if region == null:
		var wild := _wild_regions(world)
		if wild.is_empty():
			return null
		# Несколько случайных проб: лучше край любимого биома и без других племён.
		var best_score := -1.0
		for k in 12:
			var r: Region = wild[rng.randi_range(0, wild.size() - 1)]
			var score := rng.randf() + (2.0 if def.biomes.has(_biome_id(world, r.center)) else 0.0) - (3.0 if tribe_in(world, r.id) != null else 0.0)
			if score > best_score:
				best_score = score
				region = r
	var race := RaceDB.get_race(def.race)
	if race == null:
		return null
	var t := Tribe.new()
	t.id = world.tribes.size()
	t.def = def
	t.race = race
	t.name = NameGenerator.place_name(race, rng)
	t.region = region.id
	t.cell = region.center
	t.strength = rng.randf_range(def.strength.x, def.strength.y)
	t.born = world.year
	t.day = rng.randi_range(0, Simulation.DAYS - 1)
	world.tribes.append(t)
	world.count(&"tribes")
	if world.year > 0:
		world.log_event(&"tribe", "В диком крае %s объявились %s — «%s» (%s)." % [_rname(region), def.display_name.to_lower(),
			t.label(), race.display_name])
	return t


static func _pick_def(world: World, region: Region) -> TribeDef:
	var total := 0.0
	var defs: Array[TribeDef] = []
	var weights: Array[float] = []
	for d in TribeDB.all():
		var def: TribeDef = d
		var w := def.weight
		if region != null:
			w *= 3.0 if def.biomes.has(_biome_id(world, region.center)) else 0.3
		defs.append(def)
		weights.append(w)
		total += w
	if defs.is_empty():
		return null
	var roll := world.rng.randf() * total
	for i in defs.size():
		roll -= weights[i]
		if roll <= 0.0:
			return defs[i]
	return defs[defs.size() - 1]


static func tribe_in(world: World, region_id: int) -> Tribe:
	for t in world.tribes:
		if t.alive and t.region == region_id:
			return t
	return null


static func _rname(region: Region) -> String:
	return region.name if not region.name.is_empty() else "без имени"


## Племена по «своим» дням месяца — пересобираются при изменении списка (и раз в год).
var _days: Array = []
var _days_key := Vector3i(-1, -1, -1)


## Каждый день — племена «этого» дня.
func tick_day(world: World) -> void:
	var key := Vector3i(world.get_instance_id() % 1000000007, world.tribes.size(), world.year)
	if key != _days_key:
		_days_key = key
		_days = WildDays.bucket(world.tribes)
	for t in _days[world.day]:
		if t.alive:
			_month(world, t)


## Раз в год: рождение племён и уплотнение списка.
func tick_year(world: World) -> void:
	var wild := 0
	for r in world.regions:
		if r.cells.size() >= 4 and r.owner_counts.is_empty():
			wild += 1
	var limit := mini(MAX_TRIBES, wild / REGIONS_PER_TRIBE)
	if alive_tribes(world).size() < limit and world.rng.randf() < SPAWN_CHANCE:
		spawn(world, null, -1)
	var keep: Array[Tribe] = []
	for t in world.tribes:
		if t.alive:
			t.id = keep.size()
			keep.append(t)
	world.tribes = keep


func _month(world: World, t: Tribe) -> void:
	var rng := world.rng
	var region := world.regions[t.region]
	# Государство пришло в край племени: вобрать или вытеснить.
	if not region.owner_counts.is_empty():
		_meet_state(world, t, region)
		if not t.alive:
			return
		region = world.regions[t.region]
	var cap := minf(MAX_STRENGTH, 1500.0 + region.cells.size() * 120.0 * (2.0 if t.horde else 1.0))
	t.strength = minf(cap, t.strength * (1.0 + t.def.growth / 12.0))
	var chance := t.def.raid_chance * (HORDE_RAID_MULT if t.horde else 1.0)
	if rng.randf() < chance:
		_raid(world, t, region)
	if not t.def.nomad:
		return
	# Кочевники собираются в орду.
	if t.horde and world.year - t.horde_year > HORDE_YEARS:
		t.horde = false
		t.strength *= 0.4
		world.log_event(&"tribe", "%s распалась: роды разошлись по степям." % t.def.horde_name.replace("{name}", t.name))
	if not t.horde and t.strength >= t.def.horde_strength and world.year - t.horde_year > HORDE_YEARS:
		t.horde = true
		t.horde_year = world.year
		world.count(&"hordes")
		world.log_event(&"tribe", "Кочевые роды сошлись в крае %s: %s ищет новых пастбищ и добычи." % [_rname(region), t.label()])
	if t.horde:
		if t.strength >= t.def.found_strength and region.cells.size() >= 8 and rng.randf() < FOUND_CHANCE:
			_found_state(world, t, region)
			return
		if rng.randf() < HORDE_CONQUER_CHANCE and _conquer(world, t, region):
			return
	if rng.randf() < MOVE_CHANCE:
		_wander(world, t, region)


## Соседний ничейный край (любимый биом — чаще); нет — стоять.
func _wander(world: World, t: Tribe, region: Region) -> void:
	var options := PackedInt32Array()
	for nb in region.neighbors:
		var r := world.regions[nb]
		if r.cells.size() >= 4 and r.owner_counts.is_empty() and tribe_in(world, nb) == null:
			options.append(nb)
			if t.def.biomes.has(_biome_id(world, r.center)):
				options.append(nb)
	if options.is_empty():
		return
	var to := options[world.rng.randi_range(0, options.size() - 1)]
	t.region = to
	t.cell = world.regions[to].center


## Набег на государство соседнего края: золото, люди, воины; сильный сосед отбивается.
func _raid(world: World, t: Tribe, region: Region) -> void:
	var rng := world.rng
	var targets := PackedInt32Array()
	for nb in region.neighbors:
		var c := world.regions[nb].controller()
		if c >= 0 and not targets.has(c):
			targets.append(c)
	if targets.is_empty():
		return
	var n := world.nations[targets[rng.randi_range(0, targets.size() - 1)]]
	if not n.alive:
		return
	var force := t.strength * RAID_SHARE * (3.0 if t.horde else 1.0)
	t.raids += 1
	if n.power() * 0.15 > force * (1.0 + rng.randf()):
		t.strength *= 0.9
		if t.horde and rng.randf() < 0.3:
			world.log_event(&"tribe", "Государство %s отбило набег — %s отступает." % [n.short_name, t.label()], PackedInt32Array([n.id]))
		return
	var loot := minf(maxf(0.0, n.stock[Goods.GOLD]) * 0.04, force * 0.05)
	n.stock[Goods.GOLD] -= loot
	n.army = maxf(0.0, n.army - force * 0.2)
	n.stability = maxf(0.0, n.stability - (0.004 if t.horde else 0.0))
	var share := 0.004 if t.horde else 0.001
	for r in n.pop.size():
		n.pop[r] *= 1.0 - share
	t.strength += force * 0.1
	world.count(&"tribe_raids")
	if t.horde or rng.randf() < 0.06:
		world.log_event(&"tribe", "Набег на земли государства %s: %s." % [n.short_name, t.label()], PackedInt32Array([n.id]))


## Государство заняло край племени: сильное — вбирает народ и воинов, слабое — племя уходит.
func _meet_state(world: World, t: Tribe, region: Region) -> void:
	var n := world.nations[region.controller()]
	if n.power() * 0.5 > t.strength or not t.def.nomad:
		var free := PackedInt32Array()
		for nb in region.neighbors:
			if world.regions[nb].owner_counts.is_empty() and world.regions[nb].cells.size() >= 4 and tribe_in(world, nb) == null:
				free.append(nb)
		# Оседлые сильнее держатся за землю: слабое государство не может их вобрать — они уходят.
		if not t.def.nomad and n.power() * 0.5 <= t.strength and not free.is_empty():
			t.region = free[world.rng.randi_range(0, free.size() - 1)]
			t.cell = world.regions[t.region].center
			return
		_absorb(world, t, n)
		return
	_wander(world, t, region)
	if t.region == region.id:
		_absorb(world, t, n)


static func _absorb(world: World, t: Tribe, n: Nation) -> void:
	t.alive = false
	var r := t.race.index
	n.pop[r] = minf(n.pop[r] + t.strength * 3.0, maxf(n.pop[r], n.capacity[r]))
	n.army += t.strength * 0.3
	world.count(&"tribes_absorbed")
	world.log_event(&"tribe", "%s — теперь подданные государства %s." % [t.label(), n.short_name], PackedInt32Array([n.id]))


## Орда оседает в ничейном крае и основывает государство (как основатели мира).
func _found_state(world: World, t: Tribe, region: Region) -> void:
	var nation := GodTools.create_nation(world, t.race, region.center, false)
	if nation == null:
		return
	nation.army = t.strength * 0.8
	nation.pop[t.race.index] = maxf(nation.pop[t.race.index], t.strength * 4.0)
	t.alive = false
	world.count(&"tribe_states")
	world.log_event(&"nation", "%s оседает в крае %s и основывает государство %s." % [t.label(), _rname(region), nation.name],
			PackedInt32Array([nation.id]))


## Орда отнимает край у слабого соседа — там рождается государство орды.
func _conquer(world: World, t: Tribe, region: Region) -> bool:
	for nb in region.neighbors:
		var c := world.regions[nb].controller()
		if c < 0:
			continue
		var n := world.nations[c]
		if not n.alive or n.power() > t.strength * 0.8:
			continue
		if n.capital_city >= 0 and world.region_of[world.cities[n.capital_city].cell] == nb:
			continue  # столицу орда не берёт
		var old := n.short_name
		var nation := GodTools.create_nation(world, t.race, world.regions[nb].center, false)
		if nation == null:
			return false
		nation.army = t.strength * 0.7
		n.army = maxf(0.0, n.army - t.strength * 0.3)
		t.alive = false
		world.count(&"tribe_states")
		world.log_event(&"conquest", "%s отнимает край %s у государства %s и основывает там державу %s." % [t.label(),
			_rname(world.regions[nb]), old, nation.name], PackedInt32Array([nation.id, c]))
		return true
	return false
