class_name SaveSystem
## Сохранение и загрузка мира в JSON.
##
## Большие массивы клеток (высоты, климат, биомы, владельцы, народы, регионы…)
## пишутся как base64 сырых байтов Packed-массивов — компактно и точно.
## Производный учёт (списки клеток государств, добыча, ёмкость земли, длина
## границ, счётчики регионов) не сохраняется: при загрузке он пересобирается
## через World.set_owner, поэтому гарантированно согласован.

const VERSION := 1
const SAVE_DIR := "user://saves/"


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
	file.store_string(JSON.stringify(to_dict(world), "", false, true))
	return OK


static func load_world(path: String) -> World:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SaveSystem: не удалось прочитать " + path)
		return null
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		push_error("SaveSystem: неверный формат сохранения " + path)
		return null
	return from_dict(data)


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
			"owner_order": r.owner_counts.keys()})
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
		history.append({"year": snap.year, "races": Array(snap.races), "nations": ns})
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


static func _nation_dict(n: Nation) -> Dictionary:
	return {
		"id": n.id, "name": n.name, "short": n.short_name, "race": str(n.race_id), "color": n.color.to_html(),
		"ruler": n.ruler_name, "title": n.ruler_title, "ruler_age": n.ruler_age, "reign_left": n.reign_left,
		"trait": str(n.ruler_trait.id) if n.ruler_trait != null else "", "ruler_number": n.ruler_number,
		"government": str(n.government.id) if n.government != null else "monarchy",
		"dynasty": n.dynasty, "dynasty_names": n.dynasty_names, "hero_ids": Array(n.hero_ids),
		"capital": n.capital_city, "city_ids": Array(n.city_ids),
		"cells": _b64(n.cells.to_byte_array()), "yields": Array(n.yields), "capacity": Array(n.capacity),
		"border_order": n.borders.keys(), "region_order": n.region_counts.keys(),
		"pop": Array(n.pop), "stock": Array(n.stock), "income": Array(n.income),
		"bonus": [n.food_bonus, n.stability_bonus, n.army_bonus, n.science_bonus], "building_production": Array(n.building_production),
		"hero_power": n.hero_power, "sources": n.sources,
		"army": n.army, "stability": n.stability, "tech": n.tech, "expansion_points": n.expansion_points,
		"famine": n.famine_years, "founded": n.founded_year, "alive": n.alive, "label": n.label_cell,
		"overlord": n.overlord, "vassal_since": n.vassal_since, "allies": n.allies.keys(), "trade": n.trade_partners.keys(),
		"stalled": n.stalled_years, "collapse": n.collapse_years,
		"modifiers": n.modifiers.map(func(m: Dictionary) -> Dictionary:
			var c := m.duplicate()
			c.id = str(m.id)
			return c),
	}


static func _hero_dict(h: Hero) -> Dictionary:
	return {
		"id": h.id, "name": h.name, "race": str(h.race_id), "class": str(h.hero_class.id), "level": h.level, "xp": h.xp,
		"age": h.age, "max_age": h.max_age, "born": h.born_year, "cell": h.cell, "nation": h.nation_id,
		"alive": h.alive, "ruler": h.is_ruler, "kills": h.kills, "monsters": h.monsters_slain, "epithet": h.epithet,
		"deeds": h.deeds, "move_in": h.move_in, "karma": h.karma, "artifact": h.artifact, "artifact_mult": h.artifact_mult,
		"fate": str(h.fate), "returns": h.returns, "goal": h.goal_cell, "bonds": _int_dict(h.bonds),
		"spouse": h.spouse, "mentor": h.mentor, "party": h.party_leader, "ally": h.ally_nation, "ally_until": h.ally_until,
		"vendetta": h.vendetta, "killed_by": h.killed_by,
	}


static func _war_dict(w: War) -> Dictionary:
	return {"id": w.id, "name": w.name, "cause": str(w.cause), "start": w.start_year, "end": w.end_year,
		"att": Array(w.attackers), "def": Array(w.defenders), "score": w.score, "siege": w.siege_region,
		"siege_side": w.siege_side, "progress": w.siege_progress, "landing": w.siege_landing,
		"month": w.month, "day": w.day, "battles": w.battles, "casualties": w.casualties, "active": w.active}


static func _b64(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes) if not bytes.is_empty() else ""


static func _int_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k]
	return out


# ---------------------------------------------------------------------------
# Чтение
# ---------------------------------------------------------------------------

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
		world.history.append({"year": int(snap.year), "races": PackedFloat32Array(snap.races), "nations": ns})
	world.terrain_version = int(data.get("terrain_version", 0))
	world.update_label_anchors()
	# Состояние ГСЧ — в самом конце: восстановление не должно его сдвигать.
	world.rng.seed = int(data.rng[0])
	world.rng.state = int(data.rng[1])
	return world


