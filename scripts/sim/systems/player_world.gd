class_name PlayerWorld
## Герой игрока в живом мире (этап 11.H): товары рынка (купить дёшево,
## продать дорого, торговые заказы), охрана караванов, служба в войске (офицер
## или полководец; битвы, жалованье, плен), плен (выкуп, побег), болезни
## краёв, язык края (чужая речь — дороже и меньше заданий), цепочки событий
## (продолжение через несколько месяцев). Чистые функции над World — вызывает
## PlayerSystem, ArmySystem, CaravanSystem.

## Жалованье в войске (в месяц) и опыт за битву.
const OFFICER_PAY := 3.0
const GENERAL_PAY := 6.0
const BATTLE_XP := 2.5
## Поражение войска: шанс плена и рана.
const CAPTURE_CHANCE := 0.3
const BATTLE_WOUND := Vector2(0.1, 0.4)
## Выкуп из плена (за уровень) и шанс побега (× ум).
const RANSOM_PER_LEVEL := 40.0
const ESCAPE_CHANCE := 0.25
## Болезнь края: шанс заболеть в месяц и тяжесть.
const SICK_CHANCE := 0.12
const SICK_WOUND := Vector2(0.15, 0.35)
## Охраняемый караван грабят во столько раз реже.
const ESCORT_SAFETY := 0.15


static func hero_of(world: World) -> Hero:
	return world.heroes[world.player] if world.player >= 0 and world.player < world.heroes.size() else null


# ---------------------------------------------------------------------------
# Язык края
# ---------------------------------------------------------------------------


## Праязык народа героя (без создания нового).
static func native_language(world: World, h: Hero) -> int:
	for l in world.languages:
		if l.parent < 0 and l.race == h.race:
			return l.id
	return -1


## Понимают ли героя в этом краю (язык края — из семьи его праязыка).
static func speaks_here(world: World, h: Hero) -> bool:
	if h == null or h.cell < 0:
		return true
	var rid := world.region_of[h.cell]
	if rid < 0 or world.regions[rid].language < 0:
		return true
	var own := native_language(world, h)
	return own < 0 or LanguageSystem.root(world, world.regions[rid].language) == own


# ---------------------------------------------------------------------------
# Товары
# ---------------------------------------------------------------------------


static func cargo_total(h: Hero) -> float:
	var sum := 0.0
	for k in h.cargo:
		sum += float(h.cargo[k])
	return sum


static func cargo_cap(h: Hero) -> float:
	return PlayerQuests.CARGO_BASE + h.guards * PlayerQuests.CARGO_PER_GUARD


static func _market_here(world: World, h: Hero) -> Nation:
	var city := PlayerQuests.city_here(world, h)
	if city == null or city.nation_id < 0:
		return null
	var n := world.nations[city.nation_id]
	MarketSystem.ensure(world, n)
	return n


## Варианты торговли на рынке города: купить самые дешёвые товары, продать груз.
static func goods_options(world: World, h: Hero) -> Array:
	var n := _market_here(world, h)
	var res: Array = []
	if n == null:
		return res
	var goods := MarketDB.all()
	var lot := PlayerQuests.TRADE_LOT
	for i in goods.size():
		var have := float(h.cargo.get(i, 0.0))
		if have >= 1.0:
			var gain := roundf(minf(have, lot * 2.0) * n.market_price[i] * 0.9)
			res.append({"text": "Продать %d ед. «%s» — %d зол." % [int(minf(have, lot * 2.0)), goods[i].display_name, int(gain)],
				"act": "sell_good", "good": i, "amount": minf(have, lot * 2.0), "cost": gain})
	# Купить: товары, что здесь дешевле обычного (по базе) и есть в запасе.
	var cheap: Array = []
	for i in goods.size():
		var g: GoodDef = goods[i]
		if n.market_stock[i] >= lot and cargo_total(h) + lot <= cargo_cap(h):
			cheap.append([n.market_price[i] / g.base_price, i])
	cheap.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for c in cheap.slice(0, 2):
		var i: int = c[1]
		var cost := PlayerQuests.price(h, ceilf(lot * n.market_price[i]), world)
		res.append({"text": "Купить %d ед. «%s» — %d зол." % [int(lot), goods[i].display_name, int(cost)], "act": "buy_good", "good": i,
			"amount": lot, "cost": cost})
	return res


