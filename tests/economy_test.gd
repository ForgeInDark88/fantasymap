extends SceneTree
## Headless-проверка этапа 11.D (рынок и общество):
##   • данные data/goods: все товары, у каждого есть откуда взяться;
##   • учёт рынка по миру: произведено = потреблено + испорчено + прирост
##     запасов + прирост товаров в пути + разграблено;
##   • цена: дефицит дорожит, избыток дешевит; караваны везут из дешёвого в
##     дорогое и доходят; небезопасная дорога грабит;
##   • инфляция от золотой лихорадки; займы и дефолт; наёмники нанимаются и без
##     платы уходят; сословия (сумма 1) и рабство;
##   • сохранение → загрузка посреди каравана: одинаковое продолжение;
##   • производительность на огромной карте.
##   godot --headless --path . -s res://tests/economy_test.gd -- [годы]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 150
	_data()
	_balance(years)
	_prices_and_caravans()
	_finance()
	_society()
	_save_load()
	_performance()
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _data() -> void:
	var ids := {}
	for d in MarketDB.all():
		var g: GoodDef = d
		ids[g.id] = true
		var source := not g.biomes.is_empty() or g.coastal > 0.0 or g.river > 0.0 or g.deposit != &"" or g.crafted_from != &""
		_expect(source, "товар %s: неоткуда взяться" % g.id)
		_expect(g.base_price > 0.0 and g.spoil >= 0.0 and g.spoil < 1.0, "товар %s: цена или порча" % g.id)
		var need := g.army_demand > 0.0 or not g.demand.is_empty()
		_expect(need, "товар %s: никому не нужен" % g.id)
		if g.deposit != &"":
			_expect(EconomyDB.deposits().any(func(x: DepositDef) -> bool: return x.id == g.deposit), "товар %s: нет месторождения" % g.id)
		if g.crafted_from != &"":
			_expect(Goods.index_of(g.crafted_from) >= 0, "товар %s: нет сырья" % g.id)
	for id in [&"grain", &"salt", &"wine", &"silk", &"spices", &"horses", &"furs", &"weapons", &"gems", &"mithril", &"fish"]:
		_expect(ids.has(id), "нет товара %s" % id)


## Сумма запасов всех государств (живых и павших) и товаров в пути.
func _held(world: World) -> float:
	var sum := 0.0
	for n in world.nations:
		for x in n.market_stock:
			sum += x
	return sum + CaravanSystem.in_transit(world)


func _balance(years: int) -> void:
	for cfg in [[2024, 1], [77, 0]]:
		var s := MapSettings.new()
		s.world_seed = cfg[0]
		s.apply_size_preset(cfg[1])
		var world := World.create(s)
		var sim := Simulation.new()
		for y in 20:
			sim.step(world)
		var t0 := world.market_totals.duplicate()
		var h0 := _held(world)
		for y in years:
			sim.step(world)
		var t1 := world.market_totals
		var made := float(t1.get("made", 0.0)) - float(t0.get("made", 0.0))
		var used := float(t1.get("used", 0.0)) - float(t0.get("used", 0.0))
		var lost := float(t1.get("lost", 0.0)) - float(t0.get("lost", 0.0))
		var robbed := float(t1.get("robbed", 0.0)) - float(t0.get("robbed", 0.0))
		var dh := _held(world) - h0
		var gap := made - (used + lost + dh + robbed)
		print("seed %d: произведено %s = потреблено %s + испорчено %s + запасы %+.0f + разграблено %s (расхождение %.1f, %.4f%%)" % [
			cfg[0], ArmySystem._num(made), ArmySystem._num(used), ArmySystem._num(lost), dh, ArmySystem._num(robbed), gap,
			absf(gap) / maxf(1.0, made) * 100.0])
		_expect(made > 0.0 and used > 0.0, "рынок пуст")
		_expect(absf(gap) <= maxf(1.0, made * 0.001), "учёт рынка не сходится: %.1f" % gap)
		_expect(world.counters.get(&"caravans_arrived", 0) > 0, "караваны не доходят")
		_expect(world.counters.get(&"mercs_hired", 0) > 0, "наёмников никто не нанимает")
		# Сословия — доли, сумма 1; цены и индекс цен в разумных рамках.
		for n in world.nations:
			if not n.alive or n.market_price.size() != MarketDB.size():
				continue
			var sum := 0.0
			for k in 4:
				_expect(n.classes[k] >= 0.0, "доля сословия < 0")
				sum += n.classes[k]
			_expect(absf(sum - 1.0) < 0.01, "сословия не в сумме 1: %.3f" % sum)
			_expect(n.inflation >= 0.8 and n.inflation <= 2.51, "индекс цен вне рамок: %.2f" % n.inflation)
			for i in MarketDB.size():
				_expect(n.market_stock[i] >= -0.01 and n.market_price[i] > 0.0, "%s: запас или цена неверны" % n.name)


