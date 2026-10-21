class_name DiseaseSystem
extends RefCounted
## Болезни (этап 11.C, data/diseases). Поветрие рождается в людном городе и
## идёт по краям: по дорогам (чаще), морским путям и к соседним краям без
## дорог (реже). В каждом крае болезнь держится months месяцев и губит долю
## жителей хозяина края (кроме невосприимчивых рас), потом уходит, оставляя
## иммунитет на immunity_years лет. Чума — частный случай: событие «Чума»
## (data/events/plague) начинает «Чёрный мор», и тот, придя в новое
## государство, приносит ему событие чумы (вместо прежнего «перескока к
## соседям» события).
##
## Ход: каждое поветрие — раз в месяц в «свой» день (Outbreak.day); новое — раз в год.

const MAX_OUTBREAKS := 3
const YEAR_CHANCE := 0.12
## Предел краёв одного поветрия (дальше не идёт — «выгорает»).
const MAX_REGIONS := 60
## Порядок в краях больных: стабильность в месяц.
const STABILITY := 0.001
const PLAGUE := &"black_death"

## Доля прежнего «дорожного» распространения, что остаётся без караванов
## (вторую половину везут сами караваны — carry()).
const CARAVAN_SHARE := 0.5

## Пары краёв, связанных дорогой (суша) и морским путём: кэш по World.road_version.
var _road_adj := {}
var _sea_adj := {}
var _adj_version := -1
var _adj_world := 0


static func alive_outbreaks(world: World) -> Array[Outbreak]:
	var res: Array[Outbreak] = []
	for o in world.outbreaks:
		if o.alive:
			res.append(o)
	return res


static func outbreak_in(world: World, region_id: int) -> Outbreak:
	for o in world.outbreaks:
		if o.alive and o.regions.has(region_id):
			return o
	return null


static func _pick_def(world: World) -> DiseaseDef:
	var total := 0.0
	var defs: Array[DiseaseDef] = []
	for d in DiseaseDB.all():
		var def: DiseaseDef = d
		if not def.plague and world.year >= def.min_year:
			defs.append(def)
			total += def.weight
	if defs.is_empty():
		return null
	var roll := world.rng.randf() * total
	for def in defs:
		roll -= def.weight
		if roll <= 0.0:
			return def
	return defs[defs.size() - 1]


## Может ли болезнь войти в край: люди есть, иммунитета нет, народ хозяина восприимчив.
static func can_infect(world: World, def: DiseaseDef, region: Region) -> bool:
	if region.immune.get(def.id, -1) > world.year:
		return false
	var c := region.controller()
	if c < 0:
		return TribeSystem.tribe_in(world, region.id) != null
	var race := world.nations[c].race
	return not def.immune_races.has(race.id) and not def.immune_traits.any(func(t: StringName) -> bool: return race.has_trait(t))


## Караван из больного края везёт заразу: шанс заразить край прихода (этап 12.B).
static func carry(world: World, from_cell: int, to_cell: int) -> void:
	var from := world.region_of[from_cell]
	var to := world.region_of[to_cell]
	if from < 0 or to < 0 or from == to:
		return
	var o := outbreak_in(world, from)
	if o == null or not o.alive or o.regions.has(to):
		return
	if world.rng.randf() < o.def.road_spread * (1.0 - CARAVAN_SHARE) * 3.0:
		if start(world, o.def, to) != null:
			world.count(&"caravan_plague")


## Начать поветрие def в крае region_id (Бог, событие чумы, случай). Уже есть такое — край добавляется к нему.
static func start(world: World, def: DiseaseDef, region_id: int) -> Outbreak:
	if def == null or region_id < 0:
		return null
	var region := world.regions[region_id]
	for o in world.outbreaks:
		if o.alive and o.def == def:
			if not o.regions.has(region_id) and can_infect(world, def, region):
				o.regions[region_id] = def.months
			return o
	if not can_infect(world, def, region):
		return null
	var o := Outbreak.new()
	o.id = world.outbreaks.size()
	o.def = def
	o.origin = region_id
	o.regions[region_id] = def.months
	o.born = world.year
	o.day = world.rng.randi_range(0, Simulation.DAYS - 1)
	o.peak = 1
	world.outbreaks.append(o)
	world.count(&"outbreaks")
	var c := region.controller()
	if c >= 0:
		o.nations[c] = true
	world.log_event(&"disease", "В крае %s началось поветрие: %s." % [_rname(region), def.display_name.to_lower()],
		PackedInt32Array([c]) if c >= 0 else PackedInt32Array())
	return o


static func _rname(region: Region) -> String:
	return region.name if not region.name.is_empty() else "без имени"


func tick_day(world: World) -> void:
	for o in world.outbreaks:
		if o.alive and o.day == world.day:
			_month(world, o)


