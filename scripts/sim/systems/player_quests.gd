class_name PlayerQuests
extends RefCounted
## Задания, рынок и храм для героя игрока (PlayerSystem). В городе края
## висит доска заданий: держава просит сразить чудовище, исследовать руины,
## доставить послание, разогнать разбойников или найти потерянный предмет —
## за золото, опыт и её расположение; у задания есть срок. На рынке — кузнец
## (снаряжение), лекарь, наёмная охрана и пожертвование храму.
## Задание — словарь: {kind, title, region, target, giver, gold, xp, deadline}.

const MAX_ACTIVE := 3
const OFFERS := 3
## Задания на расстоянии от 1 до MAX_STEPS краёв.
const MAX_STEPS := 5
const KIND_NAMES := {"hunt": "Охота", "ruins": "Руины", "deliver": "Послание", "bandits": "Разбойники", "artifact": "Пропажа"}
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


static func city_here(world: World, h: Hero) -> City:
	if h == null or h.cell < 0:
		return null
	var rid := world.region_of[h.cell]
	for c in world.cities:
		if c.alive and world.region_of[c.cell] == rid:
			return c
	return null


static func price(h: Hero, base: float) -> float:
	return roundf(base * maxf(0.5, 1.0 - h.charm * CHARM_DISCOUNT))


## Восстановление из сохранения (числа из JSON — в целые).
static func restore(d: Dictionary) -> Dictionary:
	return {"kind": str(d.kind), "title": str(d.title), "region": int(d.region), "target": int(d.target), "giver": int(d.giver),
		"gold": float(d.gold), "xp": float(d.xp), "deadline": int(d.deadline)}


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
	var giver := city.nation_id
	var from := world.region_of[h.cell]
	var near := _near_regions(world, from)
	var far: Array = near.keys().filter(func(r: int) -> bool: return near[r] >= 1)
	if far.is_empty():
		return res
	var kinds := ["hunt", "ruins", "deliver", "bandits", "artifact"]
	var tries := 0
	while res.size() < OFFERS and tries < 20:
		tries += 1
		var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		var q := {}
		match kind:
			"hunt":
				var r: int = far[rng.randi_range(0, far.size() - 1)]
				q = _quest(world, kind, "Сразить чудовище в краю %s" % _rname(world, r), r, -1, giver, near[r])
			"bandits":
				var r: int = far[rng.randi_range(0, far.size() - 1)]
				q = _quest(world, kind, "Разогнать разбойников в краю %s" % _rname(world, r), r, -1, giver, near[r])
			"deliver":
				for c in world.cities:
					var r := world.region_of[c.cell]
					if c.alive and c != city and near.has(r) and near[r] >= 1 and (c.nation_id == giver or rng.randf() < 0.3):
						q = _quest(world, kind, "Доставить послание в город %s" % c.name, r, c.id, giver, near[r])
						break
			"ruins":
				for ru in world.ruins:
					if ru.cell >= 0 and not ru.depleted() and near.has(world.region_of[ru.cell]):
						q = _quest(world, kind, "Исследовать «%s»" % ru.name, world.region_of[ru.cell], ru.id, giver, near[world.region_of[ru.cell]] + 1)
						break
			"artifact":
				for a in world.artifacts:
					if a.is_lost() and a.cell >= 0 and world.region_of[a.cell] >= 0:
						var r := world.region_of[a.cell]
						q = _quest(world, kind, "Найти пропажу — %s" % a.name, r, a.id, giver, near.get(r, MAX_STEPS + 2) + 2)
						break
		if not q.is_empty() and not res.any(func(o: Dictionary) -> bool: return o.title == q.title) \
				and not world.player_quests.any(func(o: Dictionary) -> bool: return o.title == q.title):
			res.append(q)
	return res


## Задание из слухов (событие пути): ближайшие руины или потерянный предмет.
static func rumor_quest(world: World, h: Hero, kind: String) -> Dictionary:
	var near := _near_regions(world, world.region_of[h.cell])
	if kind == "ruins":
		for ru in world.ruins:
			if ru.cell >= 0 and not ru.depleted() and near.has(world.region_of[ru.cell]):
				return _quest(world, kind, "Исследовать «%s»" % ru.name, world.region_of[ru.cell], ru.id, -1, near[world.region_of[ru.cell]] + 1)
	for a in world.artifacts:
		if a.is_lost() and a.cell >= 0 and world.region_of[a.cell] >= 0:
			return _quest(world, "artifact", "Найти пропажу — %s" % a.name, world.region_of[a.cell], a.id, -1, near.get(world.region_of[a.cell], MAX_STEPS + 2) + 2)
	return {}