func _world(seed: int, years: int, size: int = 0) -> Array:
	var s := MapSettings.new()
	s.world_seed = seed
	s.apply_size_preset(size)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in years:
		sim.step(world)
	return [world, sim]


func _prices_and_caravans() -> void:
	var ws := _world(2024, 60, 1)
	var world: World = ws[0]
	var sim: Simulation = ws[1]
	var n: Nation = null
	for x in world.nations:
		if x.alive and (n == null or x.population > n.population):
			n = x
	var grain := MarketDB.index_of(&"grain")
	n.market_stock[grain] = 0.0
	sim.market.tick(world, n)
	var p_short := n.market_price[grain]
	for k in 3:
		n.market_stock[grain] = n.market_demand[grain] * 50.0 + 1000.0
		sim.market.tick(world, n)
	var p_glut := n.market_price[grain]
	print("цена зерна: дефицит %.2f, избыток %.2f" % [p_short, p_glut])
	_expect(p_glut < p_short, "избыток не дешевит")
	# Караван Бога от столицы: товар уходит с рынка и приходит соседу.
	var city := world.cities[n.capital_city]
	var c: Caravan = null
	for x in world.cities:
		if x.alive and not world.city_roads.get(x.id, PackedInt32Array()).is_empty():
			for rid in world.city_roads[x.id]:
				var other := world.cities[world.roads[rid].other(x.id)]
				if world.roads[rid].alive and other.alive and other.nation_id != x.nation_id and other.nation_id >= 0:
					city = x
					break
		if city != world.cities[n.capital_city]:
			break
	var from := world.nations[city.nation_id]
	MarketSystem.ensure(world, from)
	for i in MarketDB.size():
		from.market_stock[i] += 50.0
	c = GodTools.send_caravan(world, city.cell)
	_expect(c != null, "караван не вышел")
	if c == null:
		return
	world.roads[c.road].safety = 1.0
	var to := world.nations[c.to_nation]
	var before := to.market_stock[c.good]
	for m in c.months + 1:
		world.roads[c.road].safety = 1.0
		sim.step_month(world)
	_expect(not c.alive and not c.robbed, "караван не дошёл")
	_expect(to.market_in[c.good] >= c.amount * 0.99 or to.market_stock[c.good] > before, "товар не пришёл получателю")
	# Небезопасная дорога грабит.
	var robbed := 0
	for k in 12:
		from.market_stock[c.good] += 10.0
		var x := CaravanSystem.launch(world, world.roads[c.road], c.from_city, c.to_city, c.good, 5.0, 1.0)
		world.roads[c.road].safety = 0.0
		for m in x.months + 1:
			world.roads[c.road].safety = 0.0
			sim.caravans._month(world, x)
			if not x.alive:
				break
		if x.robbed:
			robbed += 1
	_expect(robbed > 0, "на опасной дороге караваны не грабят")


