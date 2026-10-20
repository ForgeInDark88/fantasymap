class_name PlayerSystem
extends "res://scripts/sim/systems/player_encounters.gd"
## Режим «Сыграй за героя» (логика, без интерфейса). Игрок управляет одним
## героем (World.player): отдаёт команды (World.player_cmd), а в пути и при
## встречах получает выбор из 2–4 вариантов (World.player_choice) — пока выбор
## не сделан, герой ждёт, а интерфейс ставит игру на паузу. Остальной мир
## живёт сам: автономное поведение HeroSystem для героя игрока отключено, но
## другие герои встречают его и бьются с ним по обычным правилам. Без команд
## герой отдыхает и не гибнет без причины (старость, бой, кара богов — причины).
## Гибель героя открывает «Чертоги Судьбы»: продолжить за наследника или
## ученика, выбрать другого героя или вернуться к наблюдению.

## Команды: id, надпись, сколько месяцев занимает.
const COMMANDS := [
	[&"travel", "Идти в регион", 0], [&"hunt", "Охота на чудовищ", 1], [&"explore", "Исследовать руины и пещеры", 2],
	[&"good", "Доброе деяние", 1], [&"evil", "Злое деяние", 1], [&"swear", "Присягнуть державе края", 0],
	[&"join_order", "Вступить в орден", 0], [&"faith", "Принять веру края", 0], [&"friends", "Искать друзей", 1],
	[&"marry", "Предложить брак", 0], [&"mentor", "Наставничество", 1], [&"mercenary", "Наняться на войну", 0],
	[&"great", "Великое деяние", 3], [&"rest", "Отдыхать и лечиться", 1],
	[&"shop", "Рынок и лекарь", 0], [&"board", "Доска заданий", 0], [&"invite", "Позвать в отряд", 0],
	[&"quest_go", "К цели задания", 0],
]


static func command_name(kind: StringName) -> String:
	for c in COMMANDS:
		if c[0] == kind:
			return c[1]
	return String(kind)


## Можно ли отдать команду сейчас; пустая строка — можно, иначе — почему нет.
static func why_not(world: World, kind: StringName) -> String:
	var h := hero_of(world)
	if h == null or not h.alive:
		return "нет героя"
	if not world.player_choice.is_empty():
		return "ждёт вашего решения"
	var owner := world.owner[h.cell] if h.cell >= 0 else -1
	var rid := world.region_of[h.cell] if h.cell >= 0 else -1
	match kind:
		&"explore":
			if RuinSystem.near(world, h.cell) == null and _cave_here(world, h) == null:
				return "рядом нет руин и неисследованных пещер"
		&"swear":
			if owner < 0:
				return "здесь ничья земля"
			if h.nation_id == owner:
				return "уже служит этой державе"
		&"join_order":
			if h.order >= 0 and world.orders[h.order].alive:
				return "уже в ордене"
			if _order_near(world, h) == null:
				return "рядом нет ордена вашего рода и натуры"
		&"faith":
			if rid < 0 or world.regions[rid].main_faith() < 0:
				return "у края нет веры"
		&"marry":
			if h.spouse >= 0 and world.heroes[h.spouse].alive:
				return "уже в браке"
			if _suitor(world, h) == null:
				return "рядом нет героя, который ответит согласием"
		&"mentor":
			if _mentor_target(world, h) == null:
				return "рядом нет ни наставника, ни ученика"
		&"mercenary":
			if h.nation_id >= 0 or h.ally_nation >= 0:
				return "уже воюет за державу"
		&"great":
			if h.level < HeroSystem.MIN_GREAT_LEVEL:
				return "нужен %d-й уровень" % HeroSystem.MIN_GREAT_LEVEL
		&"shop", &"board":
			if PlayerQuests.city_here(world, h) == null:
				return "в этом краю нет города"
		&"invite":
			if _companion_candidate(world, h) == null:
				return "рядом нет героя, готового идти с вами"
		&"quest_go":
			if world.player_quests.is_empty():
				return "нет заданий"
	return ""