static func buy_good(world: World, h: Hero, gi: int, amount: float, cost: float) -> String:
	var n := _market_here(world, h)
	if n == null:
		return "Здесь нет рынка."
	if h.gold < cost:
		return "Не хватает золота (нужно %d)." % int(cost)
	if n.market_stock[gi] < amount or cargo_total(h) + amount > cargo_cap(h) + 0.01:
		return "Столько не купить и не унести."
	h.gold -= cost
	n.stock[Goods.GOLD] += cost * MarketSystem.EXPORT_DUTY
	n.market_stock[gi] -= amount
	n.market_out[gi] += amount
	h.cargo[gi] = float(h.cargo.get(gi, 0.0)) + amount
	return "Куплено %d ед. товара «%s»." % [int(amount), (MarketDB.all()[gi] as GoodDef).display_name]


static func sell_good(world: World, h: Hero, gi: int, amount: float, gain: float) -> String:
	var city := PlayerQuests.city_here(world, h)
	if city == null or float(h.cargo.get(gi, 0.0)) < amount - 0.01:
		return "Нечего продать."
	unload(world, h, gi, amount, city.id)
	h.gold += gain
	h.add_xp(world, 0.2)
	return "Продано %d ед. товара «%s» за %d золотых." % [int(amount), (MarketDB.all()[gi] as GoodDef).display_name, int(gain)]


## Выгрузить товар на рынок города (продажа или торговый заказ).
static func unload(world: World, h: Hero, gi: int, amount: float, city_id: int) -> void:
	var left := float(h.cargo.get(gi, 0.0)) - amount
	if left <= 0.01:
		h.cargo.erase(gi)
	else:
		h.cargo[gi] = left
	var city := world.cities[city_id]
	if city.nation_id >= 0:
		var n := world.nations[city.nation_id]
		MarketSystem.ensure(world, n)
		n.market_stock[gi] += amount
		n.market_in[gi] += amount


## Товары в мешке героя игрока (для учёта рынка: «в пути»).
static func carried(world: World) -> float:
	var h := hero_of(world)
	return cargo_total(h) if h != null and h.alive else 0.0


# ---------------------------------------------------------------------------
# Охрана каравана
# ---------------------------------------------------------------------------


static func escort_caravan(world: World, h: Hero, q: Dictionary) -> Caravan:
	var city := PlayerQuests.city_here(world, h)
	if city == null or city.nation_id < 0:
		return null
	var nation := world.nations[city.nation_id]
	MarketSystem.ensure(world, nation)
	var road: Road = null
	for rid in world.city_roads.get(city.id, PackedInt32Array()):
		var r := world.roads[rid]
		if r.alive and r.other(city.id) == int(q.target):
			road = r
	if road == null:
		return null
	var best := -1
	for i in MarketDB.size():
		if nation.market_stock[i] >= 3.0 and (best < 0 or nation.market_stock[i] * nation.market_price[i] > nation.market_stock[best] * nation.market_price[best]):
			best = i
	if best < 0:
		return null
	var c := CaravanSystem.launch(world, road, city.id, int(q.target), best, minf(nation.market_stock[best] * 0.3, 25.0), nation.market_price[best])
	c.escort = h.id
	return c


## Караван под охраной героя дошёл или пропал (вызывает CaravanSystem).
static func on_caravan(world: World, c: Caravan, arrived: bool) -> void:
	for q in world.player_quests:
		if PlayerQuests.handler_of(q) == &"caravan" and int(q.target) == c.to_city and not bool(q.get("arrived", false)):
			if arrived:
				q.arrived = true
				PlayerSystem.note(world, "Караван благополучно прибыл в город %s — идите за наградой." % world.cities[c.to_city].name)
			else:
				world.player_quests.erase(q)
				PlayerSystem.note(world, "Караван, что вы охраняли, разграблен — задание провалено.")
				if int(q.giver) >= 0:
					PlayerSystem.rep(world, "n%d" % int(q.giver), -0.06)
			return


