extends SceneTree
## Headless-проверка этапа 11.H (герой игрока в живом мире) — полный цикл:
## задания новых видов (логово, набег, караван, торговля, разведка,
## поветрие, посольство, клад), товары в мешке, служба в войске и битва,
## плен и выкуп, болезнь и иммунитет, чужой язык, цепочка событий,
## сохранение → загрузка (поля героя и одинаковое продолжение), старое
## сохранение без новых полей.
##   godot --headless --path . -s res://tests/player_world_test.gd

var _failures := 0
var world: World
var sim: Simulation
var h: Hero


func _initialize() -> void:
	_setup()
	_data()
	_quests()
	_trade()
	_caravan()
	_army_and_captivity()
	_disease_and_language()
	_chain()
	_save_load()
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _setup() -> void:
	var s := MapSettings.new()
	s.world_seed = 2024
	s.apply_size_preset(1)
	world = World.create(s)
	sim = Simulation.new()
	for y in 60:
		sim.step(world)
	var hero: Hero = null
	for x in world.wandering_heroes():
		if x.alive and not x.is_ruler:
			hero = x
			break
	_expect(hero != null and PlayerSystem.take_control(world, hero.id), "не взять героя под управление")
	h = hero
	h.level = 9
	h.gold = 2000.0
	h.wounds = 0.0
	world.player_choice = {}


## Герой — в город с дорогой к другой державе.
func _to_trade_city() -> City:
	for c in world.cities:
		if not c.alive or c.nation_id < 0:
			continue
		for rid in world.city_roads.get(c.id, PackedInt32Array()):
			var other := world.cities[world.roads[rid].other(c.id)]
			if world.roads[rid].alive and other.alive and other.nation_id >= 0 and other.nation_id != c.nation_id:
				h.cell = c.cell
				return c
	return null


func _data() -> void:
	_expect(QuestDB.all().size() >= 12, "мало видов заданий")
	for d in QuestDB.all():
		var q: QuestDef = d
		_expect(not q.title.is_empty() and q.handler != &"", "задание %s без названия или обработчика" % q.id)
	var chained := 0
	for e in LoreDB.hero_events():
		var ev := e as HeroEventDef
		if ev.chained:
			chained += 1
		for o in ev.options:
			if o.has("next"):
				_expect(LoreDB.hero_event(StringName(o.next)) != null, "событие %s: нет продолжения %s" % [ev.id, o.next])
	_expect(chained >= 3 and LoreDB.hero_events().size() >= 30, "мало событий или цепочек")


func _quest_of(kind: StringName) -> Dictionary:
	var def := QuestDB.find(kind)
	for c in world.cities:
		if not c.alive or c.nation_id < 0:
			continue
		h.cell = c.cell
		var q := PlayerQuests.make_quest(world, def, h, c, PlayerQuests._near_regions(world, world.region_of[c.cell]))
		if not q.is_empty():
			return q
	return {}


func _go(q: Dictionary) -> void:
	var cell := PlayerQuests.target_cell(world, q)
	h.cell = cell if cell >= 0 else world.regions[int(q.region)].center
	world.player_choice = {}


func _quests() -> void:
	var done := {}
	# Логово: великое чудовище слабее героя 9-го уровня с мифриловым мечом.
	var city := world.cities[world.nations.filter(func(n: Nation) -> bool: return n.alive)[0].capital_city]
	var near := world.regions[world.region_of[city.cell]].neighbors
	LairSystem.spawn(world, LairDB.find(&"troll_den"), world.regions[near[0]].center)
	world.lairs[world.lairs.size() - 1].strength = 300.0
	for kind in [&"lair", &"raid", &"intel", &"epidemic", &"embassy"]:
		if kind == &"epidemic":
			DiseaseSystem.start(world, DiseaseDB.find(&"pox"), near[0])
		if kind == &"raid":
			var t := TribeSystem.spawn(world, TribeDB.find(&"orc_clans"), -1)
			if t != null:
				t.raids = 1
				t.strength = 500.0
		var q := _quest_of(kind)
		if q.is_empty():
			print("  нет задания вида ", kind)
			continue
		world.player_quests = [q]
		_go(q)
		h.artifact_mult = 4.0
		h.wounds = 0.0
		var tries := 0
		while not world.player_quests.is_empty() and tries < 8 and h.alive:
			tries += 1
			h.wounds = 0.0
			h.captive_by = -1
			_go(q)
			PlayerQuests.check(world, h, &"arrive")
		done[kind] = world.player_quests.is_empty()
	print("задания: ", done)
	for k in done:
		_expect(done[k], "задание «%s» не выполнено" % k)
	_expect(done.size() >= 4, "мало видов заданий сделано: %s" % done)
	# Клад по слухам: правда даёт золото, вымысел — пустые руки.
	var q := PlayerQuests.rumor_quest(world, h, "treasure")
	_expect(not q.is_empty() and q.has("truth"), "клад без правды/вымысла")


