class_name SaveSections
extends "res://scripts/core/save_util.gd"
## Разделы сохранения по подсистемам (часть SaveSystem): государства,
## веры, технологии и культуры, интриги, герои и лор (артефакты, роды,
## ордена, игра за героя), войны.


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
		"pl": [h.wounds, h.gold, h.gear, h.guards, h.guards_until, h.perk_points, h.strength, h.wit, h.charm],
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
		"player": {"hero": world.player, "cmd": world.player_cmd, "choice": world.player_choice,
			"journal": world.player_journal, "rep": world.player_rep, "idle": world.player_idle},
		"bookmarks": world.bookmarks,
		"quests": world.player_quests, "offers": world.player_offers,
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
	for q in lore.get("quests", []):
		world.player_quests.append(PlayerQuests.restore(q))
	for q in lore.get("offers", []):
		world.player_offers.append(PlayerQuests.restore(q))
	for b in lore.get("bookmarks", []):
		world.bookmarks.append({"year": int(b.year), "month": int(b.month), "day": int(b.day), "kind": str(b.kind), "text": str(b.text)})
	var pl: Dictionary = lore.get("player", {})
	if not pl.is_empty():
		world.player = int(pl.hero)
		world.player_cmd = pl.cmd
		if world.player_cmd.has("path"):
			world.player_cmd.path = Array(world.player_cmd.path).map(func(x: Variant) -> int: return int(x))
			world.player_cmd.target = int(world.player_cmd.target)
		if world.player_cmd.has("wait"):
			world.player_cmd.wait = int(world.player_cmd.wait)
		world.player_choice = pl.choice
		for j in pl.journal:
			world.player_journal.append({"year": int(j.year), "month": int(j.month), "text": str(j.text)})
		world.player_rep = pl.rep
		world.player_idle = int(pl.idle)
	for i in mini(lore.boons.size(), world.nations.size()):
		world.nations[i].god_boon = StringName(lore.boons[i][0])
		world.nations[i].god_boon_until = int(lore.boons[i][1])


static func _war_dict(w: War) -> Dictionary:
	return {"id": w.id, "name": w.name, "cause": str(w.cause), "start": w.start_year, "end": w.end_year,
		"first": [w.first_attacker, w.first_defender], "att": Array(w.attackers), "def": Array(w.defenders), "score": w.score, "siege": w.siege_region,
		"siege_side": w.siege_side, "progress": w.siege_progress, "landing": w.siege_landing,
		"month": w.month, "day": w.day, "battles": w.battles, "casualties": w.casualties, "active": w.active}


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
	if hd.has("pl"):
		var pl: Array = hd.pl
		h.wounds = pl[0]
		h.gold = pl[1]
		h.gear = int(pl[2])
		h.guards = int(pl[3])
		h.guards_until = int(pl[4])
		h.perk_points = int(pl[5])
		h.strength = int(pl[6])
		h.wit = int(pl[7])
		h.charm = int(pl[8])
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
	var first: Array = wd.get("first", [w.attackers[0] if not w.attackers.is_empty() else -1, w.defenders[0] if not w.defenders.is_empty() else -1])
	w.first_attacker = int(first[0])
	w.first_defender = int(first[1])
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
