class_name SaveSystem
## Сохранение и загрузка мира в JSON.
##
## Большие массивы клеток (высоты, климат, биомы, владельцы, народы, регионы…)
## пишутся как base64 сырых байтов Packed-массивов — компактно и точно.
## Производный учёт (списки клеток государств, добыча, ёмкость земли, длина
## границ, счётчики регионов) не сохраняется: при загрузке он пересобирается
## через World.set_owner, поэтому гарантированно согласован.

## Версия формата. 1 — этап 6; 2 — религии, технологии и далее (этапы 7+).
## Старые версии загружаются: недостающее заполняется значениями по умолчанию.
const VERSION := 2
const SAVE_DIR := "user://saves/"
const EXACT_PREFIX := "~"


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
			"faith": _int_dict(r.faith), "culture": r.culture, "assim": r.assim})
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
			"techs": Array(snap.get("techs", PackedFloat32Array())), "faiths": _int_dict(snap.get("faiths", {}))})
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
		"religion": n.state_religion, "unity": n.faith_unity, "effects": _effects_dict(n),
		"techs": n.techs.keys().map(func(t: StringName) -> String: return str(t)), "researching": str(n.researching),
		"research": n.research, "tech_seen": n.tech_seen, "culture": n.culture, "culture_level": n.culture_level,
		"intel": n.intel, "legacy": n.legacy, "home": n.home_cell, "tdirty": n.territory_dirty,
		"modifiers": n.modifiers.map(func(m: Dictionary) -> Dictionary:
			var c := m.duplicate()
			c.id = str(m.id)
			return c),
	}


static func _effects_dict(n: Nation) -> Dictionary:
	var out := {}
	for src in n.effect_sources:
		out[str(src)] = _str_dict(n.effect_sources[src])
	return out


static func _str_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k]
	return out


static func _religion_dict(r: Religion) -> Dictionary:
	return {"id": r.id, "name": r.name, "symbol": r.symbol, "color": _col(r.color), "def": str(r.def.id) if r.def != null else "",
		"parent": r.parent, "root": r.root, "founded": r.founded_year, "origin": r.origin_nation, "dogmas": Array(r.dogmas),
		"effects": _str_dict(r.effects), "missionary": r.missionary, "tolerance": r.tolerance, "zeal": r.zeal,
		"magic": r.magic, "undead": r.undead, "demons": r.demons, "alive": r.alive}


## Религии (v2). В сохранениях v1 их нет — веры назначаются заново по расам.
static func _load_religions(world: World, data: Dictionary) -> void:
	if not data.has("religions"):
		world.init_religions()
		for n in world.nations:
			n.state_religion = ReligionSystem.pick_for_race(world, n.race)
		for region in world.regions:
			var c := region.controller()
			if c >= 0:
				region.faith = {world.nations[c].state_religion: 1.0}
		return
	for rd in data.religions:
		var r := Religion.new()
		r.id = int(rd.id)
		r.name = rd.name
		r.symbol = rd.symbol
		r.color = _to_col(rd.color)
		r.def = ReligionDB.find(StringName(rd.def)) if not rd.def.is_empty() else null
		r.parent = int(rd.parent)
		r.root = int(rd.root)
		r.founded_year = int(rd.founded)
		r.origin_nation = int(rd.origin)
		r.dogmas = PackedStringArray(rd.dogmas)
		for k in rd.effects:
			r.effects[StringName(k)] = float(rd.effects[k])
		r.missionary = rd.missionary
		r.tolerance = rd.tolerance
		r.zeal = rd.zeal
		r.magic = rd.magic
		r.undead = rd.undead
		r.demons = rd.demons
		r.alive = rd.alive
		world.religions.append(r)
	for i in data.regions.size():
		var region := world.regions[i]
		region.faith.clear()
		var fd: Dictionary = data.regions[i].get("faith", {})
		for k in fd:
			region.faith[int(k)] = float(fd[k])
	for k in data.nations.size():
		var nd: Dictionary = data.nations[k]
		var n := world.nations[k]
		n.state_religion = int(nd.get("religion", -1))
		n.faith_unity = nd.get("unity", 1.0)
		var eff: Dictionary = nd.get("effects", {})
		for src in eff:
			n.set_effects(StringName(src), eff[src])