func _trade() -> void:
	var city := _to_trade_city()
	_expect(city != null, "нет города с внешней дорогой")
	if city == null:
		return
	var n := world.nations[city.nation_id]
	MarketSystem.ensure(world, n)
	var gi := 0
	for i in MarketDB.size():
		if n.market_stock[i] > n.market_stock[gi]:
			gi = i
	n.market_stock[gi] += 20.0
	var stock := n.market_stock[gi]
	var held := CaravanSystem.in_transit(world)
	var msg := PlayerWorld.buy_good(world, h, gi, 5.0, 10.0)
	_expect(float(h.cargo.get(gi, 0.0)) >= 5.0 and is_equal_approx(n.market_stock[gi], stock - 5.0), "товар не куплен: " + msg)
	_expect(is_equal_approx(CaravanSystem.in_transit(world), held + 5.0), "груз героя не учтён в пути")
	var opts := PlayerWorld.goods_options(world, h)
	_expect(opts.any(func(o: Dictionary) -> bool: return o.act == "sell_good"), "нечего продать на рынке")
	# Торговый заказ: привезти товар в город.
	var q := {"kind": "trade", "title": "тест", "region": world.region_of[city.cell], "target": city.id, "giver": city.nation_id,
		"gold": 30.0, "xp": 1.0, "deadline": world.year + 3, "good": gi, "amount": 5.0}
	world.player_quests = [q]
	var gold := h.gold
	PlayerQuests.check(world, h, &"arrive")
	_expect(world.player_quests.is_empty() and h.gold > gold and not h.cargo.has(gi), "торговый заказ не выполнен")


func _caravan() -> void:
	var city := _to_trade_city()
	if city == null:
		return
	var q := _quest_of_here(&"caravan", city)
	_expect(not q.is_empty(), "нет задания охраны каравана")
	if q.is_empty():
		return
	world.player_offers = [q]
	var n := world.nations[city.nation_id]
	MarketSystem.ensure(world, n)
	for i in MarketDB.size():
		n.market_stock[i] += 30.0
	var text := PlayerQuests.accept(world, h, 0)
	var c: Caravan = null
	for x in world.caravans:
		if x.alive and x.escort == h.id:
			c = x
	_expect(c != null, "караван не вышел: " + text)
	if c == null:
		return
	_expect(PlayerWorld.escort_factor(world, c) < 1.0, "охрана не бережёт караван")
	for m in c.months + 2:
		world.roads[c.road].safety = 1.0
		sim.caravans._month(world, c)
		if not c.alive:
			break
	_expect(bool(world.player_quests[0].get("arrived", false)) if not world.player_quests.is_empty() else false, "караван не отметил прибытия")
	h.cell = world.cities[c.to_city].cell
	PlayerQuests.check(world, h, &"arrive")
	_expect(world.player_quests.is_empty(), "задание охраны не закрыто")


func _quest_of_here(kind: StringName, city: City) -> Dictionary:
	h.cell = city.cell
	return PlayerQuests.make_quest(world, QuestDB.find(kind), h, city, PlayerQuests._near_regions(world, world.region_of[city.cell]))


func _army_and_captivity() -> void:
	# Держава на войне с армией: присяга, вступление, битва.
	var army: Army = null
	for x in world.nations:
		if not x.alive:
			continue
		if world.diplomacy.wars_of(x.id).is_empty():
			for o in x.borders:
				if world.nations[o].alive and world.diplomacy.war_between(x.id, o) == null:
					world.diplomacy.declare_war(world, x.id, o, &"territory")
					break
		for d in 31:
			sim.armies.tick_day(world)
			world.day = (world.day + 1) % 30
		for a in world.armies:
			if a.alive and a.kind == &"land" and a.nation == x.id and a.war >= 0:
				army = a
				break
		if army != null:
			break
	_expect(army != null, "нет войска для службы")
	if army == null:
		return
	h.leave_service(world)
	h.nation_id = army.nation
	h.cell = army.cell
	_expect(PlayerSystem.why_not(world, &"join_army").is_empty(), "нельзя вступить в войско: " + PlayerSystem.why_not(world, &"join_army"))
	PlayerSystem.command(world, &"join_army")
	_expect(not world.player_army.is_empty() and PlayerWorld.player_army(world) == army, "герой не в войске")
	_expect(not PlayerSystem.why_not(world, &"travel").is_empty(), "в войске можно уйти в путь")
	var xp := h.xp + h.level * 100.0
	PlayerWorld.on_battle(world, army, true)
	_expect(h.xp + h.level * 100.0 > xp, "победа не дала опыта")
	# Поражение до плена (несколько попыток — плен случаен).
	var captured := false
	for k in 30:
		h.wounds = 0.0
		if world.player_army.is_empty():
			world.player_army = {"war": army.war, "nation": army.nation, "role": "officer", "since": world.year}
		PlayerWorld.on_battle(world, army, false)
		if h.captive_by >= 0:
			captured = true
			break
	_expect(captured, "поражение не ведёт в плен")
	_expect(world.player_army.is_empty(), "пленник остался в войске")
	_expect(PlayerSystem.why_not(world, &"travel") == "вы в плену" and PlayerSystem.why_not(world, &"ransom").is_empty(), "команды пленника неверны")
	h.gold = 5000.0
	PlayerSystem.command(world, &"ransom")
	_expect(h.captive_by < 0, "выкуп не освободил")