static func _rname(world: World, r: int) -> String:
	world.ensure_region_name(world.regions[r])
	return world.regions[r].name


static func _quest(world: World, kind: String, title: String, region: int, target: int, giver: int, steps: int) -> Dictionary:
	var danger := 1.5 if kind == "bandits" or kind == "hunt" else 1.0
	return {"kind": kind, "title": title, "region": region, "target": target, "giver": giver,
		"gold": roundf((20.0 + steps * 15.0) * danger), "xp": 1.5 + steps * 0.6 * danger, "deadline": world.year + 2 + steps / 2}


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
	world.player_quests.append(q)
	world.player_offers.clear()
	return "Задание принято: %s. Награда — %d золотых, срок — до %d года." % [q.title, int(q.gold), int(q.deadline)]


## Клетка цели задания (для карты и «К цели»).
static func target_cell(world: World, q: Dictionary) -> int:
	match String(q.kind):
		"deliver":
			return world.cities[int(q.target)].cell
		"ruins":
			return world.ruins[int(q.target)].cell
		"artifact":
			var a := world.artifacts[int(q.target)]
			return a.cell if a.is_lost() else -1
	var cells := world.regions[int(q.region)].cells
	return cells[cells.size() / 2] if not cells.is_empty() else -1


## Проверка заданий: trigger — &"arrive", &"hunt", &"explore", &"month".
static func check(world: World, h: Hero, trigger: StringName) -> void:
	if world.player_quests.is_empty() or h == null or not h.alive or h.cell < 0:
		return
	var rid := world.region_of[h.cell]
	for q in world.player_quests.duplicate():
		if not h.alive:
			return
		var here := int(q.region) == rid
		match String(q.kind):
			"hunt":
				if here and trigger == &"hunt":
					_complete(world, h, q)
			"deliver":
				if here and (trigger == &"arrive" or trigger == &"month"):
					_complete(world, h, q)
			"ruins":
				if here and trigger == &"explore":
					_complete(world, h, q)
			"bandits":
				if here and (trigger == &"arrive" or trigger == &"hunt"):
					var threat := BANDIT_THREAT * h.hero_class.power * 5.0
					if PlayerSystem.fight_power(world, h) * world.rng.randf_range(0.6, 1.4) > threat * world.rng.randf_range(0.6, 1.2):
						_complete(world, h, q)
					else:
						PlayerSystem.note(world, "Разбойники в краю %s дали отпор." % _rname(world, rid))
						PlayerSystem.wound(world, h, BANDIT_WOUND, "пал от рук разбойников")
			"artifact":
				var a := world.artifacts[int(q.target)]
				if a.hero == h.id:
					_complete(world, h, q)
				elif not a.is_lost():
					_fail(world, q, "предмет нашёл кто-то другой")
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
		var p := price(h, GEAR_PRICE[h.gear])
		options.append({"text": "Кузнец: снаряжение %d-го уровня (+10%% к силе) — %d зол." % [h.gear + 1, int(p)], "act": "buy", "item": "gear", "cost": p})
	if h.wounds > 0.05:
		var p := price(h, ceilf(HEAL_PRICE * h.wounds))
		options.append({"text": "Лекарь: залечить раны — %d зол." % int(p), "act": "buy", "item": "heal", "cost": p})
	var g := price(h, GUARD_PRICE)
	options.append({"text": "Нанять охрану: %d бойца на %d года — %d зол." % [GUARDS, GUARD_YEARS, int(g)], "act": "buy", "item": "guards", "cost": g})
	options.append({"text": "Пожертвовать храму — %d зол." % int(DONATION), "act": "buy", "item": "donate", "cost": DONATION})
	options = options.slice(0, 3)
	options.append({"text": "Уйти", "act": "leave"})
	world.player_choice = {"kind": "shop", "title": "Рынок города %s" % (city.name if city != null else "?"),
		"text": "В кошеле %d золотых. Раны: %d%%. Снаряжение: %d из %d. Охрана: %d." % [int(h.gold), roundi(h.wounds * 100.0), h.gear, GEAR_MAX, h.guards],
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