## Насколько охрана героя бережёт караван (множитель шанса грабежа).
static func escort_factor(world: World, c: Caravan) -> float:
	if c.escort < 0 or c.escort != world.player:
		return 1.0
	var h := hero_of(world)
	return ESCORT_SAFETY if h != null and h.alive and h.captive_by < 0 else 1.0


# ---------------------------------------------------------------------------
# Служба в войске
# ---------------------------------------------------------------------------


## Держава, за которую воюет герой (присяга или наём).
static func _side(h: Hero) -> int:
	return h.nation_id if h.nation_id >= 0 else h.ally_nation


## Войско державы героя в его краю или по соседству.
static func army_near(world: World, h: Hero) -> Army:
	var nid := _side(h)
	if nid < 0 or h.cell < 0:
		return null
	var rid := world.region_of[h.cell]
	for a in world.armies:
		if a.alive and a.kind == &"land" and a.nation == nid and a.war >= 0 \
				and (a.region == rid or world.regions[rid].neighbors.has(a.region)):
			return a
	return null


## Войско, где служит герой игрока (или null).
static func player_army(world: World) -> Army:
	var pa := world.player_army
	if pa.is_empty():
		return null
	for a in world.armies:
		if a.alive and a.kind == &"land" and a.war == int(pa.war) and a.nation == int(pa.nation):
			return a
	return null


static func join_army(world: World, h: Hero) -> String:
	var a := army_near(world, h)
	if a == null:
		return "рядом нет войска вашей державы"
	var nation := world.nations[a.nation]
	var role := "officer"
	var skill := minf(1.0, h.level * 0.08 + h.wits() * 0.2)
	var current := float(world.generals[a.general].skill) if a.general >= 0 else -1.0
	if skill > current:
		role = "general"
		if a.general >= 0:
			world.generals[a.general].army = -1
		var gid := ArmySystem.new_general(world, nation, h.display_name(), skill, h.id)
		world.generals[gid].army = a.id
		a.general = gid
	world.player_army = {"war": a.war, "nation": a.nation, "role": role, "since": world.year}
	h.cell = a.cell
	world.player_cmd = {}
	h.add_deed(world, "%s войско государства %s" % ["повёл" if role == "general" else "вступил в", nation.short_name])
	return ""


static func leave_army(world: World, h: Hero, why: String = "") -> void:
	var a := player_army(world)
	if a != null and a.general >= 0 and int(world.generals[a.general].hero) == h.id:
		world.generals[a.general].army = -1
		a.general = -1
	world.player_army = {}
	if not why.is_empty():
		PlayerSystem.note(world, why)


## Войско героя игрока билось (вызывает ArmySystem.battle).
static func on_battle(world: World, a: Army, won: bool) -> void:
	var h := hero_of(world)
	if h == null or not h.alive:
		return
	var rng := world.rng
	var where := world.region_label(a.cell, "поле боя")
	if won:
		h.add_xp(world, BATTLE_XP * (1.5 if world.player_army.get("role") == "general" else 1.0))
		h.gold += 10.0
		PlayerSystem.note(world, "Битва в краю %s — победа! Ваша доля добычи — 10 золотых." % where)
		return
	PlayerSystem.wound(world, h, rng.randf_range(BATTLE_WOUND.x, BATTLE_WOUND.y), "пал в битве в краю " + where)
	if not h.alive:
		return
	if rng.randf() < CAPTURE_CHANCE:
		var enemy := -1
		for w in world.diplomacy.wars:
			if w.id == a.war:
				enemy = w.leader(-w.side_of(a.nation))
		if enemy >= 0:
			capture(world, h, enemy, "взят в плен в битве в краю " + where)
			return
	PlayerSystem.note(world, "Битва в краю %s проиграна; вы отступили с войском (раны %d%%)." % [where, roundi(h.wounds * 100.0)])


# ---------------------------------------------------------------------------
# Плен
# ---------------------------------------------------------------------------


