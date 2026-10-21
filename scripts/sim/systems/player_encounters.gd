class_name PlayerEncounters
extends "res://scripts/sim/systems/player_core.gd"
## События пути, встречи, поединки и выбор игрока (часть PlayerSystem).


## Случайное событие пути из data/hero_events (по месту).
static func start_event(world: World, h: Hero) -> bool:
	var owner := world.owner[h.cell]
	var pool: Array[HeroEventDef] = []
	var total := 0.0
	for res in LoreDB.hero_events():
		var e := res as HeroEventDef
		if e.chained or (e.where == &"nation" and owner < 0) or (e.where == &"wild" and owner >= 0) or not _terrain_ok(world, h, e.terrain) \
				or not _requires_ok(world, h, e.requires):
			continue
		pool.append(e)
		total += e.weight
	if pool.is_empty():
		return false
	var roll := world.rng.randf() * total
	var ev := pool[pool.size() - 1]
	for e in pool:
		roll -= e.weight
		if roll <= 0.0:
			ev = e
			break
	_show_event(world, h, ev)
	return true


## Событие по id (продолжение цепочки) — без проверки места.
static func start_event_id(world: World, h: Hero, id: StringName) -> bool:
	var ev := LoreDB.hero_event(id)
	if ev == null or not world.player_choice.is_empty():
		return false
	_show_event(world, h, ev)
	return true


## Условие события (этап 11.H): поветрие, война, чужой язык, рабство, логово, город.
static func _requires_ok(world: World, h: Hero, req: StringName) -> bool:
	var rid := world.region_of[h.cell]
	var owner := world.owner[h.cell]
	match req:
		&"":
			return true
		&"outbreak":
			return DiseaseSystem.outbreak_in(world, rid) != null
		&"war":
			return owner >= 0 and not world.diplomacy.wars_of(owner).is_empty()
		&"foreign":
			return not PlayerWorld.speaks_here(world, h)
		&"slavery":
			return owner >= 0 and world.nations[owner].slavery
		&"lair":
			return rid >= 0 and LairSystem.lair_near(world, rid) != null
		&"caravan":
			for c in world.caravans:
				if c.alive and (world.region_of[world.cities[c.from_city].cell] == rid or world.region_of[world.cities[c.to_city].cell] == rid):
					return true
			return false
		&"rumor":
			return not RumorSystem.active(world).is_empty()
	return true


static func _show_event(world: World, h: Hero, ev: HeroEventDef) -> void:
	var owner := world.owner[h.cell]
	var options: Array = []
	for i in ev.options.size():
		var cost := -float(ev.options[i].get("gold", 0.0))
		if cost > 0.0 and h.gold < cost:
			continue  # не по карману
		var label := String(ev.options[i].get("text", "…"))
		if cost > 0.0:
			label += " (%d зол.)" % int(cost)
		options.append({"text": label, "act": "event", "index": i})
	world.player_choice = {"kind": "event", "event": String(ev.id), "title": ev.title,
		"text": ev.text.format({"where": world.region_label(h.cell, "диких земель"), "owner": world.nations[owner].short_name if owner >= 0 else "?"}),
		"options": options}


static func _terrain_ok(world: World, h: Hero, terrain: StringName) -> bool:
	if terrain == &"":
		return true
	var b := world.map.biome[h.cell]
	match terrain:
		&"forest":
			return b == Biome.FOREST or b == Biome.JUNGLE
		&"mountains":
			return b == Biome.MOUNTAINS or b == Biome.HILLS
		&"desert":
			return b == Biome.DESERT or b == Biome.STEPPE
		&"swamp":
			return b == Biome.SWAMP
		&"cold":
			return b == Biome.TUNDRA or b == Biome.SNOW
		&"coast":
			var rid := world.region_of[h.cell]
			return rid >= 0 and world.regions[rid].coastal
		&"city":
			return PlayerQuests.city_here(world, h) != null
	return true