## Отдать команду. arg — регион для travel. Возвращает пустую строку или причину отказа.
static func command(world: World, kind: StringName, arg: int = -1) -> String:
	var reason := why_not(world, kind)
	if not reason.is_empty():
		return reason
	var h := hero_of(world)
	world.player_idle = 0
	if kind == &"travel":
		var plan := plan_path(world, world.region_of[h.cell], arg)
		if plan.is_empty():
			return "туда не добраться"
		world.player_cmd = {"kind": "travel", "target": arg, "path": plan.path, "costs": plan.costs, "wait": 0}
		var target := world.regions[arg]
		world.ensure_region_name(target)
		note(world, "В путь — в регион %s (≈%d мес.)." % [target.name, int(plan.months)])
		h.thought = "Иду в регион %s." % target.name
		return ""
	if kind == &"quest_go":
		var q := world.player_quests[clampi(arg, 0, world.player_quests.size() - 1)]
		var cell := PlayerQuests.target_cell(world, q)
		if cell < 0 or world.region_of[cell] < 0:
			return "цель задания не найти"
		if world.region_of[cell] == world.region_of[h.cell]:
			return "вы уже на месте"
		return command(world, &"travel", world.region_of[cell])
	for c in COMMANDS:
		if c[0] == kind:
			world.player_cmd = {"kind": String(kind), "wait": int(c[2])}
	_execute(world, h, kind)
	if kind == &"shop" or kind == &"board":
		world.player_cmd = {}
	return ""


## Путь по графу регионов: [путь регионов, месяцы на шаг]. Дорога между
## городами соседних краёв ускоряет шаг вдвое; если посуху не дойти —
## морской переход от побережья до побережья.
static func plan_path(world: World, from: int, to: int) -> Dictionary:
	if from < 0 or to < 0 or to >= world.regions.size() or world.regions[to].cells.is_empty():
		return {}
	if from == to:
		return {"path": [], "costs": [], "months": 0}
	var prev := {from: -1}
	var queue: Array[int] = [from]
	var qi := 0
	while qi < queue.size() and not prev.has(to):
		var r := queue[qi]
		qi += 1
		for nb in world.regions[r].neighbors:
			if not prev.has(nb) and not world.regions[nb].cells.is_empty():
				prev[nb] = r
				queue.append(nb)
	var path: Array = []
	var costs: Array = []
	if prev.has(to):
		var cur := to
		while cur != from:
			path.push_front(cur)
			cur = prev[cur]
		var roads := _road_pairs(world)
		var last := from
		for r in path:
			costs.append(0.5 if roads.has(Vector2i(mini(last, r), maxi(last, r))) else 1.0)
			last = r
	elif world.regions[from].coastal and world.regions[to].coastal:
		path = [to]
		costs = [float(SEA_MONTHS)]
	else:
		return {}
	var months := 0.0
	for c in costs:
		months += c
	return {"path": path, "costs": costs, "months": ceili(months)}


static func _road_pairs(world: World) -> Dictionary:
	var res := {}
	for road in world.roads:
		if not road.alive or road.sea:
			continue
		var ra := world.region_of[world.cities[road.a].cell]
		var rb := world.region_of[world.cities[road.b].cell]
		if ra != rb and ra >= 0 and rb >= 0:
			res[Vector2i(mini(ra, rb), maxi(ra, rb))] = true
	return res


