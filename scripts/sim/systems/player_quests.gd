class_name PlayerQuests
extends RefCounted
## Задания, рынок и храм для героя игрока (PlayerSystem). В городе края
## висит доска заданий (виды — data/quests, QuestDef): чудовище, руины,
## послание, разбойники, пропажа, а с этапа 11.H — логово, набег племени,
## охрана каравана, торговый заказ, разведка, поветрие, посольство (и клад по
## слухам — правда или вымысел); за золото, опыт и расположение державы; у
## задания есть срок. На рынке — кузнец, лекарь, охрана, пожертвование храму и
## товары (купить дёшево, продать дорого).
## Задание — словарь: {kind, title, region, target, giver, gold, xp, deadline}
## и дополнительно (по виду) good, amount, nation, truth, arrived.

const MAX_ACTIVE := 3
const OFFERS := 3
## Задания на расстоянии от 1 до MAX_STEPS краёв.
const MAX_STEPS := 5
## Опасность разбойников (доля силы героя 5-го уровня его класса) и рана при неудаче.
const BANDIT_THREAT := 0.7
const BANDIT_WOUND := 0.35
## Рынок: снаряжение (цена за уровень), лечение (за всю рану), охрана (бойцов, лет, цена), дар храму.
const GEAR_MAX := 3
const GEAR_PRICE := [60.0, 150.0, 320.0]
const HEAL_PRICE := 40.0
const GUARDS := 2
const GUARD_YEARS := 3
const GUARD_PRICE := 45.0
const DONATION := 30.0
## Скидка за каждое очко обаяния.
const CHARM_DISCOUNT := 0.06
## Товары: сколько унести (без охраны и с каждым охранником), сколько брать за раз.
const CARGO_BASE := 20.0
const CARGO_PER_GUARD := 10.0
const TRADE_LOT := 5.0
## Чужой язык края: всё дороже и заданий меньше.
const FOREIGN_PRICE := 1.2
## Набег: опасность (доля силы племени); разведка: шанс попасться (× (1 − ум)).
const RAID_THREAT := 0.12
const INTEL_CAPTURE := 0.3


## Название вида задания (для панели).
static func kind_name(kind: String) -> String:
	var def := QuestDB.find(StringName(kind))
	return def.display_name if def != null else kind


static func handler_of(q: Dictionary) -> StringName:
	var def := QuestDB.find(StringName(q.kind))
	return def.handler if def != null else StringName(q.kind)


static func city_here(world: World, h: Hero) -> City:
	if h == null or h.cell < 0:
		return null
	var rid := world.region_of[h.cell]
	for c in world.cities:
		if c.alive and world.region_of[c.cell] == rid:
			return c
	return null


static func price(h: Hero, base: float, world: World = null) -> float:
	var k := maxf(0.5, 1.0 - h.charm * CHARM_DISCOUNT)
	if world != null and not PlayerWorld.speaks_here(world, h):
		k *= FOREIGN_PRICE
	return roundf(base * k)


## Восстановление из сохранения (числа из JSON — в целые).
static func restore(d: Dictionary) -> Dictionary:
	var q := {"kind": str(d.kind), "title": str(d.title), "region": int(d.region), "target": int(d.target), "giver": int(d.giver),
		"gold": float(d.gold), "xp": float(d.xp), "deadline": int(d.deadline)}
	for k in ["good", "nation"]:
		if d.has(k):
			q[k] = int(d[k])
	if d.has("amount"):
		q.amount = float(d.amount)
	for k in ["truth", "arrived"]:
		if d.has(k):
			q[k] = bool(d[k])
	if d.has("tname"):
		q.tname = str(d.tname)
	return q


# ---------------------------------------------------------------------------
# Доска заданий
# ---------------------------------------------------------------------------


## Края в пределах MAX_STEPS шагов: регион → расстояние.
static func _near_regions(world: World, from: int) -> Dictionary:
	var dist := {from: 0}
	var queue: Array[int] = [from]
	var qi := 0
	while qi < queue.size():
		var r := queue[qi]
		qi += 1
		if dist[r] >= MAX_STEPS:
			continue
		for nb in world.regions[r].neighbors:
			if not dist.has(nb) and not world.regions[nb].cells.is_empty():
				dist[nb] = dist[r] + 1
				queue.append(nb)
	return dist


