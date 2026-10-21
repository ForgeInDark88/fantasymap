class_name ClimateSystem
extends RefCounted
## Климат (раз в год для всего мира).
##
## Три пояса (север, умеренный, юг) получают урожайность года: суровые зимы
## (чаще на севере), засухи (чаще на юге) и пепельные зимы после извержений
## вулканов. Случаются наводнения у рек, лесные пожары (особенно тяжелы для
## эльфов) и обвалы в горах (для рудокопов-дворфов). Климат медленно
## дрейфует (температура и влажность); раз в DRIFT_PERIOD лет, если сдвиг
## заметен, биомы пересчитываются в нескольких регионах — только в них.
## Следы бедствий (пепел, затопления, гари, засуха) видны на карте.

## Пояса: шансы суровой зимы и засухи в год, их сила (множитель урожая).
const WINTER_CHANCE: Array[float] = [0.07, 0.03, 0.005]
const DROUGHT_CHANCE: Array[float] = [0.01, 0.03, 0.06]
const WINTER_HARVEST := 0.8
const DROUGHT_HARVEST := 0.7
const ASH_HARVEST := 0.8
const ZONE_NAMES: Array[String] = ["на севере", "в умеренных землях", "на юге"]
## Вулканы: число на карте (одна гора на столько клеток суши) и шанс извержения в год.
const LAND_PER_VOLCANO := 12000
const ERUPTION_CHANCE := 0.003
## Шансы в год (на весь мир) наводнения, пожара, обвала.
const FLOOD_CHANCE := 0.05
const FIRE_CHANCE := 0.04
const CAVE_IN_CHANCE := 0.025
## Дрейф климата: шаг в год, предел, как часто пересчитывать биомы и в скольких регионах.
const DRIFT_STEP := 0.004
const DRIFT_LIMIT := 0.12
const DRIFT_PERIOD := 20
const DRIFT_REGIONS := 3


## Вулканы — самые высокие горные вершины (детерминированно по карте).
static func place_volcanoes(world: World) -> void:
	world.volcanoes.clear()
	var map := world.map
	var peaks: Array[Vector2] = []
	var land := 0
	for i in map.cell_count():
		if map.is_land(i):
			land += 1
			if map.biome[i] == Biome.MOUNTAINS:
				peaks.append(Vector2(map.elevation[i], i))
	peaks.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	var count := maxi(2, world.gbi(land) / LAND_PER_VOLCANO)
	for p in peaks:
		var cell := int(p.y)
		var far := true
		for v in world.volcanoes:
			if Vector2(map.cell_pos(v)).distance_to(Vector2(map.cell_pos(cell))) < world.gd(25.0):
				far = false
				break
		if far:
			world.volcanoes.append(cell)
			if world.volcanoes.size() >= count:
				break


func tick_year(world: World) -> void:
	var rng := world.rng
	_drift(world)
	# Урожай поясов: суровые зимы и засухи (с длительностью), пепел.
	for z in 3:
		var ev: Dictionary = world.zone_events.get(z, {})
		if not ev.is_empty() and int(ev.until) <= world.year:
			world.zone_events.erase(z)
			ev = {}
		if ev.is_empty():
			if rng.randf() < WINTER_CHANCE[z]:
				ev = {"kind": "winter", "until": world.year + 1}
				world.log_event(&"climate", "Суровая зима %s: замёрзли реки, урожай погиб на корню." % ZONE_NAMES[z], _nations_in_zone(world, z))
			elif rng.randf() < DROUGHT_CHANCE[z] * (1.0 + maxf(0.0, -world.moist_shift) * 5.0):
				ev = {"kind": "drought", "until": world.year + rng.randi_range(2, 4)}
				world.log_event(&"climate", "Великая сушь %s: колодцы пересохли, поля трескаются от зноя." % ZONE_NAMES[z], _nations_in_zone(world, z))
				_drought_scars(world, z)
			if not ev.is_empty():
				world.zone_events[z] = ev
		var h := 1.0
		if not ev.is_empty():
			h *= WINTER_HARVEST if ev.kind == "winter" else DROUGHT_HARVEST
		if world.ash_until > world.year:
			h *= ASH_HARVEST
		world.zone_harvest[z] = h
	for v in world.volcanoes:
		if rng.randf() < ERUPTION_CHANCE:
			erupt(world, v)
	if rng.randf() < FLOOD_CHANCE:
		_flood(world)
	if rng.randf() < FIRE_CHANCE:
		_fire(world)
	if rng.randf() < CAVE_IN_CHANCE:
		_cave_in(world)
	# Старые следы стираются.
	var k := 0
	for s in world.scars:
		if int(s.until) > world.year:
			world.scars[k] = s
			k += 1
	world.scars.resize(k)


