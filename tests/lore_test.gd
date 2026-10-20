extends SceneTree
## Headless-проверка этапа 10.1: артефакты-предметы (переходы владения,
## наследство, трофеи, сокровищница, кражи и находки), родословные (рождение,
## взросление, наследование), ордена и гильдии, боги (милость, избранники,
## Судьба), сохранение и загрузка, старые сохранения, детерминизм.
##   godot --headless --path . -s res://tests/lore_test.gd -- [годы]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 300
	for cfg in [[5, 1], [909, 0]]:
		var s := MapSettings.new()
		s.world_seed = cfg[0]
		s.apply_size_preset(cfg[1])
		var world := World.create(s)
		var sim := Simulation.new()
		for y in years:
			sim.step(world)
			if y % 50 == 49:
				_check_consistency(world)
		var held := world.artifacts.filter(func(a: Artifact) -> bool: return not a.is_lost()).size()
		print("seed %d: артефактов %d (во владении %d), родов %d, орденов %d (живых %d), избранных %d, детей-героев %d" % [cfg[0],
			world.artifacts.size(), held, world.lineages.size(), world.orders.size(), OrderSystem.alive_count(world),
			world.counters.get(&"chosen", 0), world.heroes.filter(func(h: Hero) -> bool: return not h.parents.is_empty()).size()])
		_expect(world.artifacts.size() >= 3, "артефактов почти нет")
		_expect(world.orders.size() >= 1, "ни одного ордена")
		_expect(world.heroes.any(func(h: Hero) -> bool: return h.patron_god != &""), "никто не почитает богов")
	_scripted_artifacts()
	_scripted_lineage()
	_scripted_orders()
	_scripted_gods()
	_scripted_saves()
	_expect(_digest(31) == _digest(31), "этап 10.1 недетерминирован")
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


## Каждый предмет — ровно в одном месте; ссылки героев и орденов согласованы.
func _check_consistency(world: World) -> void:
	for a in world.artifacts:
		var places := (1 if a.hero >= 0 else 0) + (1 if a.nation >= 0 else 0) + (1 if a.hero < 0 and a.nation < 0 and a.cell >= 0 else 0)
		_expect(places == 1 or (a.is_lost() and a.cell < 0), "предмет %s в нескольких местах" % a.name)
		if a.hero >= 0:
			_expect(world.heroes[a.hero].artifact_id == a.id, "у героя нет его предмета %s" % a.name)
	for h in world.heroes:
		if h.artifact_id >= 0:
			_expect(world.artifacts[h.artifact_id].hero == h.id and h.artifact == world.artifacts[h.artifact_id].name, "герой %s и его предмет разошлись" % h.name)
		for c in h.children:
			_expect(world.heroes[c].parents.has(h.id), "ребёнок не знает родителя")
		if h.order >= 0 and world.orders[h.order].alive and h.alive:
			_expect(world.orders[h.order].members.has(h.id), "член ордена %s не в списке" % world.orders[h.order].name)


func _world(seed: int = 3) -> World:
	var s := MapSettings.new()
	s.world_seed = seed
	s.apply_size_preset(0)
	return World.create(s)


func _hero(world: World) -> Hero:
	var n := world.nations[0]
	return HeroSystem.spawn(world, n, world.regions[world.region_of[world.cities[n.capital_city].cell]], true)


func _scripted_artifacts() -> void:
	var world := _world()
	var a := _hero(world)
	var b := _hero(world)
	var ring := ArtifactSystem.create(world, &"ring_of_power", a, "Кольцо Проверки", "тест")
	_expect(a.artifact_id == ring.id and a.artifact == "Кольцо Проверки" and a.artifact_mult > 1.0, "предмет не у героя")
	var p0 := b.power()
	# Трофей: победитель забирает предмет.
	a.die(world, b)
	_expect(ring.hero == b.id and b.artifact_id == ring.id and b.power() > p0, "трофей не перешёл победителю")
	# Наследство: ребёнок получает предмет родителя.
	var kid := _hero(world)
	b.children.append(kid.id)
	kid.parents.append(b.id)
	b.die(world)
	_expect(ring.hero == kid.id, "наследство не досталось ребёнку")
	# Трон: предмет становится реликвией, эффекты державе.
	var n := world.nations[kid.nation_id if kid.nation_id >= 0 else 0]
	kid.nation_id = n.id
	kid.become_ruler(world)
	_expect(ring.nation == n.id and n.effect_sources.has(&"relics"), "предмет не ушёл в сокровищницу")
	# Пала столица: реликвия — победителю.
	var winner := world.nations[1]
	ArtifactSystem.on_capital_taken(world, n, winner)
	_expect(ring.nation == winner.id and winner.effect_sources.has(&"relics") and not n.effect_sources.has(&"relics"), "реликвия не перешла победителю")
	# Потерянный предмет находится героем на месте.
	var lost := ArtifactSystem.create(world, &"amulet_of_luck", null, "", "")
	var c := _hero(world)
	ArtifactSystem.drop(world, lost, c.cell)
	_expect(ArtifactSystem.try_pick_up(world, c) and lost.hero == c.id, "потерянный предмет не нашёлся")
	_check_consistency(world)