static func make_offers(world: World, h: Hero) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	var city := city_here(world, h)
	if city == null:
		return res
	var rng := world.rng
	var near := _near_regions(world, world.region_of[h.cell])
	var defs: Array[QuestDef] = []
	var total := 0.0
	for d in QuestDB.all():
		var def: QuestDef = d
		if def.board and def.weight > 0.0:
			defs.append(def)
			total += def.weight
	# В краю чужого языка — меньше заданий (вас плохо понимают).
	var offers := OFFERS - (1 if not PlayerWorld.speaks_here(world, h) else 0)
	var tries := 0
	while res.size() < offers and tries < 24 and total > 0.0:
		tries += 1
		var roll := rng.randf() * total
		var def: QuestDef = defs[defs.size() - 1]
		for x in defs:
			roll -= x.weight
			if roll <= 0.0:
				def = x
				break
		var q := make_quest(world, def, h, city, near)
		if not q.is_empty() and not res.any(func(o: Dictionary) -> bool: return o.title == q.title) \
				and not world.player_quests.any(func(o: Dictionary) -> bool: return o.title == q.title):
			res.append(q)
	return res


## Задание вида def от державы города city (near — края в пределах MAX_STEPS). Пусто — не вышло.
static func make_quest(world: World, def: QuestDef, h: Hero, city: City, near: Dictionary) -> Dictionary:
	var rng := world.rng
	var giver := city.nation_id
	var far: Array = near.keys().filter(func(r: int) -> bool: return near[r] >= 1)
	if far.is_empty():
		return {}
	match def.handler:
		&"hunt", &"bandits":
			var r: int = far[rng.randi_range(0, far.size() - 1)]
			return _quest(world, def, {"region": _rname(world, r)}, r, -1, giver, near[r])
		&"deliver":
			for c in world.cities:
				var r := world.region_of[c.cell]
				if c.alive and c != city and near.has(r) and near[r] >= 1 and (c.nation_id == giver or rng.randf() < 0.3):
					return _quest(world, def, {"target": c.name}, r, c.id, giver, near[r])
		&"ruins":
			for ru in world.ruins:
				if ru.cell >= 0 and not ru.depleted() and near.has(world.region_of[ru.cell]):
					return _quest(world, def, {"target": ru.name}, world.region_of[ru.cell], ru.id, giver, near[world.region_of[ru.cell]] + 1)
		&"artifact":
			for a in world.artifacts:
				if a.is_lost() and a.cell >= 0 and world.region_of[a.cell] >= 0:
					var r := world.region_of[a.cell]
					return _quest(world, def, {"target": a.name}, r, a.id, giver, near.get(r, MAX_STEPS + 2) + 2)
		&"lair":
			for l in world.lairs:
				if l.alive and (near.has(l.region) or near.has(l.home)):
					var r := l.region if near.has(l.region) else l.home
					return _quest(world, def, {"target": l.label() if l.def.great else l.def.display_name.to_lower()}, r, l.id, giver, near[r] + (2 if l.def.great else 0))
		&"raid":
			for t in world.tribes:
				if t.alive and near.has(t.region) and (t.horde or t.raids > 0):
					var q := _quest(world, def, {"target": t.label()}, t.region, t.id, giver, near[t.region] + 1)
					q.tname = t.name
					return q
		&"caravan":
			for rid in world.city_roads.get(city.id, PackedInt32Array()):
				var road := world.roads[rid]
				var to := world.cities[road.other(city.id)]
				if road.alive and to.alive and to.nation_id >= 0 and near.has(world.region_of[to.cell]):
					return _quest(world, def, {"target": to.name}, world.region_of[to.cell], to.id, giver, near.get(world.region_of[to.cell], 1))
		&"trade":
			for c in world.cities:
				var r := world.region_of[c.cell]
				if not c.alive or c == city or not near.has(r) or near[r] < 1 or c.nation_id < 0:
					continue
				var n := world.nations[c.nation_id]
				if n.market_price.size() != MarketDB.size():
					continue
				for i in MarketDB.size():
					if n.market_demand[i] > n.market_used[i] + 2.0:
						var amount := float(rng.randi_range(1, 3)) * TRADE_LOT
						var g: GoodDef = MarketDB.all()[i]
						var q := _quest(world, def, {"amount": int(amount), "good": g.display_name.to_lower(), "target": c.name}, r, c.id, giver, near[r])
						q.good = i
						q.amount = amount
						q.gold = roundf(float(q.gold) + amount * n.market_price[i] * 0.3)
						return q
		&"intel", &"embassy":
			var d := world.diplomacy
			for n in world.nations:
				if not n.alive or n.id == giver or n.capital_city < 0:
					continue
				var r := world.region_of[world.cities[n.capital_city].cell]
				if not near.has(r) or near[r] < 1:
					continue
				var war := giver >= 0 and d.war_between(giver, n.id) != null
				if (def.handler == &"intel" and (war or (giver >= 0 and d.opinion(world, giver, n.id) < 0.0))) or (def.handler == &"embassy" and not war):
					var q := _quest(world, def, {"nation": n.short_name}, r, n.capital_city, giver, near[r])
					q.nation = n.id
					return q
		&"epidemic":
			for o in world.outbreaks:
				if not o.alive:
					continue
				for r in o.regions:
					if near.has(r):
						return _quest(world, def, {"region": _rname(world, r)}, r, -1, giver, near[r])
	return {}