## Извержение: города рядом гибнут, жители бегут, пепел на годы, пепельная зима.
static func erupt(world: World, cell: int) -> void:
	var rng := world.rng
	var map := world.map
	var pos := Vector2(map.cell_pos(cell))
	var region := world.region_label(cell, "диких горах")
	var lost: Array[String] = []
	for city in world.cities:
		if city.alive and not city.is_capital and Vector2(map.cell_pos(city.cell)).distance_to(pos) <= world.gd(5.0) and rng.randf() < 0.5:
			lost.append(city.name)
			world.destroy_city(city)
	var hit := {}
	for rid in [world.region_of[cell]] + (Array(world.regions[world.region_of[cell]].neighbors) if world.region_of[cell] >= 0 else []):
		var o := world.regions[rid].controller()
		if o >= 0 and not hit.has(o):
			hit[o] = true
			var n := world.nations[o]
			for r in n.pop.size():
				n.pop[r] *= 0.95
			n.stability = maxf(0.0, n.stability - 0.05)
	world.scars.append({"cell": cell, "radius": 9.0, "kind": "ash", "until": world.year + 15})
	world.ash_until = maxi(world.ash_until, world.year + rng.randi_range(2, 5))
	world.count(&"eruptions")
	world.log_event(&"climate", "Извержение вулкана в регионе %s! %sПепел затмил солнце — наступает пепельная зима." % [
		region, ("Погребены города: %s. " % ", ".join(lost)) if not lost.is_empty() else ""], PackedInt32Array(hit.keys()))


func _flood(world: World) -> void:
	var rng := world.rng
	for attempt in 12:
		var region := world.regions[rng.randi_range(0, world.regions.size() - 1)]
		if region.cells.is_empty():
			continue
		var river := -1
		for t in 6:
			var c := region.cells[rng.randi_range(0, region.cells.size() - 1)]
			if world.map.river[c] > 1:
				river = c
				break
		var o := region.controller()
		if river < 0 or o < 0:
			continue
		var n := world.nations[o]
		for r in n.pop.size():
			n.pop[r] *= 0.98
		n.stock[Goods.FOOD] *= 0.7
		world.scars.append({"cell": river, "radius": 5.0, "kind": "flood", "until": world.year + 3})
		world.log_event(&"climate", "Наводнение в регионе %s (%s): река вышла из берегов, смыло поля и мельницы." % [region.name, n.short_name],
				PackedInt32Array([o]))
		return


func _fire(world: World) -> void:
	var rng := world.rng
	for attempt in 12:
		var region := world.regions[rng.randi_range(0, world.regions.size() - 1)]
		if region.center < 0:
			continue
		var b := world.map.biome[region.center]
		if b != Biome.FOREST and b != Biome.JUNGLE:
			continue
		var o := region.controller()
		var who := ""
		if o >= 0:
			var n := world.nations[o]
			# Эльфам гибель леса — горе всего народа.
			var forest_folk := n.race.has_trait(&"forest_bond")
			for r in n.pop.size():
				n.pop[r] *= 0.97 if forest_folk else 0.99
			n.stability = maxf(0.0, n.stability - (0.06 if forest_folk else 0.01))
			who = " (%s)%s" % [n.short_name, " — эльфы оплакивают священные рощи" if forest_folk else ""]
		world.scars.append({"cell": region.center, "radius": 6.0, "kind": "fire", "until": world.year + 4})
		world.log_event(&"climate", "Лесной пожар в регионе %s%s." % [region.name, who], PackedInt32Array([o]) if o >= 0 else PackedInt32Array())
		return