func _finance() -> void:
	var ws := _world(4242, 40)
	var world: World = ws[0]
	var sim: Simulation = ws[1]
	var alive := world.nations.filter(func(x: Nation) -> bool: return x.alive)
	var n: Nation = alive[0]
	# Золотая лихорадка → индекс цен растёт.
	var infl0 := n.inflation
	for k in 3:
		GodTools.gold_rush(world, world.cities[n.capital_city].cell)
		n.stock[Goods.GOLD] += 20000.0
		sim.market.tick(world, n)
	print("индекс цен после золотой лихорадки: %.2f → %.2f" % [infl0, n.inflation])
	_expect(n.inflation > infl0, "золото не разгоняет цены")
	# Заём и дефолт.
	var d: Nation = alive[1]
	world.loans = world.loans.filter(func(l: Dictionary) -> bool: return int(l.debtor) != d.id)
	world.defaults.erase(str(d.id))
	d.stock[Goods.GOLD] = -300.0
	sim.credit.tick_year(world)
	_expect(CreditSystem.debts_of(world, d.id) > 0.0, "заём не выдан")
	var defaults: int = world.counters.get(&"defaults", 0)
	for k in 3:
		d.stock[Goods.GOLD] = -500.0
		sim.credit._payments(world)
	_expect(world.counters.get(&"defaults", 0) > defaults and CreditSystem.debts_of(world, d.id) == 0.0, "дефолта нет")
	# Наёмники: наём воюющим, без платы — уход.
	var a: Nation = alive[2]
	var b: Nation = alive[3]
	if world.diplomacy.war_between(a.id, b.id) == null:
		world.diplomacy.declare_war(world, a.id, b.id, &"territory")
	var m := MercSystem.spawn(world, world.cities[a.capital_city])
	for x in world.nations:
		x.stock[Goods.GOLD] = minf(x.stock[Goods.GOLD], 10.0)
	a.stock[Goods.GOLD] = 5000.0
	sim.mercs._seek(world, m)
	_expect(m.employer == a.id, "наёмники не нанялись к воюющему")
	sim.mercs.tick_year(world)
	_expect(a.merc_power > 0.0, "наёмники не дают силы")
	a.stock[Goods.GOLD] = 0.0
	b.stock[Goods.GOLD] = 5000.0
	sim.mercs._serve(world, m)
	_expect(m.employer != a.id, "без платы наёмники не ушли")


func _society() -> void:
	var ws := _world(9, 30)
	var world: World = ws[0]
	var sim: Simulation = ws[1]
	var n: Nation = world.nations.filter(func(x: Nation) -> bool: return x.alive)[0]
	n.slavery = true
	for y in 15:
		sim.market.tick(world, n)
		n.slavery = true
	var with := n.classes[MarketSystem.SLAVES]
	GodTools.toggle_slavery(world, world.cities[n.capital_city].cell)
	_expect(not n.slavery, "рабство не отменено")
	for y in 30:
		sim.market.tick(world, n)
		n.slavery = false
	print("доля рабов: при рабстве %.3f, после отмены %.3f" % [with, n.classes[MarketSystem.SLAVES]])
	_expect(with > 0.03 and n.classes[MarketSystem.SLAVES] < with * 0.2, "рабство не меняет сословий")


func _hash(world: World) -> String:
	world.update_label_anchors()
	return JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", true, true).sha256_text()


func _save_load() -> void:
	var ws := _world(2024, 60, 1)
	var world: World = ws[0]
	var sim: Simulation = ws[1]
	for d in 360 * 5:
		sim.step_day(world)
		if world.caravans.any(func(c: Caravan) -> bool: return c.alive):
			break
	var moving := world.caravans.filter(func(c: Caravan) -> bool: return c.alive).size()
	_expect(moving > 0, "нет каравана в пути для проверки сохранения")
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded.caravans.size() == world.caravans.filter(func(c: Caravan) -> bool: return c.alive).size()
		and loaded.mercs.size() == MercSystem.alive_companies(world).size() and loaded.loans.size() == world.loans.size(), "рынок не сохранился")
	ArmySystem.compact(world)
	var sim2 := Simulation.new()
	for d in 360 * 2:
		sim.step_day(world)
		sim2.step_day(loaded)
	_expect(_hash(world) == _hash(loaded), "после загрузки с караванами в пути история разошлась")


func _performance() -> void:
	var s := MapSettings.new()
	s.world_seed = 5
	s.apply_size_preset(3)
	s.nation_count = 40
	var world := World.create(s)
	var sim := Simulation.new()
	sim.profile = true
	var years := 100
	for y in years:
		sim.step(world)
	var line := "огромная карта, %d лет:" % years
	for k in ["market", "caravans", "mercs", "credit"]:
		var e: Array = sim.timings.get(k, [0, 0])
		var per_month: float = e[0] / 1000.0 / years / 12.0
		line += " %s %.3f мс/мес. (худший %.1f мс);" % [k, per_month, e[1] / 1000.0]
		_expect(per_month < 0.5, "%s дольше 0,5 мс в месяц" % k)
		_expect(e[1] / 1000.0 < 10.0, "%s: худший вызов дольше 10 мс" % k)
	print(line)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
