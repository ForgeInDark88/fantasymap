class_name PlayerSystem
extends RefCounted
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
## Шанс в месяц события в пути (в дороге — выше).
const EVENT_CHANCE := 0.06
const TRAVEL_EVENT_CHANCE := 0.12
## Морской переход между прибрежными краями (месяцев).
const SEA_MONTHS := 3
## Предел записей журнала.
const JOURNAL_MAX := 200
## Риск охоты на чудовищ (ниже, чем у автономных героев: игрок выбирает сам).
const HUNT_RISK := 0.02
## Раны: заживление в месяц (в пути и без дела / отдых / отдых в городе), рана на охоте, в поединке.
const HEAL_IDLE := 0.04
const HEAL_REST := 0.12
const HEAL_CITY := 0.25
const HUNT_WOUND := Vector2(0.2, 0.45)
const DUEL_WOUND := Vector2(0.3, 0.7)
## Награда державы за чудовище и доля добычи в руинах (золотом).
const BOUNTY := Vector2(5.0, 15.0)
const LOOT := Vector2(10.0, 40.0)
## Стартовый кошель своего героя; сила спутника в бою героя игрока.
const START_GOLD := 30.0
const COMPANION_SHARE := 0.5
## Развитие: что даёт очко.
const PERKS := {"strength": "Сила (+8% к силе)", "wit": "Ум (+0.04 к уму)", "charm": "Обаяние (скидки, переговоры, репутация)"}


static func hero_of(world: World) -> Hero:
	return world.heroes[world.player] if world.player >= 0 and world.player < world.heroes.size() else null


static func is_player(world: World, hero: Hero) -> bool:
	return world.player == hero.id and world.player >= 0


static func note(world: World, text: String) -> void:
	world.player_journal.append({"year": world.year, "month": world.month, "text": text})
	if world.player_journal.size() > JOURNAL_MAX:
		world.player_journal.remove_at(0)


# ---------------------------------------------------------------------------
# Начало и конец игры за героя
# ---------------------------------------------------------------------------

## Взять под управление героя-странника.
static func take_control(world: World, hero_id: int) -> bool:
	if hero_id < 0 or hero_id >= world.heroes.size():
		return false
	var h := world.heroes[hero_id]
	if not h.alive or h.is_ruler:
		return false
	world.player = hero_id
	world.count(&"player_heroes")
	world.player_cmd = {}
	world.player_choice = {}
	world.player_idle = 0
	h.goal_cell = -1
	h.party_leader = -1
	note(world, "Вы — %s, %s, %s. Мир ждёт ваших дел." % [h.display_name(), h.race.display_name.to_lower(), h.hero_class.display_name.to_lower()])
	return true


## Создать своего героя: раса, класс, имя, стартовый регион.
static func create_hero(world: World, race: RaceDef, cls: HeroClassDef, name: String, region_id: int) -> Hero:
	if race == null or cls == null or region_id < 0 or region_id >= world.regions.size() or world.regions[region_id].cells.is_empty():
		return null
	var region := world.regions[region_id]
	world.ensure_region_name(region)
	var clean := name.strip_edges()
	if clean.is_empty() or world.used_names.has(clean):
		clean = ""
	var hero := HeroSystem.make_hero(world, race, cls, region.cells[world.rng.randi_range(0, region.cells.size() - 1)], clean)
	if not clean.is_empty():
		world.used_names[clean] = true
	hero.level = 1
	hero.gold = START_GOLD
	hero.add_deed(world, "начал свой путь в регионе %s" % region.name)
	world.log_event(&"hero", "В регионе %s начал свой путь герой %s — %s, %s." % [region.name, hero.name,
		race.display_name.to_lower(), cls.display_name.to_lower()])
	take_control(world, hero.id)
	return hero


## Вернуться к наблюдению.
static func release(world: World) -> void:
	world.player = -1
	world.player_cmd = {}
	world.player_choice = {}
	world.player_journal.clear()
	world.player_rep.clear()
	world.player_quests.clear()
	world.player_offers.clear()
	world.player_idle = 0