func _cave_in(world: World) -> void:
	var rng := world.rng
	for attempt in 12:
		var region := world.regions[rng.randi_range(0, world.regions.size() - 1)]
		if region.center < 0:
			continue
		var b := world.map.biome[region.center]
		var o := region.controller()
		if (b != Biome.MOUNTAINS and b != Biome.HILLS) or o < 0 or not world.nations[o].race.has_trait(&"miners"):
			continue
		var n := world.nations[o]
		for r in n.pop.size():
			n.pop[r] *= 0.98
		n.stock[Goods.METAL] *= 0.8
		world.log_event(&"climate", "Обвал в копях региона %s (%s): шахтёры погребены под камнем." % [region.name, n.short_name],
				PackedInt32Array([o]))
		return


## Медленный дрейф климата и пересчёт биомов в нескольких регионах.
func _drift(world: World) -> void:
	var rng := world.rng
	world.temp_shift = clampf(world.temp_shift * 0.995 + rng.randf_range(-DRIFT_STEP, DRIFT_STEP)
			- (0.002 if world.ash_until > world.year else 0.0), -DRIFT_LIMIT, DRIFT_LIMIT)
	world.moist_shift = clampf(world.moist_shift * 0.995 + rng.randf_range(-DRIFT_STEP, DRIFT_STEP), -DRIFT_LIMIT, DRIFT_LIMIT)
	if world.year % DRIFT_PERIOD != 0 or maxf(absf(world.temp_shift), absf(world.moist_shift)) < 0.03:
		return
	var map := world.map
	var changed_regions: Array[String] = []
	for k in DRIFT_REGIONS:
		var region := world.regions[rng.randi_range(0, world.regions.size() - 1)]
		var changes := {}
		for c in region.cells:
			if not map.is_land(c) or world.city_cell[c] >= 0:
				continue
			var b := MapGenerator.classify_land(map.elevation[c], clampf(map.temperature[c] + world.temp_shift, 0.0, 1.0),
					clampf(map.moisture[c] + world.moist_shift, 0.0, 1.0))
			if b != map.biome[c]:
				changes[c] = b
		if changes.size() < 3:
			continue
		var before := map.biome[changes.keys()[0]]
		var after: int = changes.values()[0]
		for c in changes:
			world.change_land_biome(c, changes[c])
		if not region.name.is_empty():
			changed_regions.append("%s (%s → %s)" % [region.name, BiomeDB.get_def(before).display_name.to_lower(),
				BiomeDB.get_def(after).display_name.to_lower()])
	if not changed_regions.is_empty():
		world.terrain_version += 1
		world.log_event(&"climate", "Климат меняется (%s): земли преображаются — %s." % [
			"холодает" if world.temp_shift < 0.0 else "теплеет", ", ".join(changed_regions)])


func _drought_scars(world: World, zone: int) -> void:
	var rng := world.rng
	for k in 3:
		var region := world.regions[rng.randi_range(0, world.regions.size() - 1)]
		if region.center >= 0 and world.climate_zone(region.center) == zone:
			world.scars.append({"cell": region.center, "radius": 7.0, "kind": "drought", "until": int(world.zone_events.get(zone, {}).get("until", world.year + 2))})


static func _nations_in_zone(world: World, zone: int) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for n in world.nations:
		if n.alive and n.capital_city >= 0 and world.climate_zone(world.cities[n.capital_city].cell) == zone:
			ids.append(n.id)
	return ids


## Время года по месяцу (для интерфейса).
static func season(month: int) -> String:
	if month <= 1 or month == 11:
		return "зима"
	if month <= 4:
		return "весна"
	if month <= 7:
		return "лето"
	return "осень"