func tick_year(world: World) -> void:
	var rng := world.rng
	if alive_outbreaks(world).size() < MAX_OUTBREAKS and rng.randf() < YEAR_CHANCE and not world.cities.is_empty():
		# Поветрие рождается в людном городе (лучший из нескольких проб).
		var best: City = null
		for k in 6:
			var c := world.cities[rng.randi_range(0, world.cities.size() - 1)]
			if c.alive and (best == null or c.population > best.population):
				best = c
		if best != null:
			start(world, _pick_def(world), world.region_of[best.cell])
	var keep: Array[Outbreak] = []
	for o in world.outbreaks:
		if o.alive:
			o.id = keep.size()
			keep.append(o)
	world.outbreaks = keep


func _refresh_adj(world: World) -> void:
	if _adj_version == world.road_version and _adj_world == world.get_instance_id():
		return
	_adj_version = world.road_version
	_adj_world = world.get_instance_id()
	_road_adj.clear()
	_sea_adj.clear()
	for road in world.roads:
		if not road.alive:
			continue
		var ra := world.region_of[world.cities[road.a].cell]
		var rb := world.region_of[world.cities[road.b].cell]
		if ra < 0 or rb < 0 or ra == rb:
			continue
		var adj: Dictionary = _sea_adj if road.sea else _road_adj
		for pair in [[ra, rb], [rb, ra]]:
			if adj.has(pair[0]):
				if not (adj[pair[0]] as PackedInt32Array).has(pair[1]):
					adj[pair[0]].append(pair[1])
			else:
				adj[pair[0]] = PackedInt32Array([pair[1]])


func _month(world: World, o: Outbreak) -> void:
	var rng := world.rng
	var def := o.def
	_refresh_adj(world)
	var spread := PackedInt32Array()
	for rid in o.regions.keys():
		var region := world.regions[rid]
		var c := region.controller()
		if c >= 0:
			var n := world.nations[c]
			var share := float(region.owner_counts.get(c, 0)) / maxf(1.0, float(n.cell_count))
			var f := def.lethality / float(def.months) * share
			for r in n.pop.size():
				if n.pop[r] <= 0.0:
					continue
				var race := RaceDB.by_index(r)
				if def.immune_races.has(race.id) or def.immune_traits.any(func(t: StringName) -> bool: return race.has_trait(t)):
					continue
				o.deaths += n.pop[r] * f
				n.pop[r] *= 1.0 - f
			n.stability = maxf(0.0, n.stability - STABILITY * share * 4.0)
		var t := TribeSystem.tribe_in(world, rid)
		if t != null:
			t.strength *= 1.0 - def.lethality / float(def.months) * 2.0
		# Куда идёт дальше.
		if o.regions.size() + spread.size() < MAX_REGIONS:
			# По дорогам поветрие разносят и караваны (CaravanSystem, этап 12.B) — здесь вдвое реже.
			for nb in _road_adj.get(rid, PackedInt32Array()):
				if rng.randf() < def.road_spread * CARAVAN_SHARE:
					spread.append(nb)
			for nb in _sea_adj.get(rid, PackedInt32Array()):
				if rng.randf() < def.sea_spread:
					spread.append(nb)
			for nb in region.neighbors:
				if rng.randf() < def.land_spread:
					spread.append(nb)
		o.regions[rid] -= 1
		if o.regions[rid] <= 0:
			o.regions.erase(rid)
			region.immune[def.id] = world.year + def.immunity_years
	for rid in spread:
		var region := world.regions[rid]
		if o.regions.has(rid) or outbreak_in(world, rid) != null or not can_infect(world, def, region):
			continue
		o.regions[rid] = def.months
		var c := region.controller()
		if c >= 0 and not o.nations.has(c):
			o.nations[c] = true
			if def.plague:
				world.pending_events.append([c, &"plague"])
			if o.nations.size() <= 3 or rng.randf() < 0.25:
				world.log_event(&"disease", "Поветрие «%s» пришло в государство %s (край %s)." % [def.display_name, world.nations[c].short_name,
					_rname(region)], PackedInt32Array([c]))
	o.peak = maxi(o.peak, o.regions.size())
	if o.regions.is_empty():
		o.alive = false
		world.count(&"outbreaks_over")
		if o.deaths > 3000.0 or o.peak >= 5:
			world.log_event(&"disease", "Поветрие «%s» отступило (краёв за раз — до %d, погибших — %s)." % [def.display_name, o.peak, ArmySystem._num(o.deaths)])


## Болезни края (для карточек): названия поветрий, которые сейчас здесь.
static func region_text(world: World, region_id: int) -> String:
	var o := outbreak_in(world, region_id)
	if o == null:
		return ""
	return "%s (ещё %d мес.)" % [o.def.display_name, o.regions[region_id]]