static func _execute(world: World, h: Hero, kind: StringName) -> void:
	var where := world.region_label(h.cell, "диких землях")
	var owner := world.owner[h.cell]
	var deeds := h.deeds.size()
	match kind:
		&"hunt":
			if world.rng.randf() < HUNT_RISK * 6.0 * (1.3 - h.wits() * 0.6) * (0.5 if h.level >= 4 else 1.0):
				note(world, "Чудовище в регионе %s оказалось сильнее — вы ранены." % where)
				wound(world, h, world.rng.randf_range(HUNT_WOUND.x, HUNT_WOUND.y), "погиб в схватке с чудовищем в регионе " + where)
				return
			h.monsters_slain += 1
			if owner >= 0:
				var bounty := roundf(world.rng.randf_range(BOUNTY.x, BOUNTY.y))
				h.gold += bounty
				note(world, "Держава %s заплатила за голову чудовища %d золотых." % [world.nations[owner].short_name, int(bounty)])
			PlayerQuests.check(world, h, &"hunt")
			h.add_xp(world, 2.0)
			h.add_deed(world, "сразил чудовище в регионе " + where)
			if owner >= 0:
				rep(world, "n%d" % owner, 0.03)
			note(world, "Охота удалась: чудовище в регионе %s сражено." % where)
		&"explore":
			var cave := _cave_here(world, h)
			if cave != null and (RuinSystem.near(world, h.cell) == null or world.rng.randf() < 0.5):
				cave.explored = true
				h.add_xp(world, 3.0)
				h.add_deed(world, "спустился в %s и вернулся живым" % cave.name)
				note(world, "Вы исследовали пещеру «%s»." % cave.name)
			else:
				RuinSystem.hero_explore(world, h, true)
				if h.alive and h.deeds.size() > deeds:
					var loot := roundf(world.rng.randf_range(LOOT.x, LOOT.y))
					h.gold += loot
					note(world, "Руины: %s. Ваша доля добычи — %d золотых." % [h.deeds[h.deeds.size() - 1], int(loot)])
			if h.alive:
				PlayerQuests.check(world, h, &"explore")
		&"good":
			HeroSystem.new()._good_deed(world, h)
			if owner >= 0:
				rep(world, "n%d" % owner, 0.05)
		&"evil":
			HeroSystem.new()._evil_deed(world, h)
			h.gold += roundf(world.rng.randf_range(5.0, 25.0))
			if owner >= 0:
				rep(world, "n%d" % owner, -0.1)
		&"swear":
			h.leave_service(world)
			h.nation_id = owner
			world.nations[owner].hero_ids.append(h.id)
			h.add_deed(world, "присягнул государству %s" % world.nations[owner].name)
			rep(world, "n%d" % owner, 0.3)
			world.log_event(&"hero", "Герой %s присягнул государству %s." % [h.display_name(), world.nations[owner].name], PackedInt32Array([owner]))
		&"join_order":
			var o := _order_near(world, h)
			OrderSystem.join(world, o, h)
			rep(world, "o%d" % o.id, 0.3)
		&"faith":
			var faith := world.regions[world.region_of[h.cell]].main_faith()
			rep(world, "r%d" % faith, 0.3)
			h.patron_god = &""
			var gods := GodSystem.gods_of(world, faith)
			if not gods.is_empty():
				var best := gods[0]
				for g in gods:
					if absf(g.karma - h.karma) < absf(best.karma - h.karma):
						best = g
				h.patron_god = best.id
			h.add_deed(world, "принял веру «%s»" % world.religions[faith].name)
		&"friends":
			var other := _someone_here(world, h)
			if other != null:
				HeroRelations.meet(world, h, other, where)
				note(world, "Вы провели время с героем %s (отношение %+.2f)." % [other.display_name(), h.bond(other.id)])
			else:
				h.add_xp(world, 0.3)
				note(world, "В регионе %s не нашлось других героев — только трактирщик." % where)
		&"marry":
			var s := _suitor(world, h)
			h.spouse = s.id
			s.spouse = h.id
			h.add_deed(world, "сочетался браком с героем %s" % s.name)
			s.add_deed(world, "сочетался браком с героем %s" % h.name)
			world.log_event(&"hero", "Герои %s и %s сочетались браком в регионе %s." % [h.display_name(), s.display_name(), where])
		&"mentor":
			var t := _mentor_target(world, h)
			if t.level > h.level:
				h.mentor = t.id
				h.add_xp(world, 2.0 + t.level * 0.2)
				h.add_deed(world, "стал учеником героя %s" % t.name)
			else:
				t.mentor = h.id
				t.add_xp(world, 2.0 + h.level * 0.2)
				h.add_deed(world, "взял в ученики героя %s" % t.name)
		&"mercenary":
			HeroRelations._join_war(world, h)
			if h.ally_nation < 0:
				note(world, "Никто поблизости не нуждается в наёмном мече.")
		&"great":
			HeroSystem.new()._great_deed(world, h)
		&"rest":
			var city := PlayerQuests.city_here(world, h)
			note(world, "Отдых %s." % (("в городе " + city.name) if city != null else "в регионе " + where))
		&"shop":
			PlayerQuests.open_shop(world, h)
		&"board":
			PlayerQuests.open_board(world, h)
		&"invite":
			var c := _companion_candidate(world, h)
			c.party_leader = h.id
			c.cell = h.cell
			c.add_bond(h, 0.1)
			h.add_deed(world, "позвал в свой отряд героя %s" % c.name)
			c.add_deed(world, "присоединился к отряду героя %s" % h.name)
	if h.alive and h.deeds.size() > deeds and kind != &"explore":
		note(world, h.deeds[h.deeds.size() - 1].substr(0, 1).to_upper() + h.deeds[h.deeds.size() - 1].substr(1) + ".")


static func _cave_here(world: World, h: Hero) -> Cave:
	var rid := world.region_of[h.cell]
	for c in world.caves:
		if c.entrance and not c.explored and c.kind == &"ruins" and world.region_of[c.cell] == rid:
			return c
	return null


static func _order_near(world: World, h: Hero) -> HeroOrder:
	var kind: StringName = OrderSystem.KIND_BY_CLASS.get(h.hero_class.id, &"knights")
	var rid := world.region_of[h.cell]
	for o in world.orders:
		if not o.alive or o.kind != kind or absf(o.karma - h.karma) > OrderSystem.KARMA_GAP:
			continue
		if o.hall_cell >= 0 and world.region_of[o.hall_cell] == rid:
			return o
		for m in o.members:
			var mh := world.heroes[m]
			if mh.alive and mh.cell >= 0 and world.region_of[mh.cell] == rid:
				return o
	return null