## Технологии и культура (v2). Из сохранений v1 — культура по государству,
## технологий нет (очки исследований начнут копиться с текущего уровня науки).
static func _load_techs_and_cultures(world: World, data: Dictionary) -> void:
	if data.has("cultures"):
		for cd in data.cultures:
			var c := Culture.new()
			c.id = int(cd.id)
			c.name = cd.name
			c.race = int(cd.race)
			c.color = _to_col(cd.color)
			c.customs = PackedStringArray(cd.customs)
			c.origin_nation = int(cd.origin)
			c.founded_year = int(cd.founded)
			world.cultures.append(c)
	for k in data.nations.size():
		var nd: Dictionary = data.nations[k]
		var n := world.nations[k]
		if not data.has("cultures"):
			n.culture = CultureSystem.new_culture(world, n).id
			n.tech_seen = n.tech
			continue
		for t in nd.get("techs", []):
			if TechDB.find(StringName(t)) != null:
				n.techs[StringName(t)] = true
		n.researching = StringName(nd.get("researching", ""))
		n.research = nd.get("research", 0.0)
		n.tech_seen = nd.get("tech_seen", n.tech)
		n.culture = int(nd.get("culture", -1))
		n.culture_level = nd.get("culture_level", 0.0)
	for i in data.regions.size():
		var region := world.regions[i]
		var rd: Dictionary = data.regions[i]
		if rd.has("culture"):
			region.culture = int(rd.culture)
			region.assim = rd.get("assim", 0.0)
		else:
			var c := region.controller()
			region.culture = world.nations[c].culture if c >= 0 else -1


## Разведка, тайные общества, организации, наследия (этап 8; в v1 их нет — пусто).
static func _load_intrigue(world: World, data: Dictionary) -> void:
	for k in data.nations.size():
		var nd: Dictionary = data.nations[k]
		world.nations[k].intel = nd.get("intel", 0.0)
		world.nations[k].legacy = int(nd.get("legacy", -1))
		world.nations[k].home_cell = int(nd.get("home", -1))
		world.nations[k].territory_dirty = nd.get("tdirty", true)
	for sd in data.get("societies", []):
		var s := Society.new()
		s.id = int(sd.id)
		s.name = sd.name
		s.kind = StringName(sd.kind)
		s.religion = int(sd.religion)
		s.home = int(sd.home)
		s.leader = sd.leader
		s.founded_year = int(sd.founded)
		for r in sd.influence:
			s.influence[int(r)] = float(sd.influence[r])
		s.seized = int(sd.seized)
		s.alive = sd.alive
		world.societies.append(s)
	for od in data.get("orgs", []):
		var o := Organization.new()
		o.id = int(od.id)
		o.def = OrgDB.find_org(StringName(od.def))
		if o.def == null:
			continue
		o.name = od.name
		o.members = PackedInt32Array(od.members)
		o.founder = int(od.founder)
		o.founded_year = int(od.founded)
		o.faith = int(od.faith)
		o.alive = od.alive
		for m in od.get("banned", {}):
			o.banned[int(m)] = int(od.banned[m])
		world.orgs.append(o)
	for ld in data.get("legacies", []):
		var l := Legacy.new()
		l.id = int(ld.id)
		l.name = ld.name
		l.origin = int(ld.origin)
		l.regions = PackedInt32Array(ld.regions)
		l.founded_year = int(ld.founded)
		l.until_year = int(ld.until)
		l.collector = int(ld.collector)
		l.alive = ld.alive
		world.legacies.append(l)
	# Кэш членства (Nation.org_ids) — из списков организаций.
	OrgSystem._apply_membership(world)


