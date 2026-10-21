class_name SaveSystem
extends "res://scripts/core/save_sections.gd"
## Сохранение и загрузка мира в JSON.
##
## Большие массивы клеток (высоты, климат, биомы, владельцы, народы, регионы…)
## пишутся как base64 сырых байтов Packed-массивов — компактно и точно.
## Производный учёт (списки клеток государств, добыча, ёмкость земли, длина
## границ, счётчики регионов) не сохраняется: при загрузке он пересобирается
## через World.set_owner, поэтому гарантированно согласован.


static func save_path(name: String) -> String:
	return SAVE_DIR + name.validate_filename() + ".json"


static func list_saves() -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	for f in dir.get_files():
		if f.ends_with(".json"):
			result.append(f.get_basename())
	result.sort()
	return result


static func save_world(world: World, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(exact(to_dict(world)), "", false, true))
	return OK


static func load_world(path: String) -> World:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SaveSystem: не удалось прочитать " + path)
		return null
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) < 1 or int(data.get("version", 0)) > VERSION:
		push_error("SaveSystem: неверный формат сохранения " + path)
		return null
	return from_dict(unexact(data))


# ---------------------------------------------------------------------------
# Запись
# ---------------------------------------------------------------------------


static func to_dict(world: World) -> Dictionary:
	var map := world.map
	var s := map.settings
	var regions := []
	for r in world.regions:
		regions.append({"name": r.name, "center": r.center, "loyalty": r.loyalty, "unrest": r.unrest,
			"conquered": r.conquered_year, "pacified": r.pacified_until, "claims": _int_dict(r.claims),
			"owner_order": r.owner_counts.keys(), "neighbors": Array(r.neighbors), "coastal": r.coastal,
			"faith": _int_dict(r.faith), "culture": r.culture, "assim": r.assim,
			"lang": r.language, "lassim": r.lang_assim, "immune": r.immune})
	var nations := []
	for n in world.nations:
		nations.append(_nation_dict(n))
	var cities := []
	for c in world.cities:
		cities.append({"id": c.id, "name": c.name, "cell": c.cell, "nation": c.nation_id, "race": str(c.race_id),
			"pop": c.population, "founded": c.founded_year, "capital": c.is_capital, "alive": c.alive,
			"weight": c.weight, "luck": c.luck, "coastal": c.coastal, "near": c.near_biomes,
			"buildings": Array(c.buildings).map(func(b: StringName) -> String: return str(b))})
	var heroes := []
	for h in world.heroes:
		heroes.append(_hero_dict(h))
	var landmarks := []
	for lm in world.landmarks:
		landmarks.append({"kind": str(lm.kind), "name": lm.name, "cell": lm.cell, "year": lm.created_year,
			"hero": lm.hero_id, "active": lm.active, "guardian": lm.guardian, "artifact": lm.artifact})
	var d := world.diplomacy
	var pairs := {}
	for k in d._pairs:
		pairs[str(k)] = d._pairs[k]
	var history := []
	for snap in world.history:
		var ns := {}
		for id in snap.nations:
			ns[str(id)] = Array(snap.nations[id])
		history.append({"year": snap.year, "races": Array(snap.races), "nations": ns,
			"techs": Array(snap.get("techs", PackedFloat32Array())), "faiths": _int_dict(snap.get("faiths", {})),
			"prices": Array(snap.get("prices", PackedFloat32Array()))})
	var chronicle := []
	for e in world.chronicle:
		chronicle.append({"y": e.year, "m": e.get("month", 0), "d": e.get("day", 0), "k": str(e.kind),
			"t": e.text, "n": Array(e.nations)})
	return {
		"version": VERSION,
		"settings": {"width": s.width, "height": s.height, "seed": s.world_seed, "land": s.land_fraction,
			"continents": s.continents, "rivers": s.river_density, "climate": s.temperature_bias,
			"nation_count": s.nation_count, "races": Array(s.enabled_races).map(func(r: StringName) -> String: return str(r))},
		"date": [world.year, world.month, world.day],
		"rng": [str(world.rng.seed), str(world.rng.state)],
		"map": {
			"elevation": _b64(map.elevation.to_byte_array()), "temperature": _b64(map.temperature.to_byte_array()),
			"moisture": _b64(map.moisture.to_byte_array()), "biome": _b64(map.biome), "river": _b64(map.river),
		},
		"cells": {
			"owner": _b64(world.owner.to_byte_array()), "race": _b64(world.cell_race), "deposit": _b64(world.deposit),
			"region": _b64(world.region_of.to_byte_array()), "cap": _b64(world.cell_cap.to_byte_array()),
		},
		"regions": regions,
		"nations": nations,
		"cities": cities,
		"heroes": heroes,
		"landmarks": landmarks,
		"religions": world.religions.map(_religion_dict),
		"crisis": {"current": world.crisis, "history": world.crisis_history, "last_end": world.last_crisis_end,
			"harvest": world.crisis_harvest, "events": world.crisis_events, "eras": world.eras},
		"ruins": world.ruins.map(func(r: Ruin) -> Array: return [r.name, str(r.kind), r.cell, r.origin, r.created_year,
			r.wealth, r.danger, r.cursed, r.hero_id, r.revived]),
		"caves": world.caves.map(func(c: Cave) -> Array: return [c.name, str(c.kind), c.cell, c.depth, c.entrance,
			Array(c.neighbors), c.owner, c.monsters, c.city, c.explored]),
		"counters": _str_dict(world.counters),
		"climate": {"volcanoes": Array(world.volcanoes), "scars": world.scars, "temp_shift": world.temp_shift,
			"moist_shift": world.moist_shift, "zone_harvest": Array(world.zone_harvest), "zone_events": _int_dict(world.zone_events),
			"ash_until": world.ash_until},
		"roads": world.roads.map(func(r: Road) -> Array: return [r.a, r.b, r.sea, r.length, r.bridges, r.built_year,
			r.safety, r.traffic, r.alive]),
		"societies": world.societies.map(func(s: Society) -> Dictionary: return {"id": s.id, "name": s.name, "kind": str(s.kind),
			"religion": s.religion, "home": s.home, "leader": s.leader, "founded": s.founded_year,
			"influence": _int_dict(s.influence), "seized": s.seized, "alive": s.alive}),
		"orgs": world.orgs.map(func(o: Organization) -> Dictionary: return {"id": o.id, "def": str(o.def.id), "name": o.name,
			"members": Array(o.members), "founder": o.founder, "founded": o.founded_year, "faith": o.faith,
			"alive": o.alive, "banned": _int_dict(o.banned)}),
		"legacies": world.legacies.map(func(l: Legacy) -> Dictionary: return {"id": l.id, "name": l.name, "origin": l.origin,
			"regions": Array(l.regions), "founded": l.founded_year, "until": l.until_year, "collector": l.collector, "alive": l.alive}),
		"cultures": world.cultures.map(func(c: Culture) -> Dictionary: return {"id": c.id, "name": c.name, "race": c.race,
			"color": _col(c.color), "customs": Array(c.customs), "origin": c.origin_nation, "founded": c.founded_year}),
		"lore": _lore_dict(world),
		"wild": _wild_dict(world),
		"market": _market_dict(world),
		"diplo": _diplo_dict(world),
		"fate_queue": Array(world.fate_queue),
		"pending_events": world.pending_events.map(func(p: Array) -> Array: return [p[0], str(p[1])]),
		"diplomacy": {
			"wars": d.wars.map(_war_dict), "past_wars": d.past_wars.slice(maxi(0, d.past_wars.size() - 300)).map(_war_dict),
			"pairs": pairs, "next_war": d._next_war_id, "hegemon": d.hegemon, "coalitions": _int_dict(d.coalitions),
		},
		"chronicle": chronicle,
		"chronicle_total": world.chronicle_total,
		"history": history,
		"used_names": world.used_names.keys(),
		"terrain_version": world.terrain_version,
	}