static func _restore_nation(nd: Dictionary) -> Nation:
	var n := Nation.new()
	n.id = int(nd.id)
	n.name = nd.name
	n.short_name = nd.short
	n.race_id = StringName(nd.race)
	n.race = RaceDB.get_race(n.race_id)
	n.color = Color.html(nd.color)
	n.ruler_name = nd.ruler
	n.ruler_title = nd.title
	n.ruler_age = int(nd.ruler_age)
	n.reign_left = int(nd.reign_left)
	var traits := PoliticsDB.ruler_traits()
	for t in traits:
		if str(t.id) == nd.trait:
			n.ruler_trait = t
	n.ruler_number = int(nd.ruler_number)
	n.government = PoliticsDB.government(StringName(nd.government))
	n.dynasty = nd.dynasty
	for k in nd.dynasty_names:
		n.dynasty_names[k] = int(nd.dynasty_names[k])
	n.hero_ids = PackedInt32Array(nd.hero_ids)
	n.stock = PackedFloat32Array(nd.stock)
	n.income = PackedFloat32Array(nd.income)
	n.army = nd.army
	n.stability = nd.stability
	n.tech = nd.tech
	n.expansion_points = nd.expansion_points
	n.famine_years = int(nd.famine)
	n.founded_year = int(nd.founded)
	n.label_cell = int(nd.label)
	n.overlord = int(nd.overlord)
	n.vassal_since = int(nd.vassal_since)
	for a in nd.allies:
		n.allies[int(a)] = true
	for t in nd.trade:
		n.trade_partners[int(t)] = true
	n.stalled_years = int(nd.stalled)
	n.collapse_years = int(nd.collapse)
	for md in nd.modifiers:
		var mod: Dictionary = md.duplicate()
		mod.id = StringName(md.id)
		mod.until = int(md.until)
		n.modifiers.append(mod)
	return n


static func _restore_hero(hd: Dictionary) -> Hero:
	var h := Hero.new()
	h.id = int(hd.id)
	h.name = hd.name
	h.race_id = StringName(hd.race)
	h.race = RaceDB.get_race(h.race_id)
	h.hero_class = PoliticsDB.get_hero_class(StringName(hd["class"]))
	h.level = int(hd.level)
	h.xp = hd.xp
	h.age = int(hd.age)
	h.max_age = int(hd.max_age)
	h.born_year = int(hd.born)
	h.cell = int(hd.cell)
	h.nation_id = int(hd.nation)
	h.alive = hd.alive
	h.is_ruler = hd.ruler
	h.kills = int(hd.kills)
	h.monsters_slain = int(hd.monsters)
	h.epithet = hd.epithet
	var deeds: Array[String] = []
	for d in hd.deeds:
		deeds.append(d)
	h.deeds = deeds
	h.move_in = int(hd.move_in)
	h.karma = hd.karma
	h.artifact = hd.artifact
	h.artifact_mult = hd.artifact_mult
	h.fate = StringName(hd.fate)
	h.returns = int(hd.returns)
	h.goal_cell = int(hd.goal)
	for k in hd.bonds:
		h.bonds[int(k)] = float(hd.bonds[k])
	h.spouse = int(hd.spouse)
	h.mentor = int(hd.mentor)
	h.party_leader = int(hd.party)
	h.ally_nation = int(hd.ally)
	h.ally_until = int(hd.ally_until)
	h.vendetta = int(hd.vendetta)
	h.killed_by = int(hd.killed_by)
	return h


static func _restore_war(wd: Dictionary) -> War:
	var w := War.new()
	w.id = int(wd.id)
	w.name = wd.name
	w.cause = StringName(wd.cause)
	w.start_year = int(wd.start)
	w.end_year = int(wd.end)
	w.attackers = PackedInt32Array(wd.att)
	w.defenders = PackedInt32Array(wd.def)
	w.score = wd.score
	w.siege_region = int(wd.siege)
	w.siege_side = int(wd.siege_side)
	w.siege_progress = wd.progress
	w.siege_landing = wd.landing
	w.month = int(wd.month)
	w.day = int(wd.day)
	w.battles = int(wd.battles)
	w.casualties = wd.casualties
	w.active = wd.active
	return w


## Переставляет ключи словаря в порядке order (значения не меняются).
static func _reorder(d: Dictionary, order: Array) -> void:
	var copy := d.duplicate()
	d.clear()
	for k in order:
		if copy.has(int(k)):
			d[int(k)] = copy[int(k)]
			copy.erase(int(k))
	for k in copy:
		d[k] = copy[k]


static func _raw(text: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(text) if not text.is_empty() else PackedByteArray()