## Задание из события пути: руины, пропажа, логово, клад по слухам, посольство.
static func rumor_quest(world: World, h: Hero, kind: String) -> Dictionary:
	var near := _near_regions(world, world.region_of[h.cell])
	if kind == "ruins":
		for ru in world.ruins:
			if ru.cell >= 0 and not ru.depleted() and near.has(world.region_of[ru.cell]):
				return _quest(world, QuestDB.find(&"ruins"), {"target": ru.name}, world.region_of[ru.cell], ru.id, -1, near[world.region_of[ru.cell]] + 1)
	if kind == "treasure":
		var far: Array = near.keys().filter(func(r: int) -> bool: return near[r] >= 1)
		if far.is_empty():
			return {}
		var r: int = far[world.rng.randi_range(0, far.size() - 1)]
		var q := _quest(world, QuestDB.find(&"treasure"), {"region": _rname(world, r)}, r, -1, -1, near[r])
		q.truth = world.rng.randf() < 0.6
		return q
	if kind in ["lair", "embassy", "raid", "epidemic"]:
		var city := city_here(world, h)
		var fake := city if city != null else null
		if fake != null:
			return make_quest(world, QuestDB.find(StringName(kind)), h, fake, near)
		return {}
	for a in world.artifacts:
		if a.is_lost() and a.cell >= 0 and world.region_of[a.cell] >= 0:
			return _quest(world, QuestDB.find(&"artifact"), {"target": a.name}, world.region_of[a.cell], a.id, -1, near.get(world.region_of[a.cell], MAX_STEPS + 2) + 2)
	return {}


static func _rname(world: World, r: int) -> String:
	world.ensure_region_name(world.regions[r])
	return world.regions[r].name


static func _quest(world: World, def: QuestDef, fill: Dictionary, region: int, target: int, giver: int, steps: int) -> Dictionary:
	var title := def.title
	for k in fill:
		title = title.replace("{%s}" % k, str(fill[k]))
	return {"kind": String(def.id), "title": title, "region": region, "target": target, "giver": giver,
		"gold": roundf((def.gold_base + steps * def.gold_per_step) * def.danger), "xp": def.xp_base + steps * def.xp_per_step * def.danger,
		"deadline": world.year + def.years + steps / 2}