func _disease_and_language() -> void:
	# Болезнь края: заболев, герой получает иммунитет.
	for n in world.nations:
		if n.alive and n.capital_city >= 0 and not n.race.has_trait(&"no_food"):
			h.cell = world.cities[n.capital_city].cell
			break
	var rid := world.region_of[h.cell]
	world.regions[rid].immune.clear()
	var o := DiseaseSystem.start(world, DiseaseDB.find(&"red_cough"), rid)
	if o == null:
		o = DiseaseSystem.outbreak_in(world, rid)
	_expect(o != null, "поветрие не началось")
	if o != null:
		for k in 100:
			h.wounds = 0.0
			PlayerWorld.risk_disease(world, h, o, 5.0)
			if h.immune.has(String(o.def.id)):
				break
		_expect(h.immune.has(String(o.def.id)), "болезнь не оставила иммунитета")
	# Чужой язык: в краю иной семьи языков всё дороже.
	var own := PlayerWorld.native_language(world, h)
	for r in world.regions:
		if r.language >= 0 and own >= 0 and LanguageSystem.root(world, r.language) != own and not r.cells.is_empty():
			h.cell = r.center
			_expect(not PlayerWorld.speaks_here(world, h), "чужой язык не замечен")
			_expect(PlayerQuests.price(h, 100.0, world) > PlayerQuests.price(h, 100.0), "чужой язык не дорожит")
			return


func _chain() -> void:
	world.player_choice = {}
	world.player_chain.clear()
	var ev := LoreDB.hero_event(&"moneylender")
	PlayerSystem._event_outcome(world, h, ev, 0)
	_expect(world.player_chain.size() == 1, "цепочка не запомнена")
	world.player_chain[0].at = world.year * 12 + world.month
	world.player_cmd = {}
	h.captive_by = -1
	world.player_army = {}
	PlayerWorld.monthly(world, h)
	_expect(not world.player_choice.is_empty() and world.player_choice.get("event", "") == "moneylender_due", "продолжение цепочки не случилось")
	world.player_choice = {}


func _hash(w: World) -> String:
	w.update_label_anchors()
	return JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(w)), "", true, true).sha256_text()


func _save_load() -> void:
	h.cargo[2] = 7.0
	h.immune["pox"] = world.year + 10
	world.player_chain.append({"event": "fugitive_return", "at": world.year * 12 + 40})
	world.player_choice = {}
	var data: Variant = SaveSystem.exact(SaveSystem.to_dict(world))
	var text := JSON.stringify(data, "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	var lh := loaded.heroes[h.id]
	_expect(is_equal_approx(float(lh.cargo.get(2, 0.0)), 7.0) and lh.immune.has("pox") and loaded.player_chain.size() == world.player_chain.size(),
		"поля героя не сохранились")
	ArmySystem.compact(world)
	var sim2 := Simulation.new()
	for d in 360:
		sim.step_day(world)
		sim2.step_day(loaded)
		if not world.player_choice.is_empty():
			PlayerSystem.choose(world, 0)
		if not loaded.player_choice.is_empty():
			PlayerSystem.choose(loaded, 0)
	_expect(_hash(world) == _hash(loaded), "после загрузки история героя разошлась")
	# Старое сохранение без полей этапа 11.H.
	var old: Dictionary = SaveSystem.unexact(JSON.parse_string(text))
	for hd in old.heroes:
		hd.erase("cargo")
		hd.erase("captive")
		hd.erase("immune")
	old.lore.player.erase("army")
	old.lore.player.erase("chain")
	var w2 := SaveSystem.from_dict(old)
	_expect(w2 != null and w2.heroes[h.id].cargo.is_empty() and w2.player_army.is_empty(), "старое сохранение героя не загрузилось")


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