static func _hero_dict(h: Hero) -> Dictionary:
	return {
		"id": h.id, "name": h.name, "race": str(h.race_id), "class": str(h.hero_class.id), "level": h.level, "xp": h.xp,
		"age": h.age, "max_age": h.max_age, "born": h.born_year, "cell": h.cell, "nation": h.nation_id,
		"alive": h.alive, "ruler": h.is_ruler, "kills": h.kills, "monsters": h.monsters_slain, "epithet": h.epithet,
		"deeds": h.deeds, "move_in": h.move_in, "karma": h.karma, "artifact": h.artifact, "artifact_mult": h.artifact_mult,
		"fate": str(h.fate), "returns": h.returns, "goal": h.goal_cell, "bonds": _int_dict(h.bonds),
		"spouse": h.spouse, "mentor": h.mentor, "party": h.party_leader, "ally": h.ally_nation, "ally_until": h.ally_until,
		"vendetta": h.vendetta, "killed_by": h.killed_by, "intellect": h.intellect, "thought": h.thought,
		"parents": Array(h.parents), "children": Array(h.children), "lineage": h.lineage, "artifact_id": h.artifact_id,
		"order": h.order, "god": str(h.patron_god), "chosen": h.chosen, "awits": h._artifact_wits,
	}


## Этап 10.1: артефакты, роды, дети, ордена, милости богов.
static func _lore_dict(world: World) -> Dictionary:
	return {
		"artifacts": world.artifacts.map(func(a: Artifact) -> Dictionary: return {"def": str(a.def.id) if a.def != null else "",
			"name": a.name, "hero": a.hero, "nation": a.nation, "cell": a.cell, "year": a.created_year, "history": Array(a.history)}),
		"lineages": world.lineages,
		"births": world.hero_births,
		"orders": world.orders.map(func(o: HeroOrder) -> Dictionary: return {"name": o.name, "kind": str(o.kind), "founder": o.founder,
			"leader": o.leader, "founded": o.founded_year, "ended": o.ended_year, "karma": o.karma, "hall": o.hall_cell,
			"members": Array(o.members), "alive": o.alive, "total": o.total}),
		"boons": world.nations.map(func(n: Nation) -> Array: return [str(n.god_boon), n.god_boon_until]),
	}


static func _load_lore(world: World, data: Dictionary) -> void:
	if not data.has("lore"):
		# Старое сохранение: оружие героев (строки) становится предметами без ГСЧ.
		for h in world.heroes:
			if h.artifact.is_empty():
				continue
			var a := Artifact.new()
			a.id = world.artifacts.size()
			a.def = LoreDB.artifact(&"legendary_weapon" if h.artifact_mult >= 1.75 else (&"cursed_weapon" if h.artifact_mult >= 1.5 else &"ancient_weapon"))
			a.name = h.artifact
			a.created_year = h.born_year
			if h.alive and not h.is_ruler:
				a.hero = h.id
				h.artifact_id = a.id
			elif h.is_ruler and h.nation_id >= 0:
				a.nation = h.nation_id
			else:
				a.cell = h.cell
			world.artifacts.append(a)
		for n in world.nations:
			ArtifactSystem.apply_nation_effects(world, n)
		return
	var lore: Dictionary = data.lore
	for ad in lore.artifacts:
		var a := Artifact.new()
		a.id = world.artifacts.size()
		a.def = LoreDB.artifact(StringName(ad.def))
		a.name = ad.name
		a.hero = int(ad.hero)
		a.nation = int(ad.nation)
		a.cell = int(ad.cell)
		a.created_year = int(ad.year)
		a.history = PackedStringArray(ad.history)
		world.artifacts.append(a)
	for l in lore.lineages:
		world.lineages.append({"name": str(l.name), "founder": int(l.founder), "year": int(l.year), "heroes": int(l.heroes)})
	for b in lore.births:
		world.hero_births.append({"parents": [int(b.parents[0]), int(b.parents[1])], "race": str(b.race), "class": str(b["class"]),
			"name": str(b.name), "karma": float(b.karma), "intellect": float(b.intellect), "adult": int(b.adult),
			"lineage": int(b.lineage), "cell": int(b.cell), "born": int(b.born), "epithet": str(b.epithet)})
	for od in lore.orders:
		var o := HeroOrder.new()
		o.id = world.orders.size()
		o.name = od.name
		o.kind = StringName(od.kind)
		o.founder = int(od.founder)
		o.leader = int(od.leader)
		o.founded_year = int(od.founded)
		o.ended_year = int(od.ended)
		o.karma = od.karma
		o.hall_cell = int(od.hall)
		o.members = PackedInt32Array(od.members)
		o.alive = od.alive
		o.total = int(od.total)
		world.orders.append(o)
	for i in mini(lore.boons.size(), world.nations.size()):
		world.nations[i].god_boon = StringName(lore.boons[i][0])
		world.nations[i].god_boon_until = int(lore.boons[i][1])