static func open_board(world: World, h: Hero) -> bool:
	world.player_offers = make_offers(world, h)
	var city := city_here(world, h)
	var options: Array = []
	for i in world.player_offers.size():
		var q := world.player_offers[i]
		options.append({"text": "%s — %d зол., до %d г." % [q.title, int(q.gold), int(q.deadline)], "act": "take_quest", "index": i})
	options.append({"text": "Уйти", "act": "leave"})
	var text := "На доске заданий в городе %s %s." % [city.name if city != null else "?",
		"висят просьбы жителей" if not world.player_offers.is_empty() else "пусто"]
	if world.player_quests.size() >= MAX_ACTIVE:
		text += " Но у вас уже %d задания — больше не унести." % MAX_ACTIVE
		options = [options[options.size() - 1]]
	world.player_choice = {"kind": "board", "title": "Доска заданий", "text": text, "options": options}
	return true


static func accept(world: World, h: Hero, index: int) -> String:
	if index < 0 or index >= world.player_offers.size() or world.player_quests.size() >= MAX_ACTIVE:
		return ""
	var q := world.player_offers[index]
	world.player_offers.clear()
	var extra := ""
	if handler_of(q) == &"caravan":
		# Купцы снаряжают караван — герой его охраняет.
		var c := PlayerWorld.escort_caravan(world, h, q)
		if c == null:
			return "Купцам нечего везти — задание отменено."
		extra = " Караван с товаром «%s» выходит в путь." % (MarketDB.all()[c.good] as GoodDef).display_name.to_lower()
	world.player_quests.append(q)
	return "Задание принято: %s. Награда — %d золотых, срок — до %d года.%s" % [q.title, int(q.gold), int(q.deadline), extra]


## Клетка цели задания (для карты и «К цели»).
static func target_cell(world: World, q: Dictionary) -> int:
	match handler_of(q):
		&"deliver", &"caravan", &"trade", &"intel", &"embassy":
			var t := int(q.target)
			return world.cities[t].cell if t >= 0 and t < world.cities.size() else -1
		&"ruins":
			return world.ruins[int(q.target)].cell
		&"artifact":
			var a := world.artifacts[int(q.target)]
			return a.cell if a.is_lost() else -1
		&"lair":
			var l := _lair(world, q)
			if l != null:
				return l.cell if l.region == l.home else world.regions[l.region].center
		&"raid":
			var t := _tribe(world, q)
			if t != null:
				return t.cell
	var cells := world.regions[int(q.region)].cells
	return cells[cells.size() / 2] if not cells.is_empty() else -1


## Логово и племя задания (по id; списки уплотняются раз в год — ищем по краю, если id сменился).
static func _lair(world: World, q: Dictionary) -> Lair:
	var id := int(q.target)
	if id >= 0 and id < world.lairs.size() and world.lairs[id].alive and (world.lairs[id].region == int(q.region) or world.lairs[id].home == int(q.region)):
		return world.lairs[id]
	for l in world.lairs:
		if l.alive and (l.region == int(q.region) or l.home == int(q.region)):
			q.target = l.id
			return l
	return null


static func _tribe(world: World, q: Dictionary) -> Tribe:
	for t in world.tribes:
		if t.alive and t.name == str(q.get("tname", "")):
			q.region = t.region
			return t
	return null