static func _someone_here(world: World, h: Hero) -> Hero:
	var rid := world.region_of[h.cell]
	for o in world.wandering_heroes():
		if o != h and o.alive and o.cell >= 0 and world.region_of[o.cell] == rid:
			return o
	return null


static func _suitor(world: World, h: Hero) -> Hero:
	var rid := world.region_of[h.cell]
	for o in world.wandering_heroes():
		if o != h and o.alive and o.spouse < 0 and o.race == h.race and o.cell >= 0 and world.region_of[o.cell] == rid \
				and h.bond(o.id) > 0.4 and o.bond(h.id) > 0.4:
			return o
	return null


static func _mentor_target(world: World, h: Hero) -> Hero:
	var rid := world.region_of[h.cell]
	for o in world.wandering_heroes():
		if o != h and o.alive and o.cell >= 0 and world.region_of[o.cell] == rid and absi(o.level - h.level) >= 3:
			if (o.level > h.level and h.mentor < 0) or (o.level < h.level and o.mentor < 0):
				return o
	return null


# ---------------------------------------------------------------------------
# Месяц героя игрока (вызывает HeroSystem вместо автономного поведения)
# ---------------------------------------------------------------------------


static func tick_month(world: World, h: Hero) -> void:
	if not world.player_choice.is_empty():
		return  # ждёт решения игрока
	if h.id % Simulation.MONTHS == world.month:
		_yearly(world, h)
		if not h.alive:
			return
	h.add_xp(world, 0.1)
	var cmd := world.player_cmd
	if h.wounds > 0.0:
		var heal := HEAL_IDLE
		if not cmd.is_empty() and cmd.kind == "rest":
			heal = HEAL_CITY if PlayerQuests.city_here(world, h) != null else HEAL_REST
		h.wounds = maxf(0.0, h.wounds - heal)
	PlayerQuests.check(world, h, &"month")
	if not h.alive:
		return
	if cmd.is_empty():
		world.player_idle += 1
		if world.rng.randf() < EVENT_CHANCE:
			start_event(world, h)
		return
	if int(cmd.get("wait", 0)) > 0:
		cmd.wait = int(cmd.wait) - 1
		return
	if cmd.kind == "travel":
		_travel_step(world, h, cmd)
		if h.alive and world.player_choice.is_empty() and world.rng.randf() < TRAVEL_EVENT_CHANCE:
			start_event(world, h)
		return
	world.player_cmd = {}


static func _travel_step(world: World, h: Hero, cmd: Dictionary) -> void:
	var path: Array = cmd.path
	var costs: Array = cmd.costs
	var budget := 1.0
	while not path.is_empty() and budget > 0.0:
		var need := float(costs[0])
		if need > budget:
			costs[0] = need - budget
			return
		budget -= need
		var r: int = path.pop_front()
		costs.pop_front()
		var region := world.regions[r]
		h.cell = region.cells[world.rng.randi_range(0, region.cells.size() - 1)]
	if path.is_empty():
		var region := world.region_at(h.cell)
		world.ensure_region_name(region)
		note(world, "Вы пришли в регион %s." % region.name)
		h.thought = "Пришёл в регион %s." % region.name
		if h.artifact_id < 0:
			ArtifactSystem.try_pick_up(world, h)
		world.player_cmd = {}
		PlayerQuests.check(world, h, &"arrive")


## Годовые дела героя игрока: возраст, служба, семья, боги. Ничего не решает за игрока.
static func _yearly(world: World, h: Hero) -> void:
	h.age += 1
	if h.age > h.max_age:
		world.log_event(&"hero", "Умер от старости герой %s, прославленный %d деяниями." % [h.display_name(), h.deeds.size()])
		h.die(world)
		return
	if h.ally_nation >= 0 and (world.year >= h.ally_until or not world.nations[h.ally_nation].alive):
		h.ally_nation = -1
		note(world, "Срок наёмной службы истёк.")
	if h.vendetta >= 0 and not world.heroes[h.vendetta].alive:
		h.vendetta = -1
	if h.guards > 0 and world.year >= h.guards_until:
		h.guards = 0
		note(world, "Срок найма охраны вышел — бойцы ушли.")
	if h.ally_nation >= 0:
		h.gold += 20.0  # жалованье наёмника
	if h.nation_id >= 0 and not world.nations[h.nation_id].alive:
		h.leave_service(world)
		note(world, "Держава, которой вы служили, пала.")
	if h.artifact_id >= 0:
		var a := world.artifacts[h.artifact_id]
		if a.def != null and a.def.karma_drift != 0.0:
			h.karma = clampf(h.karma + a.def.karma_drift, -1.0, 1.0)
	LineageSystem.hero_yearly(world, h)
	if h.patron_god != &"":
		GodSystem.hero_yearly(world, h)