## Встреча героя игрока с другим героем (вызывает HeroSystem вместо автономной встречи).
static func encounter(world: World, h: Hero, other: Hero, hostile: bool) -> void:
	if not world.player_choice.is_empty() or not h.alive or not other.alive:
		return
	var who := "%s (%s, %s, ур. %d, %s)" % [other.display_name(), other.race.display_name.to_lower(),
		other.hero_class.display_name.to_lower(), other.level, other.alignment_name()]
	var options: Array = []
	var text := ""
	if hostile:
		text = "%s преграждает вам путь и обнажает оружие. Он кажется %s." % [who, _compare(h, other)]
		options.append({"text": "Принять бой", "act": "duel", "other": other.id})
		options.append({"text": "Бежать (нужен ясный ум)", "act": "flee", "other": other.id})
		if absf(h.karma - other.karma) < 0.8:
			options.append({"text": "Попытаться договориться", "act": "parley", "other": other.id})
	else:
		text = "В пути вам встречается %s. Отношение к вам: %+.2f." % [who, other.bond(h.id)]
		options.append({"text": "Заговорить", "act": "talk", "other": other.id})
		options.append({"text": "Вызвать на поединок", "act": "duel", "other": other.id})
		if h.spouse < 0 and other.spouse < 0 and h.race == other.race and h.bond(other.id) > 0.4:
			options.append({"text": "Предложить союз сердец", "act": "propose", "other": other.id})
		options.append({"text": "Пройти мимо", "act": "pass", "other": other.id})
	world.player_choice = {"kind": "meet", "title": "Встреча", "text": text, "options": options}


## Поединок героя игрока: победитель — по силе (со спутниками) и удаче.
## Проигравший игрок получает рану (гибнет при ранах ≥ 1 или от руки злодея),
## победивший — решает судьбу соперника (выбор «добить / пощадить»).
static func player_duel(world: World, h: Hero, o: Hero) -> String:
	var rng := world.rng
	var pa := fight_power(world, h) * rng.randf_range(0.6, 1.4)
	var pb := o.power() * rng.randf_range(0.6, 1.4)
	if pa >= pb:
		h.kills += 1
		h.add_xp(world, 1.0 + o.level * 0.5)
		if h.kills >= 3 and h.epithet.is_empty():
			h.epithet = "Непобедимый"
		if h.vendetta == o.id:
			h.vendetta = -1
		world.player_choice = {"kind": "mercy", "title": "Победа", "text": "%s повержен и молит о пощаде." % o.display_name(),
			"options": [{"text": "Добить", "act": "kill", "other": o.id}, {"text": "Пощадить", "act": "spare", "other": o.id}]}
		return "Вы одолели героя %s." % o.display_name()
	o.kills += 1
	o.add_xp(world, 1.0 + h.level * 0.5)
	h.add_deed(world, "проиграл поединок герою %s" % o.name)
	if o.karma < -0.5 and h.wounds > 0.4 and rng.randf() < 0.5:
		world.log_event(&"hero", "Поединок: %s сразил героя %s." % [o.display_name(), h.display_name()])
		h.die(world, o)
		return "%s не знает пощады." % o.display_name()
	h.wounds = minf(1.0, h.wounds + rng.randf_range(DUEL_WOUND.x, DUEL_WOUND.y))
	if h.wounds >= 1.0:
		world.log_event(&"hero", "Поединок: %s сразил героя %s." % [o.display_name(), h.display_name()])
		h.die(world, o)
		return "Раны оказались смертельными."
	return "%s одолел вас; израненный (раны %d%%), вы отступили." % [o.display_name(), roundi(h.wounds * 100.0)]


static func _compare(h: Hero, other: Hero) -> String:
	var ratio := other.power() / maxf(1.0, h.power())
	if ratio > 1.6:
		return "намного сильнее вас"
	if ratio > 1.1:
		return "сильнее вас"
	if ratio > 0.8:
		return "равным вам"
	return "слабее вас"