static func from_dict(data: Dictionary) -> World:
	var st: Dictionary = data.settings
	var s := MapSettings.new()
	s.width = int(st.width)
	s.height = int(st.height)
	s.world_seed = int(st.seed)
	s.land_fraction = st.land
	s.continents = int(st.continents)
	s.river_density = st.rivers
	s.temperature_bias = st.climate
	s.nation_count = int(st.nation_count)
	var races: Array[StringName] = []
	for r in st.races:
		races.append(StringName(r))
	s.enabled_races = races

	var map := WorldMap.new(s.width, s.height)
	map.settings = s
	var m: Dictionary = data.map
	map.elevation = _raw(m.elevation).to_float32_array()
	map.temperature = _raw(m.temperature).to_float32_array()
	map.moisture = _raw(m.moisture).to_float32_array()
	map.biome = _raw(m.biome)
	map.river = _raw(m.river)

	var world := World.new(map, false)
	world.year = int(data.date[0])
	world.month = int(data.date[1])
	world.day = int(data.date[2])
	var cells: Dictionary = data.cells
	world.deposit = _raw(cells.deposit)
	world.region_of = _raw(cells.region).to_int32_array()
	world.restore_geography(data.regions.size())
	for i in data.regions.size():
		var rd: Dictionary = data.regions[i]
		var r := world.regions[i]
		r.name = rd.name
		if int(rd.center) >= 0 and world.region_of[int(rd.center)] == i:
			r.center = int(rd.center)
		r.neighbors = PackedInt32Array(rd.get("neighbors", r.neighbors))
		r.coastal = rd.get("coastal", r.coastal)
		r.loyalty = rd.loyalty
		r.unrest = rd.unrest
		r.conquered_year = int(rd.conquered)
		r.pacified_until = int(rd.pacified)
		for k in rd.claims:
			r.claims[int(k)] = int(rd.claims[k])
	for name in data.used_names:
		world.used_names[name] = true

	# Государства без земли, затем земля через set_owner (пересобирает весь учёт).
	# Клетки передаются в сохранённом порядке — от него зависят случайные выборы.
	for nd in data.nations:
		world.nations.append(_restore_nation(nd))
	world.cell_race = _raw(cells.race)
	for k in data.nations.size():
		for c in _raw(data.nations[k].cells).to_int32_array():
			world.set_owner(c, k)
	world.cell_cap = _raw(cells.cap).to_float32_array()
	# Порядок ключей словарей влияет на случайные выборы — восстанавливаем и его.
	for i in data.regions.size():
		_reorder(world.regions[i].owner_counts, data.regions[i].owner_order)
	for k in data.nations.size():
		var nd: Dictionary = data.nations[k]
		var n := world.nations[k]
		_reorder(n.borders, nd.border_order)
		_reorder(n.region_counts, nd.region_order)
		# Накопленные суммы — как есть, чтобы не терять точность float.
		n.yields = PackedFloat32Array(nd.yields)
		n.capacity = PackedFloat32Array(nd.capacity)
		n.pop = PackedFloat32Array(nd.pop)
		n.city_ids = PackedInt32Array(nd.city_ids)
		n.capital_city = int(nd.capital)
		n.alive = nd.alive
	for cd in data.cities:
		var c := City.new()
		c.id = int(cd.id)
		c.name = cd.name
		c.cell = int(cd.cell)
		c.nation_id = int(cd.nation)
		c.race_id = StringName(cd.race)
		c.population = cd.pop
		c.founded_year = int(cd.founded)
		c.is_capital = cd.capital
		c.alive = cd.alive
		c.weight = cd.weight
		c.luck = cd.luck
		c.coastal = cd.coastal
		c.near_biomes = int(cd.near)
		var b: Array[StringName] = []
		for x in cd.buildings:
			b.append(StringName(x))
		c.buildings = b
		world.restore_city(c)
	for k in data.nations.size():
		var nd: Dictionary = data.nations[k]
		var n := world.nations[k]
		n.food_bonus = nd.bonus[0]
		n.stability_bonus = nd.bonus[1]
		n.army_bonus = nd.bonus[2]
		n.science_bonus = nd.bonus[3]
		n.building_production = PackedFloat32Array(nd.building_production)
		n.hero_power = nd.hero_power
		n.sources = int(nd.sources)

	for hd in data.heroes:
		var h := _restore_hero(hd)
		world.heroes.append(h)
		if h.alive and not h.is_ruler:
			world.add_wandering(h)
	for ld in data.landmarks:
		var lm := Landmark.new()
		lm.id = world.landmarks.size()
		lm.kind = StringName(ld.kind)
		lm.name = ld.name
		lm.cell = int(ld.cell)
		lm.created_year = int(ld.year)
		lm.hero_id = int(ld.hero)
		lm.active = ld.active
		lm.guardian = ld.guardian
		lm.artifact = ld.artifact
		world.landmarks.append(lm)
	world.fate_queue = PackedInt32Array(data.fate_queue)
	for p in data.pending_events:
		world.pending_events.append([int(p[0]), StringName(p[1])])

	var dd: Dictionary = data.diplomacy
	var d := world.diplomacy
	for wd in dd.wars:
		d.wars.append(_restore_war(wd))
	for wd in dd.past_wars:
		d.past_wars.append(_restore_war(wd))
	for k in dd.pairs:
		var p: Dictionary = dd.pairs[k]
		d._pairs[int(k)] = {"truce_until": int(p.truce_until), "grudge": float(p.grudge), "marriage_until": int(p.get("marriage_until", -1))}
	d._next_war_id = int(dd.next_war)
	d.hegemon = int(dd.hegemon)
	for k in dd.coalitions:
		d.coalitions[int(k)] = int(dd.coalitions[k])

	for e in data.chronicle:
		world.chronicle.append({"year": int(e.y), "month": int(e.m), "day": int(e.d), "kind": StringName(e.k),
			"text": e.t, "nations": PackedInt32Array(e.n)})
	world.chronicle_total = int(data.chronicle_total)
	for snap in data.history:
		var ns := {}
		for k in snap.nations:
			ns[int(k)] = PackedFloat32Array(snap.nations[k])
		var faiths := {}
		for k in snap.get("faiths", {}):
			faiths[int(k)] = int(snap.faiths[k])
		world.history.append({"year": int(snap.year), "races": PackedFloat32Array(snap.races), "nations": ns,
			"techs": PackedFloat32Array(snap.get("techs", [])), "faiths": faiths, "prices": PackedFloat32Array(snap.get("prices", []))})
	world.terrain_version = int(data.get("terrain_version", 0))
	_load_religions(world, data)
	_load_techs_and_cultures(world, data)
	_load_intrigue(world, data)
	var cr: Dictionary = data.get("crisis", {})
	if not cr.is_empty():
		var cur: Dictionary = cr.current
		if not cur.is_empty():
			world.crisis = {"id": str(cur.id), "stage": int(cur.stage), "stage_start": int(cur.stage_start), "start": int(cur.start),
				"invader": int(cur.invader), "titan_cell": int(cur.titan_cell), "titan_power": float(cur.titan_power),
				"titan_name": str(cur.titan_name)}
		for h in cr.history:
			world.crisis_history.append({"id": str(h.id), "name": str(h.name), "start": int(h.start), "end": int(h.end)})
		world.last_crisis_end = int(cr.last_end)
		world.crisis_harvest = float(cr.harvest)
		world.crisis_events = cr.events
		for e in cr.eras:
			world.eras.append({"name": str(e.name), "start": int(e.start), "end": int(e.end)})
	for rd in data.get("ruins", []):
		var r := Ruin.new()
		r.id = world.ruins.size()
		r.name = rd[0]
		r.kind = StringName(rd[1])
		r.cell = int(rd[2])
		r.origin = rd[3]
		r.created_year = int(rd[4])
		r.wealth = rd[5]
		r.danger = rd[6]
		r.cursed = rd[7]
		r.hero_id = int(rd[8])
		r.revived = rd[9]
		world.ruins.append(r)
	if not data.has("caves"):
		UndergroundSystem.generate(world)
	for cd in data.get("caves", []):
		var c := Cave.new()
		c.id = world.caves.size()
		c.name = cd[0]
		c.kind = StringName(cd[1])
		c.cell = int(cd[2])
		c.depth = int(cd[3])
		c.entrance = cd[4]
		c.neighbors = PackedInt32Array(cd[5])
		c.owner = int(cd[6])
		c.monsters = cd[7]
		c.city = cd[8]
		c.explored = cd[9]
		world.caves.append(c)
	for n in world.nations:
		n.tunnel_neighbors = UndergroundSystem.tunnel_neighbors(world, n.id)
	var cnt: Dictionary = data.get("counters", {})
	for k in cnt:
		world.counters[StringName(k)] = int(cnt[k])
	var cl: Dictionary = data.get("climate", {})
	if cl.is_empty():
		ClimateSystem.place_volcanoes(world)
	else:
		world.volcanoes = PackedInt32Array(cl.volcanoes)
		for sc in cl.scars:
			world.scars.append({"cell": int(sc.cell), "radius": float(sc.radius), "kind": sc.kind, "until": int(sc.until)})
		world.temp_shift = cl.temp_shift
		world.moist_shift = cl.moist_shift
		world.zone_harvest = PackedFloat32Array(cl.zone_harvest)
		for z in cl.zone_events:
			world.zone_events[int(z)] = {"kind": cl.zone_events[z].kind, "until": int(cl.zone_events[z].until)}
		world.ash_until = int(cl.ash_until)
	for rd in data.get("roads", []):
		var road := RoadSystem.build(world, world.cities[int(rd[0])], world.cities[int(rd[1])], rd[2], rd[3], int(rd[4]))
		road.built_year = int(rd[5])
		road.safety = rd[6]
		road.traffic = rd[7]
		road.alive = rd[8]
	_load_lore(world, data)
	_load_wild(world, data)
	_load_market(world, data)
	_load_diplo(world, data)
	world.update_label_anchors()
	# Состояние ГСЧ — в самом конце: восстановление не должно его сдвигать.
	world.rng.seed = int(data.rng[0])
	world.rng.state = int(data.rng[1])
	return world
