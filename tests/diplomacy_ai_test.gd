extends SceneTree
## Headless-проверка этапа 11.E (дипломатия и ИИ):
##   • данные data/personalities; у каждой живой державы — нрав и его эффект;
##   • долгий прогон: сделки разных видов, журнал в пределах, столицы
##     переносятся (и всегда верны), слухи — и правда, и вымысел;
##   • нрав влияет: завоеватели начинают войны чаще отшельников;
##   • сделки исполняются честно: продажа края (клетки и золото), обмен
##     товарами (общий запас не меняется), выкуп мира (война кончена);
##   • слухи: сильная разведка не верит вымыслу, слабая — верит; поверивший
##     охотнее нападает на «слабого»;
##   • сохранение → загрузка: одинаковое продолжение; скорость.
##   godot --headless --path . -s res://tests/diplomacy_ai_test.gd -- [годы]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 250
	_data()
	_long_run(years)
	_deals()
	_rumors()
	_save_load()
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _data() -> void:
	_expect(PersonalityDB.all().size() >= 6, "мало характеров")
	for d in PersonalityDB.all():
		var p: PersonalityDef = d
		_expect(not p.display_name.is_empty() and p.aggression > 0.0 and p.deal_rate > 0.0, "нрав %s: параметры" % p.id)
		for r in p.races:
			_expect(RaceDB.get_race(r) != null, "нрав %s: нет народа %s" % [p.id, r])
		for g in p.governments:
			_expect(PoliticsDB.government(g) != null, "нрав %s: нет формы правления %s" % [p.id, g])
		for k in p.deal_taste:
			_expect(DealSystem.KINDS.has(k), "нрав %s: нет сделки %s" % [p.id, k])


func _check_capitals(world: World, where: String) -> void:
	for n in world.nations:
		if not n.alive or n.capital_city < 0:
			continue
		var c := world.cities[n.capital_city]
		_expect(c.alive and c.nation_id == n.id and c.is_capital, "%s: столица %s неверна" % [where, n.name])
		var caps := 0
		for id in n.city_ids:
			if world.cities[id].is_capital:
				caps += 1
		_expect(caps == 1, "%s: у %s столиц %d" % [where, n.name, caps])


func _long_run(years: int) -> void:
	var wars_by := {}
	var nation_years := {}
	var accepted := {}
	var rumors_true := 0
	var rumors_false := 0
	var moved := 0
	for cfg in [[2024, 1], [77, 1], [9, 1]]:
		var s := MapSettings.new()
		s.world_seed = cfg[0]
		s.apply_size_preset(cfg[1])
		var world := World.create(s)
		var sim := Simulation.new()
		var starter := {}
		for y in years:
			sim.step(world)
			for n in world.nations:
				if n.alive and n.personality != null:
					nation_years[n.personality.id] = nation_years.get(n.personality.id, 0) + 1
			for w in world.diplomacy.wars:
				if w.start_year == world.year - 1 and not starter.has(w.id):
					starter[w.id] = true
					var a := world.nations[w.first_attacker if w.first_attacker >= 0 else w.leader(1)]
					if a.personality != null:
						wars_by[a.personality.id] = wars_by.get(a.personality.id, 0) + 1
			if y % 50 == 49:
				_check_capitals(world, "seed %d, год %d" % [cfg[0], world.year])
		for n in world.nations:
			if n.alive and n.founded_year < world.year - 1:
				_expect(n.personality != null, "держава без нрава")
				if n.personality != null:
					_expect(is_equal_approx(n.effect_sources.get(&"personality", {}).get("aggression_mult", -1.0), n.personality.aggression), "нрав без эффекта")
		for j in world.diplo_journal:
			if bool(j.ok):
				accepted[j.kind] = accepted.get(j.kind, 0) + 1
		_expect(world.diplo_journal.size() <= DealSystem.JOURNAL_LIMIT, "журнал без предела")
		rumors_true += world.counters.get(&"rumors", 0) - world.counters.get(&"rumors_false", 0)
		rumors_false += world.counters.get(&"rumors_false", 0)
		moved += world.counters.get(&"capitals_moved", 0)
	print("сделки (приняты): %s; слухов правдивых %d, ложных %d; столиц перенесено %d" % [accepted, rumors_true, rumors_false, moved])
	_expect(accepted.size() >= 4, "мало видов сделок: %s" % accepted)
	_expect(rumors_true > 0 and rumors_false > 0, "слухи только одного рода")
	_expect(moved > 0, "столицы не переносятся")
	var rate := func(id: StringName) -> float: return float(wars_by.get(id, 0)) / maxf(1.0, float(nation_years.get(id, 0))) * 100.0
	print("войн на 100 лет державы: завоеватель %.2f, отшельник %.2f, торгаш %.2f, дипломат %.2f" % [rate.call(&"conqueror"), rate.call(&"hermit"),
		rate.call(&"merchant"), rate.call(&"diplomat")])
	_expect(rate.call(&"conqueror") > rate.call(&"hermit"), "нрав не влияет на войны")