## Игрок делает выбор (индекс варианта). Возвращает текст исхода.
static func choose(world: World, index: int) -> String:
	var choice := world.player_choice
	if choice.is_empty() or index < 0 or index >= (choice.options as Array).size():
		return ""
	var opt: Dictionary = choice.options[index]
	world.player_choice = {}
	var h := hero_of(world)
	var result := ""
	match String(opt.act):
		"heir":
			take_control(world, int(opt.hero))
			result = "Вы продолжаете путь за героя %s." % world.heroes[int(opt.hero)].display_name()
		"pick":
			world.player = -1
			world.player_cmd = {}
			result = "Выберите нового героя в панели «Герои»."
		"observe":
			release(world)
			return "Вы вернулись к наблюдению за миром."
		"event":
			result = _event_outcome(world, h, LoreDB.hero_event(StringName(choice.event)), int(opt.index))
		"talk":
			var o := world.heroes[int(opt.other)]
			HeroRelations.meet(world, h, o, world.region_label(h.cell, "диких землях"))
			result = "Вы поговорили с героем %s (отношение %+.2f)." % [o.display_name(), h.bond(o.id)]
		"duel":
			var o := world.heroes[int(opt.other)]
			result = player_duel(world, h, o)
		"flee":
			var o := world.heroes[int(opt.other)]
			if world.rng.randf() < 0.3 + h.wits() * 0.6:
				var region := world.region_at(h.cell)
				if region != null and not region.neighbors.is_empty():
					var nb := world.regions[region.neighbors[world.rng.randi_range(0, region.neighbors.size() - 1)]]
					if not nb.cells.is_empty():
						MovementSystem.send(world, h.m, nb.cells[world.rng.randi_range(0, nb.cells.size() - 1)])
				h.add_bond(o, -0.2)
				result = "Вы скрылись от героя %s." % o.display_name()
			else:
				result = "Уйти не удалось — бой неизбежен. " + player_duel(world, h, o)
		"parley":
			var o := world.heroes[int(opt.other)]
			if world.rng.randf() < 0.4 + h.wits() * 0.4 + h.charm * 0.05:
				o.add_bond(h, 0.3)
				h.add_bond(o, 0.2)
				result = "Слово оказалось острее меча: %s опустил оружие." % o.display_name()
			else:
				result = "Переговоры не удались. " + player_duel(world, h, o)
		"propose":
			var o := world.heroes[int(opt.other)]
			if o.bond(h.id) > 0.3 and o.spouse < 0:
				h.spouse = o.id
				o.spouse = h.id
				h.add_deed(world, "сочетался браком с героем %s" % o.name)
				o.add_deed(world, "сочетался браком с героем %s" % h.name)
				world.log_event(&"hero", "Герои %s и %s сочетались браком." % [h.display_name(), o.display_name()])
				result = "%s ответил согласием!" % o.display_name()
			else:
				o.add_bond(h, -0.1)
				result = "%s вежливо отказал." % o.display_name()
		"take_quest":
			result = PlayerQuests.accept(world, h, int(opt.index))
		"buy":
			result = PlayerQuests.buy(world, h, String(opt.item), float(opt.cost))
		"buy_good":
			result = PlayerWorld.buy_good(world, h, int(opt.good), float(opt.amount), float(opt.cost))
		"sell_good":
			result = PlayerWorld.sell_good(world, h, int(opt.good), float(opt.amount), float(opt.cost))
		"kill":
			var o := world.heroes[int(opt.other)]
			h.karma = clampf(h.karma - 0.05 - maxf(0.0, o.karma) * 0.15, -1.0, 1.0)
			h.add_deed(world, "сразил в поединке героя %s" % o.name)
			world.log_event(&"hero", "Поединок: %s сразил героя %s." % [h.display_name(), o.display_name()])
			o.die(world, h)
			result = "%s пал от вашей руки." % o.display_name()
		"spare":
			var o := world.heroes[int(opt.other)]
			h.karma = minf(1.0, h.karma + 0.05)
			o.add_bond(h, 0.25)
			o.level = maxi(1, o.level - 1)
			o.vendetta = -1
			h.add_deed(world, "одолел героя %s и пощадил его" % o.name)
			result = "Вы пощадили героя %s. Он этого не забудет." % o.display_name()
		_:
			result = "Вы продолжаете путь."
	if world.player >= 0:
		note(world, result)
	return result


