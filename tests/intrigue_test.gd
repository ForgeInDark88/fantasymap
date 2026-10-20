extends SceneTree
## Headless-проверка этапа 8: разведка и тайные операции, тайные общества и
## перевороты, международные организации (запрет войн, общая оборона),
## наследие империй и собиратель земель; долгий прогон, детерминизм.
##   godot --headless --path . -s res://tests/intrigue_test.gd -- [годы]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 300
	_expect(OrgDB.ops().size() >= 6 and OrgDB.orgs().size() >= 5, "мало операций или организаций")
	_expect(PoliticsDB.get_hero_class(&"spy") != null, "нет класса героя «шпион»")

	var legacies := 0
	for cfg in [[41, 1, 18], [606, 2, 26]]:
		var s := MapSettings.new()
		s.world_seed = cfg[0]
		s.apply_size_preset(cfg[1])
		s.nation_count = cfg[2]
		var world := World.create(s)
		var sim := Simulation.new()
		for y in years:
			sim.step(world)
			if y % 50 == 49:
				_check(world)
		legacies += world.legacies.size()
		var intel := 0.0
		for n in world.nations:
			if n.alive:
				intel += n.intel
		var intrigue := 0
		for e in world.chronicle:
			if e.kind == &"intrigue":
				intrigue += 1
		print("seed %d: обществ %d, организаций %d, наследий %d, записей об интригах %d, разведка в среднем %.1f" % [
			cfg[0], world.societies.size(), world.orgs.size(), world.legacies.size(), intrigue, intel / maxf(1, world.nations.filter(func(n: Nation) -> bool: return n.alive).size())])
		_expect(intel > 0.0, "разведка не копится")
		_expect(world.societies.size() > 0, "тайные общества не возникают")
	_expect(legacies > 0, "наследия империй не возникают")

	_scripted()
	_expect(_digest(14) == _digest(14), "этап 8 недетерминирован")
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


## Сценарии по воле Бога.
func _scripted() -> void:
	var s := MapSettings.new()
	s.world_seed = 15
	var w := World.create(s)
	var sim := Simulation.new()
	for y in 40:
		sim.step(w)
	var alive: Array[Nation] = []
	for n in w.nations:
		if n.alive and n.capital_city >= 0:
			alive.append(n)
	alive.sort_custom(func(a: Nation, b: Nation) -> bool: return a.cell_count > b.cell_count)
	var a := alive[0]
	var b := alive[1]

	# Кража знаний: у жертвы есть то, чего нет у заказчика.
	var steal := OrgDB.find_op(&"steal_tech")
	for res in TechDB.all():
		var t := res as TechDef
		if t.requires.is_empty() and t.race_weight(a.race) > 0.0 and not a.techs.has(t.id):
			b.techs[t.id] = true
			break
	var tries := 0
	var before := a.techs.size()
	while a.techs.size() == before and tries < 40:
		a.intel = 60.0
		SpySystem.run(w, a, b, steal)
		tries += 1
	_expect(a.techs.size() > before, "кража знаний ни разу не удалась")

	# Тайное общество захватывает власть в слабой державе.
	var victim := alive[2]
	var cap_region := w.region_of[w.cities[victim.capital_city].cell]
	var society := SocietySystem.found(w, victim, cap_region, &"conspiracy")
	_expect(society != null and society.influence.has(cap_region), "общество не создано")
	var ruler := victim.ruler_display()
	var sys := SocietySystem.new()
	for i in 60:
		victim.stability = 0.1
		society.influence[cap_region] = 0.95
		sys.tick_year(w)
		if society.seized >= 0:
			break
	_expect(society.seized == victim.id and victim.ruler_display() != ruler, "переворот не случился")

	# Священный союз: единоверцы не воюют друг с другом и защищают своих.
	var union := OrgDB.find_org(&"holy_union")
	var members: Array[Nation] = [alive[3], alive[4], alive[5]]
	for n in members:
		n.state_religion = alive[3].state_religion
		for war in w.diplomacy.wars_of(n.id):
			w.diplomacy.end_war(w, war, 0)
		for o in w.orgs:
			var i := o.members.find(n.id)
			if o.def == union and i >= 0:
				o.members.remove_at(i)
	var org := OrgSystem.try_form(w, union, alive[3])
	_expect(org != null and org.members.size() >= 3, "священный союз не собрался")
	if org != null:
		_expect(OrgSystem.war_forbidden(w, alive[3].id, alive[4].id), "члены союза могут воевать")
		var attacker := alive[1]
		if not org.members.has(attacker.id):
			var war := w.diplomacy.declare_war(w, attacker.id, alive[3].id, &"territory")
			_expect(war.defenders.has(alive[4].id) or war.defenders.has(alive[5].id), "общая оборона не сработала")

	# Наследие: собиратель земель видит повод для войны за коренные земли.
	var lg := LegacySystem.create(w, a)
	var part := w.split_off(a, PackedInt32Array([lg.regions[lg.regions.size() - 1]]), a.race)
	if part.alive:
		_expect(part.legacy == lg.id, "осколок не унаследовал наследие")
		LegacySystem.set_collector(w, lg, a)
		_expect(LegacySystem.reunification_target(w, a, part), "собиратель не претендует на осколок")
	for y in 10:
		sim.step(w)
	_check(w)


func _check(world: World) -> void:
	for s in world.societies:
		for rid in s.influence:
			if rid < 0 or rid >= world.regions.size() or s.influence[rid] < 0.0 or s.influence[rid] > 1.0:
				_expect(false, "влияние общества %s некорректно" % s.name)
				return
	for org in world.orgs:
		if not org.alive:
			continue
		var seen := {}
		for m in org.members:
			if seen.has(m) or m < 0 or m >= world.nations.size():
				_expect(false, "повтор или неверный член в «%s»" % org.name)
				return
			seen[m] = true
	for n in world.nations:
		if n.legacy >= world.legacies.size() or n.intel < 0.0 or n.intel > SpySystem.MAX_INTEL + 0.01:
			_expect(false, "разведка или наследие %s некорректны" % n.name)
			return


func _digest(seed: int) -> String:
	var s := MapSettings.new()
	s.world_seed = seed
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 80:
		sim.step(world)
	var parts: Array[String] = []
	for n in world.nations:
		parts.append("%.4f:%d" % [n.intel, n.legacy])
	for s2 in world.societies:
		parts.append(s2.name + JSON.stringify(s2.influence))
	for o in world.orgs:
		parts.append(o.name + str(o.members))
	return "|".join(parts)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