func _world(seed: int, years: int) -> Array:
	var s := MapSettings.new()
	s.world_seed = seed
	s.apply_size_preset(1)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in years:
		sim.step(world)
	return [world, sim]


func _deals() -> void:
	var ws := _world(2024, 60)
	var world: World = ws[0]
	var sim: Simulation = ws[1]
	# Продажа края: клетки и золото переходят.
	var sold := false
	for seller in world.nations:
		if sold or not seller.alive:
			continue
		for b in seller.borders:
			var buyer := world.nations[b]
			if not buyer.alive or world.diplomacy.war_between(seller.id, b) != null:
				continue
			var rid := DealSystem._sale_region(world, seller, buyer)
			if rid < 0:
				continue
			buyer.stock[Goods.GOLD] += 10000.0
			var offer := {"kind": &"region", "from": buyer.id, "to": seller.id, "seller": seller.id, "buyer": buyer.id, "region": rid, "price": 100.0}
			var gold := seller.stock[Goods.GOLD]
			var cells := seller.region_counts[rid]
			DealSystem._execute(world, offer)
			_expect(not seller.region_counts.has(rid) and buyer.region_counts.get(rid, 0) >= cells, "край не перешёл к покупателю")
			_expect(is_equal_approx(seller.stock[Goods.GOLD], gold + 100.0), "продавец не получил золота")
			sold = true
			break
	_expect(sold, "не нашлось края для продажи")
	# Обмен товарами: общий запас не меняется.
	var alive := world.nations.filter(func(n: Nation) -> bool: return n.alive and n.market_price.size() == MarketDB.size())
	var a: Nation = alive[0]
	var b2: Nation = alive[1]
	var total := 0.0
	for i in MarketDB.size():
		total += a.market_stock[i] + b2.market_stock[i]
	DealSystem._execute(world, {"kind": &"goods", "from": a.id, "to": b2.id, "give": 0, "take": 1, "give_amount": 5.0, "take_amount": 5.0})
	var after := 0.0
	for i in MarketDB.size():
		after += a.market_stock[i] + b2.market_stock[i]
	_expect(absf(after - total) < 0.01, "обмен товарами потерял товар")
	# Выкуп мира: война кончается, золото переходит.
	var x: Nation = alive[2]
	var y: Nation = alive[3]
	var war := world.diplomacy.war_between(x.id, y.id)
	if war == null:
		war = world.diplomacy.declare_war(world, x.id, y.id, &"territory")
	x.stock[Goods.GOLD] = 1000.0
	DealSystem._execute(world, {"kind": &"peace", "from": x.id, "to": y.id, "war": war.id, "payer": x.id, "payee": y.id, "price": 200.0})
	_expect(not war.active and world.diplomacy.war_between(x.id, y.id) == null and is_equal_approx(x.stock[Goods.GOLD], 800.0), "мир не выкуплен")
	# Предложение через Бога доходит до журнала.
	var before := world.diplo_journal.size()
	GodTools.force_deal(world, sim, alive[4].id, alive[5].id)
	_expect(world.diplo_journal.size() == before + 1, "предложение не записано в журнал")


func _rumors() -> void:
	var ws := _world(77, 40)
	var world: World = ws[0]
	var alive := world.nations.filter(func(n: Nation) -> bool: return n.alive)
	var victim: Nation = alive[0]
	var spy: Nation = alive[1]
	var fool: Nation = alive[2]
	var r := RumorSystem.spread(world, &"weak", victim, null, -1, false)
	r.cred = 30.0
	spy.intel = 60.0
	fool.intel = 0.0
	_expect(not RumorSystem.believes(world, spy, r), "сильная разведка верит вымыслу")
	_expect(RumorSystem.believes(world, fool, r), "слабая разведка не верит слуху")
	_expect(RumorSystem.war_factor(world, fool, victim) > 1.0 and is_equal_approx(RumorSystem.war_factor(world, spy, victim), 1.0),
		"слух не влияет на желание воевать")
	var t := RumorSystem.spread(world, &"weak", victim, null, -1, true)
	_expect(RumorSystem.believes(world, spy, t), "правде не верят")


func _hash(world: World) -> String:
	world.update_label_anchors()
	return JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", true, true).sha256_text()


func _save_load() -> void:
	var ws := _world(31, 80)
	var world: World = ws[0]
	var sim: Simulation = ws[1]
	for d in 133:
		sim.step_day(world)
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded.diplo_journal.size() == world.diplo_journal.size() and loaded.rumors.size() == world.rumors.size(), "дипломатия не сохранилась")
	for n in loaded.nations:
		if n.alive:
			_expect(n.personality == world.nations[n.id].personality, "нрав не сохранился")
	ArmySystem.compact(world)
	var sim2 := Simulation.new()
	for d in 360 * 3:
		sim.step_day(world)
		sim2.step_day(loaded)
	_expect(_hash(world) == _hash(loaded), "после загрузки история разошлась")


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