## Кем можно продолжить после гибели: дети, ученики, супруг, спутники.
static func successors(world: World, hero: Hero) -> Array[Hero]:
	var res: Array[Hero] = []
	var ids: Array[int] = []
	ids.append_array(Array(hero.children))
	for o in world.heroes:
		if o.mentor == hero.id or o.party_leader == hero.id:
			ids.append(o.id)
	if hero.spouse >= 0:
		ids.append(hero.spouse)
	for id in ids:
		var h := world.heroes[id]
		if h.alive and not h.is_ruler and not res.has(h):
			res.append(h)
	return res


## Герой игрока погиб: «Чертоги Судьбы» с выбором продолжения (вызывает Hero.die).
static func on_death(world: World, hero: Hero) -> void:
	world.count(&"player_deaths")
	note(world, "%s пал. Душа уходит в Чертоги Судьбы." % hero.display_name())
	var options: Array = []
	for s in successors(world, hero).slice(0, 2):
		options.append({"text": "Продолжить за героя %s" % s.display_name(), "act": "heir", "hero": s.id})
	options.append({"text": "Выбрать другого героя", "act": "pick"})
	options.append({"text": "Вернуться к наблюдению", "act": "observe"})
	world.player_cmd = {}
	world.player_choice = {"kind": "death", "title": "Чертоги Судьбы",
		"text": "%s погиб на %d-м году жизни, совершив %d деяний. Судьба ещё решит участь его души, а ваша история может продолжиться." % [
			hero.display_name(), hero.age, hero.deeds.size()], "options": options}


# ---------------------------------------------------------------------------
# Команды
# ---------------------------------------------------------------------------

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


static func rep(world: World, key: String, amount: float) -> void:
	world.player_rep[key] = clampf(float(world.player_rep.get(key, 0.0)) + amount, -1.0, 1.0)


## Рана героя игрока; при ранах ≥ 1 — гибель (cause — для летописи).
static func wound(world: World, h: Hero, amount: float, cause: String) -> void:
	h.wounds = minf(1.0, h.wounds + amount)
	if h.wounds >= 1.0:
		world.log_event(&"hero", "Герой %s %s." % [h.display_name(), cause])
		h.die(world)
	elif h.wounds > 0.6:
		note(world, "Раны тяжелы (%d%%): пора к лекарю или на отдых." % roundi(h.wounds * 100.0))


## Сила в бою с учётом спутников по отряду.
static func fight_power(world: World, h: Hero) -> float:
	var p := h.power()
	for o in world.wandering_heroes():
		if o.party_leader == h.id and o.alive and o.cell >= 0 and h.cell >= 0 and world.region_of[o.cell] == world.region_of[h.cell]:
			p += o.power() * COMPANION_SHARE
	return p


static func companions(world: World, h: Hero) -> Array[Hero]:
	var res: Array[Hero] = []
	for o in world.wandering_heroes():
		if o.party_leader == h.id and o.alive:
			res.append(o)
	return res


static func _companion_candidate(world: World, h: Hero) -> Hero:
	var rid := world.region_of[h.cell]
	for o in world.wandering_heroes():
		if o != h and o.alive and o.party_leader < 0 and o.nation_id < 0 and o.cell >= 0 and world.region_of[o.cell] == rid \
				and o.bond(h.id) + h.charm * 0.05 > 0.2 and not companions(world, o).size() > 0:
			return o
	return null


## Вложить очко развития: "strength", "wit" или "charm".
static func spend_perk(world: World, stat: String) -> bool:
	var h := hero_of(world)
	if h == null or h.perk_points <= 0 or not PERKS.has(stat):
		return false
	h.perk_points -= 1
	h.set(stat, int(h.get(stat)) + 1)
	note(world, "Развитие: %s." % String(PERKS[stat]).to_lower())
	return true


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


# ---------------------------------------------------------------------------
# События и встречи
# ---------------------------------------------------------------------------

## Случайное событие пути из data/hero_events (по месту).
static func start_event(world: World, h: Hero) -> bool:
	var owner := world.owner[h.cell]
	var pool: Array[HeroEventDef] = []
	var total := 0.0
	for res in LoreDB.hero_events():
		var e := res as HeroEventDef
		if (e.where == &"nation" and owner < 0) or (e.where == &"wild" and owner >= 0) or not _terrain_ok(world, h, e.terrain):
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
	return true


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
						h.cell = nb.cells[world.rng.randi_range(0, nb.cells.size() - 1)]
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