static func capture(world: World, h: Hero, nation_id: int, why: String) -> void:
	if nation_id < 0 or nation_id >= world.nations.size():
		return
	leave_army(world, h)
	h.captive_by = nation_id
	h.captive_until = world.year + world.rng.randi_range(1, 3)
	world.player_cmd = {}
	var n := world.nations[nation_id]
	if n.capital_city >= 0:
		h.cell = world.cities[n.capital_city].cell
	h.add_deed(world, why)
	world.count(&"player_captured")
	world.log_event(&"hero", "Герой %s %s (держава %s)." % [h.display_name(), why, n.short_name], PackedInt32Array([nation_id]))
	PlayerSystem.note(world, "Вы в плену у государства %s до %d года. Можно выкупиться или бежать." % [n.short_name, h.captive_until])


static func ransom_price(h: Hero) -> float:
	return RANSOM_PER_LEVEL * h.level


static func ransom(world: World, h: Hero) -> String:
	var cost := ransom_price(h)
	if h.gold < cost:
		return "Выкуп — %d золотых, а у вас %d." % [int(cost), int(h.gold)]
	h.gold -= cost
	if h.captive_by >= 0:
		world.nations[h.captive_by].stock[Goods.GOLD] += cost
	_free(world, h, "Вы выкупились из плена за %d золотых." % int(cost))
	return ""


static func escape(world: World, h: Hero) -> String:
	if world.rng.randf() < ESCAPE_CHANCE + h.wits() * 0.4:
		_free(world, h, "Ночью вы бежали из плена!")
		h.add_deed(world, "бежал из плена")
		return ""
	PlayerSystem.wound(world, h, 0.25, "убит при побеге из плена")
	h.captive_until += 1
	return "Побег не удался: стража избила вас, плен продлён до %d года." % h.captive_until


static func _free(world: World, h: Hero, text: String) -> void:
	h.captive_by = -1
	h.captive_until = -1
	PlayerSystem.note(world, text)


# ---------------------------------------------------------------------------
# Болезни
# ---------------------------------------------------------------------------


static func risk_disease(world: World, h: Hero, o: Outbreak, k: float = 1.0) -> void:
	var def := o.def
	if int(h.immune.get(String(def.id), -1)) > world.year or def.immune_races.has(h.race.id) \
			or def.immune_traits.any(func(t: StringName) -> bool: return h.race.has_trait(t)):
		return
	if world.rng.randf() > SICK_CHANCE * k * (0.5 if h.hero_class.id in [&"cleric", &"druid", &"shaman"] else 1.0):
		return
	h.immune[String(def.id)] = world.year + def.immunity_years
	PlayerSystem.wound(world, h, world.rng.randf_range(SICK_WOUND.x, SICK_WOUND.y), "умер от болезни: " + def.display_name.to_lower())
	if h.alive:
		PlayerSystem.note(world, "Вас свалила болезнь — %s (раны %d%%). Переболев, вы её не боитесь." % [def.display_name.to_lower(), roundi(h.wounds * 100.0)])


# ---------------------------------------------------------------------------
# Месяц героя в мире
# ---------------------------------------------------------------------------


## Месячные дела (до команд): плен, служба, болезни, цепочки событий.
## Возвращает true, если герой занят (плен или войско) и команды месяца не идут.
static func monthly(world: World, h: Hero) -> bool:
	if h.captive_by >= 0:
		if world.year >= h.captive_until:
			_free(world, h, "Срок плена вышел — вас отпустили.")
		return h.captive_by >= 0
	var rid := world.region_of[h.cell] if h.cell >= 0 else -1
	if rid >= 0:
		var o := DiseaseSystem.outbreak_in(world, rid)
		if o != null:
			risk_disease(world, h, o)
			if not h.alive:
				return true
	if not world.player_army.is_empty():
		var a := player_army(world)
		if a == null:
			leave_army(world, h, "Война окончена — войско распущено, вы снова сами по себе.")
		else:
			h.cell = a.cell
			h.gold += GENERAL_PAY if world.player_army.role == "general" else OFFICER_PAY
			if world.player_army.role == "officer":
				a.morale = minf(1.0, a.morale + 0.02)
			return true
	var now := world.year * 12 + world.month
	for c in world.player_chain:
		if int(c.at) <= now:
			world.player_chain.erase(c)
			if PlayerSystem.start_event_id(world, h, StringName(c.event)):
				return false
	return false