func _scripted_lineage() -> void:
	var world := _world()
	var a := _hero(world)
	var b := _hero(world)
	b.race = a.race
	b.race_id = a.race_id
	a.spouse = b.id
	b.spouse = a.id
	a.epithet = "Драконоборец"
	var child := LineageSystem.birth(world, a, b)
	_expect(not child.is_empty() and a.lineage >= 0 and a.lineage == b.lineage, "род не основан")
	_expect(LineageSystem.unborn_children(world, a).size() == 1, "ребёнок не растёт")
	world.year = int(child.adult)
	var before := world.heroes.size()
	LineageSystem.new().tick_year(world)
	_expect(world.heroes.size() == before + 1 and world.hero_births.is_empty(), "ребёнок не стал героем")
	var h := world.heroes[world.heroes.size() - 1]
	_expect(h.parents.has(a.id) and a.children.has(h.id) and h.lineage == a.lineage, "связи родителей и детей не проставлены")
	_expect(h.race == a.race and absf(h.karma - float(child.karma)) < 0.001, "ребёнок не унаследовал расу и натуру")
	_expect(HeroSystem.new()._duel_chance(world, a, h) == 0.0, "родитель бьётся с ребёнком")


func _scripted_orders() -> void:
	var world := _world()
	var a := _hero(world)
	a.level = 10
	var o := OrderSystem.found(world, a)
	_expect(o != null and a.order == o.id and o.members.has(a.id), "орден не основан")
	var b := _hero(world)
	b.hero_class = a.hero_class
	b.karma = a.karma
	b.cell = a.cell
	OrderSystem.join(world, o, b)
	_expect(OrderSystem.duel_modifier(world, a, b) < 0.0 and HeroSystem.new()._duel_chance(world, a, b) == 0.0, "братья по ордену бьются")
	OrderSystem.new().tick_year(world)
	var hall := world.owner[o.hall_cell]
	_expect(hall < 0 or world.nations[hall].effect_sources.has(&"orders_hall"), "обитель не приносит пользы")
	a.die(world)
	b.die(world)
	OrderSystem.new().tick_year(world)
	_expect(not o.alive and o.ended_year == world.year, "опустевший орден не угас")


func _scripted_gods() -> void:
	var world := _world()
	var n := world.nations[0]
	var g := LoreDB.god(&"aelon")
	GodSystem.grant_boon(world, n, g)
	_expect(n.god_boon == &"aelon" and n.effect_sources.has(&"god"), "милость бога не дана")
	world.year = n.god_boon_until
	GodSystem.new().tick(world, n)
	_expect(n.god_boon == &"" and not n.effect_sources.has(&"god"), "милость бога не прошла")
	var h := _hero(world)
	GodSystem.make_chosen(world, h, g)
	_expect(h.chosen and h.patron_god == &"aelon" and h.artifact_id >= 0 and world.artifacts[h.artifact_id].def.id == &"divine_gift", "избранник без дара")
	_expect(Fate.max_returns(h) == Fate.MAX_RETURNS + 1, "избраннику не положен лишний шанс")
	h.die(world)
	var lm := Fate.curse(world, h)
	_expect(lm != null and lm.artifact.begins_with(g.curse_weapon), "проклятое оружие не названо по богу")
	_expect(GodSystem.gods_of(world, -1).all(func(x: GodDef) -> bool: return x.religions.is_empty()), "общие боги перепутаны")
	_expect(LoreDB.gods().all(func(x: Resource) -> bool: return not (x as GodDef).genitive.is_empty()), "у бога нет родительного падежа")


func _scripted_saves() -> void:
	var world := _world(77)
	var sim := Simulation.new()
	for y in 120:
		sim.step(world)
	var h := _hero(world)
	ArtifactSystem.create(world, &"book_of_secrets", h)
	h.level = 10
	OrderSystem.found(world, h)
	GodSystem.grant_boon(world, world.nations[0], LoreDB.god(&"war_god"))
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded.artifacts.size() == world.artifacts.size() and loaded.orders.size() == world.orders.size()
		and loaded.lineages.size() == world.lineages.size() and loaded.hero_births.size() == world.hero_births.size(), "лор не сохранился")
	var lh := loaded.heroes[h.id]
	_expect(lh.artifact_id == h.artifact_id and lh.order == h.order and lh.patron_god == h.patron_god and absf(lh.wits() - h.wits()) < 1e-6, "поля героя не сохранились")
	_expect(loaded.nations[0].god_boon == &"war_god", "милость бога не сохранилась")
	var sim_l := Simulation.new()
	for y in 5:
		sim.step(world)
		sim_l.step(loaded)
	_expect(loaded.chronicle_total == world.chronicle_total and loaded.owner == world.owner, "после загрузки история разошлась")
	var sim2 := Simulation.new()
	# Старое сохранение: оружие-строка становится предметом.
	var d: Dictionary = SaveSystem.unexact(JSON.parse_string(text))
	d.erase("lore")
	for hd in d.heroes:
		for k in ["parents", "children", "lineage", "artifact_id", "order", "god", "chosen", "awits"]:
			hd.erase(k)
	d.heroes[h.id].artifact = "Старый Меч"
	d.heroes[h.id].artifact_mult = 1.8
	var old := SaveSystem.from_dict(d)
	_expect(old != null and old.heroes[h.id].artifact_id >= 0 and old.artifacts[old.heroes[h.id].artifact_id].def.id == &"legendary_weapon", "старое оружие не стало предметом")
	sim2.step(old)


func _digest(seed: int) -> String:
	var world := _world(seed)
	var sim := Simulation.new()
	for y in 120:
		sim.step(world)
	return "%d|%d|%d|%d|%d" % [world.artifacts.size(), world.orders.size(), world.lineages.size(), world.hero_births.size(), world.chronicle_total]


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