## Проверка заданий: trigger — &"arrive", &"hunt", &"explore", &"month".
static func check(world: World, h: Hero, trigger: StringName) -> void:
	if world.player_quests.is_empty() or h == null or not h.alive or h.cell < 0:
		return
	var rng := world.rng
	var rid := world.region_of[h.cell]
	var at := trigger == &"arrive" or trigger == &"month"
	for q in world.player_quests.duplicate():
		if not h.alive:
			return
		var here := int(q.region) == rid
		match handler_of(q):
			&"hunt":
				if here and trigger == &"hunt":
					_complete(world, h, q)
			&"deliver":
				if here and at:
					_complete(world, h, q)
			&"ruins":
				if here and trigger == &"explore":
					_complete(world, h, q)
			&"bandits":
				if here and (trigger == &"arrive" or trigger == &"hunt"):
					var threat := BANDIT_THREAT * h.hero_class.power * 5.0
					if PlayerSystem.fight_power(world, h) * rng.randf_range(0.6, 1.4) > threat * rng.randf_range(0.6, 1.2):
						_complete(world, h, q)
					else:
						PlayerSystem.note(world, "Разбойники в краю %s дали отпор." % _rname(world, rid))
						PlayerSystem.wound(world, h, BANDIT_WOUND, "пал от рук разбойников")
			&"artifact":
				var a := world.artifacts[int(q.target)]
				if a.hero == h.id:
					_complete(world, h, q)
				elif not a.is_lost():
					_fail(world, q, "предмет нашёл кто-то другой")
					continue
			&"lair":
				var l := _lair(world, q)
				if l == null:
					_fail(world, q, "логово разорил кто-то другой")
					continue
				if (l.region == rid or l.home == rid) and (trigger == &"arrive" or trigger == &"hunt"):
					if LairSystem.hero_fight(world, h, l):
						_complete(world, h, q)
					elif h.alive:
						PlayerSystem.note(world, "%s оказалось сильнее — вы отступили (раны %d%%)." % [l.label(), roundi(h.wounds * 100.0)])
			&"raid":
				var t := _tribe(world, q)
				if t == null:
					_fail(world, q, "налётчиков больше нет")
					continue
				if t.region == rid and (trigger == &"arrive" or trigger == &"hunt"):
					if PlayerSystem.fight_power(world, h) * rng.randf_range(0.6, 1.4) > t.strength * RAID_THREAT * rng.randf_range(0.6, 1.2):
						t.strength *= 0.6
						t.raids = 0
						_complete(world, h, q)
					else:
						PlayerSystem.note(world, "%s отбились — нужно больше сил." % t.label())
						PlayerSystem.wound(world, h, BANDIT_WOUND, "пал в стычке с налётчиками")
			&"caravan":
				if here and at and bool(q.get("arrived", false)):
					_complete(world, h, q)
			&"trade":
				var gi := int(q.good)
				if here and at and float(h.cargo.get(gi, 0.0)) >= float(q.amount) - 0.01:
					PlayerWorld.unload(world, h, gi, float(q.amount), int(q.target))
					_complete(world, h, q)
			&"intel":
				if here and at:
					if rng.randf() < INTEL_CAPTURE * (1.0 - h.wits()):
						_fail(world, q, "вас схватила стража")
						PlayerWorld.capture(world, h, int(q.nation), "схвачен как лазутчик")
						continue
					if int(q.giver) >= 0:
						var g := world.nations[int(q.giver)]
						g.intel = minf(SpySystem.MAX_INTEL, g.intel + 15.0)
					_complete(world, h, q)
			&"epidemic":
				if here and at:
					var o := DiseaseSystem.outbreak_in(world, rid)
					if o == null:
						_fail(world, q, "поветрие ушло само")
						continue
					o.regions[rid] = 1
					world.regions[rid].immune[o.def.id] = world.year + o.def.immunity_years
					PlayerWorld.risk_disease(world, h, o, 0.5)
					if h.alive:
						h.karma = minf(1.0, h.karma + 0.08)
						_complete(world, h, q)
			&"embassy":
				var target := int(q.nation)
				if int(q.giver) >= 0 and world.diplomacy.war_between(int(q.giver), target) != null:
					_fail(world, q, "между державами началась война")
					continue
				if here and at:
					if int(q.giver) >= 0:
						world.diplomacy.add_grudge(int(q.giver), target, -0.15)
						world.diplomacy.add_grudge(target, int(q.giver), -0.15)
						var offer := {"kind": &"pact", "from": int(q.giver), "to": target}
						if not world.diplomacy.has_truce(int(q.giver), target, world.year) and world.nations[target].alive:
							DealSystem.propose(world, offer)
					_complete(world, h, q)
			&"treasure":
				if here and (trigger == &"arrive" or trigger == &"explore"):
					if bool(q.get("truth", false)):
						q.gold = roundf(rng.randf_range(60.0, 200.0))
						_complete(world, h, q)
					else:
						world.player_quests.erase(q)
						PlayerSystem.note(world, "Клада в краю %s нет — слух оказался вымыслом." % _rname(world, rid))
						continue
		if trigger == &"month" and world.player_quests.has(q) and world.year > int(q.deadline):
			_fail(world, q, "срок вышел")