static func _war_dict(w: War) -> Dictionary:
	return {"id": w.id, "name": w.name, "cause": str(w.cause), "start": w.start_year, "end": w.end_year,
		"att": Array(w.attackers), "def": Array(w.defenders), "score": w.score, "siege": w.siege_region,
		"siege_side": w.siege_side, "progress": w.siege_progress, "landing": w.siege_landing,
		"month": w.month, "day": w.day, "battles": w.battles, "casualties": w.casualties, "active": w.active}


## Парсер JSON в Godot теряет последний бит у ~30% чисел double, а за десятки
## лет такая ошибка меняет исход войны. Поэтому числа, которые не переживают
## запись в текст без потерь, пишутся как «~» + 16 hex-цифр их битов.
static func exact(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if JSON.stringify(f, "", false, true).to_float() == f:
				return f
			return EXACT_PREFIX + PackedFloat64Array([f]).to_byte_array().hex_encode()
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = exact(v[k])
			return out
		TYPE_ARRAY:
			var out := []
			out.resize(v.size())
			for i in v.size():
				out[i] = exact(v[i])
			return out
	return v


## Обратное к exact(): «~hex» снова становятся точными числами (на месте).
static func unexact(v: Variant) -> Variant:
	match typeof(v):
		TYPE_STRING:
			var s: String = v
			if s.length() == 17 and s.begins_with(EXACT_PREFIX):
				return s.substr(1).hex_decode().to_float64_array()[0]
		TYPE_DICTIONARY:
			for k in v:
				v[k] = unexact(v[k])
		TYPE_ARRAY:
			for i in v.size():
				v[i] = unexact(v[i])
	return v


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
			"techs": PackedFloat32Array(snap.get("techs", [])), "faiths": faiths})
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
	h.intellect = hd.get("intellect", h.hero_class.intellect)
	h.thought = hd.get("thought", "")
	h.parents = PackedInt32Array(hd.get("parents", []))
	h.children = PackedInt32Array(hd.get("children", []))
	h.lineage = int(hd.get("lineage", -1))
	h.artifact_id = int(hd.get("artifact_id", -1))
	h.order = int(hd.get("order", -1))
	h.patron_god = StringName(hd.get("god", ""))
	h.chosen = hd.get("chosen", false)
	h._artifact_wits = hd.get("awits", 0.0)
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


## Цвет без потерь (to_html округляет до 8 бит на канал).
static func _col(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


static func _to_col(v: Variant) -> Color:
	if typeof(v) == TYPE_STRING:
		return Color.html(v)
	return Color(v[0], v[1], v[2], v[3])


static func _raw(text: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(text) if not text.is_empty() else PackedByteArray()