static func _event_outcome(world: World, h: Hero, ev: HeroEventDef, index: int) -> String:
	if ev == null or h == null or index >= ev.options.size():
		return ""
	var opt: Dictionary = ev.options[index]
	var owner := world.owner[h.cell]
	var success := true
	if opt.has("power"):
		var threat := float(opt.power) * h.hero_class.power * 5.0
		success = h.power() * world.rng.randf_range(0.6, 1.4) > threat * world.rng.randf_range(0.6, 1.2)
	if not success:
		h.add_xp(world, float(opt.get("xp", 0.0)) * 0.3)
		var hurt := float(opt.get("risk", 0.0)) * 3.0
		if hurt > 0.0:
			wound(world, h, hurt * world.rng.randf_range(0.6, 1.2), "погиб: " + ev.title.to_lower())
			if not h.alive:
				return "%s — и это стало концом пути." % String(opt.get("fail", "Неудача"))
			return "%s Вы ранены (%d%%)." % [String(opt.get("fail", "Не вышло.")), roundi(h.wounds * 100.0)]
		return String(opt.get("fail", "Не вышло."))
	h.karma = clampf(h.karma + float(opt.get("karma", 0.0)), -1.0, 1.0)
	h.add_xp(world, float(opt.get("xp", 0.0)))
	if owner >= 0 and opt.has("rep"):
		rep(world, "n%d" % owner, float(opt.rep))
	var rid := world.region_of[h.cell]
	if rid >= 0 and opt.has("faith") and world.regions[rid].main_faith() >= 0:
		rep(world, "r%d" % world.regions[rid].main_faith(), float(opt.faith))
	var text := String(opt.get("result", "Так и было."))
	if opt.has("gold"):
		h.gold = maxf(0.0, h.gold + float(opt.gold))
		if float(opt.gold) > 0.0:
			text += " +%d золотых." % int(opt.gold)
	if opt.has("heal"):
		h.wounds = maxf(0.0, h.wounds - float(opt.heal))
	if opt.has("wound"):
		wound(world, h, float(opt.wound), "погиб: " + ev.title.to_lower())
		if not h.alive:
			return text
	if opt.has("quest") and world.player_quests.size() < PlayerQuests.MAX_ACTIVE:
		var q := PlayerQuests.rumor_quest(world, h, String(opt.quest))
		if not q.is_empty():
			world.player_quests.append(q)
			text += " Новое задание: %s." % q.title
	if opt.has("cargo"):
		var gi := MarketDB.index_of(StringName(opt.cargo))
		if gi >= 0:
			var amount := minf(float(opt.get("amount", 5.0)), PlayerWorld.cargo_cap(h) - PlayerWorld.cargo_total(h))
			if amount > 0.0:
				h.cargo[gi] = float(h.cargo.get(gi, 0.0)) + amount
				# Учёт рынка: товар пришёл в мир из события — как произведённый.
				world.market_totals["made"] = float(world.market_totals.get("made", 0.0)) + amount
				text += " В мешке: +%d ед. «%s»." % [int(amount), (MarketDB.all()[gi] as GoodDef).display_name]
	if opt.has("capture") and owner >= 0:
		PlayerWorld.capture(world, h, owner, String(opt.capture))
		return text
	if opt.has("swear") and owner >= 0 and h.nation_id != owner:
		h.leave_service(world)
		h.nation_id = owner
		world.nations[owner].hero_ids.append(h.id)
		rep(world, "n%d" % owner, 0.2)
	if opt.has("next"):
		world.player_chain.append({"event": String(opt.next), "at": world.year * 12 + world.month + int(opt.get("delay", 3))})
	if opt.has("item") and h.artifact_id < 0:
		var a := ArtifactSystem.create(world, StringName(opt.item), h, "", ev.title.to_lower())
		if a != null:
			text += " Теперь у вас есть %s." % a.name
	h.add_deed(world, "%s: %s" % [ev.title.to_lower(), String(opt.text).to_lower()])
	return text


## Репутация игрока для панели: [название, значение] по убыванию модуля.
static func reputation(world: World) -> Array:
	var res: Array = []
	for k: String in world.player_rep:
		var id := int(k.substr(1))
		var name := ""
		match k[0]:
			"n":
				name = world.nations[id].name if id < world.nations.size() else "?"
			"r":
				name = "вера «%s»" % world.religions[id].name if id < world.religions.size() else "?"
			"o":
				name = world.orders[id].name if id < world.orders.size() else "?"
		res.append([name, float(world.player_rep[k])])
	res.sort_custom(func(a: Array, b: Array) -> bool: return absf(a[1]) > absf(b[1]))
	return res