static func _complete(world: World, h: Hero, q: Dictionary) -> void:
	world.player_quests.erase(q)
	h.gold += float(q.gold)
	h.add_xp(world, float(q.xp))
	if int(q.giver) >= 0:
		PlayerSystem.rep(world, "n%d" % int(q.giver), 0.08 + h.charm * 0.01)
	h.add_deed(world, "выполнил задание: %s" % String(q.title).to_lower())
	world.count(&"player_quests")
	PlayerSystem.note(world, "Задание выполнено: %s. Награда — %d золотых." % [q.title, int(q.gold)])


static func _fail(world: World, q: Dictionary, why: String) -> void:
	world.player_quests.erase(q)
	if int(q.giver) >= 0:
		PlayerSystem.rep(world, "n%d" % int(q.giver), -0.06)
	PlayerSystem.note(world, "Задание провалено (%s): %s." % [why, q.title])


# ---------------------------------------------------------------------------
# Рынок и храм
# ---------------------------------------------------------------------------


static func open_shop(world: World, h: Hero) -> void:
	var city := city_here(world, h)
	var options: Array = []
	if h.gear < GEAR_MAX:
		var p := price(h, GEAR_PRICE[h.gear], world)
		options.append({"text": "Кузнец: снаряжение %d-го уровня (+10%% к силе) — %d зол." % [h.gear + 1, int(p)], "act": "buy", "item": "gear", "cost": p})
	if h.wounds > 0.05:
		var p := price(h, ceilf(HEAL_PRICE * h.wounds), world)
		options.append({"text": "Лекарь: залечить раны — %d зол." % int(p), "act": "buy", "item": "heal", "cost": p})
	var g := price(h, GUARD_PRICE, world)
	options.append({"text": "Нанять охрану: %d бойца на %d года — %d зол." % [GUARDS, GUARD_YEARS, int(g)], "act": "buy", "item": "guards", "cost": g})
	options.append({"text": "Пожертвовать храму — %d зол." % int(DONATION), "act": "buy", "item": "donate", "cost": DONATION})
	options = options.slice(0, 3)
	options.append_array(PlayerWorld.goods_options(world, h).slice(0, 3))
	options.append({"text": "Уйти", "act": "leave"})
	world.player_choice = {"kind": "shop", "title": "Рынок города %s" % (city.name if city != null else "?"),
		"text": "В кошеле %d золотых. Раны: %d%%. Снаряжение: %d из %d. Охрана: %d. Груз: %d из %d.%s" % [int(h.gold), roundi(h.wounds * 100.0), h.gear,
			GEAR_MAX, h.guards, int(PlayerWorld.cargo_total(h)), int(PlayerWorld.cargo_cap(h)),
			"" if PlayerWorld.speaks_here(world, h) else " Здесь говорят на чужом языке — всё дороже."],
		"options": options}


static func buy(world: World, h: Hero, item: String, cost: float) -> String:
	if h.gold < cost:
		return "Не хватает золота (нужно %d, есть %d)." % [int(cost), int(h.gold)]
	h.gold -= cost
	match item:
		"gear":
			h.gear += 1
			return "Кузнец выковал снаряжение %d-го уровня." % h.gear
		"heal":
			h.wounds = 0.0
			return "Лекарь залечил ваши раны."
		"guards":
			h.guards = GUARDS
			h.guards_until = world.year + GUARD_YEARS
			return "%d наёмных бойца будут охранять вас до %d года." % [GUARDS, h.guards_until]
		"donate":
			h.karma = minf(1.0, h.karma + 0.05)
			var rid := world.region_of[h.cell]
			if rid >= 0 and world.regions[rid].main_faith() >= 0:
				PlayerSystem.rep(world, "r%d" % world.regions[rid].main_faith(), 0.08)
			return "Жрецы благословили вас."
	return ""
