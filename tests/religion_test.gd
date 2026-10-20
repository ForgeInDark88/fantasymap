extends SceneTree
## Headless-проверка религий: доли вер в регионах согласованы, у каждого
## государства есть вера, ереси и новые веры создаются, детерминизм, долгий
## прогон на разных картах без ошибок.
##   godot --headless --path . -s res://tests/religion_test.gd -- [годы]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 300
	_expect(ReligionDB.all().size() >= 10, "мало стартовых религий")
	for r in ReligionDB.all():
		var d := r as ReligionDef
		_expect(d.icon != null and not d.races.is_empty(), "у религии %s нет иконки или рас" % d.id)

	# Долгий прогон на двух размерах карты.
	for cfg in [[21, 0, 10], [404, 2, 24]]:
		var s := MapSettings.new()
		s.world_seed = cfg[0]
		s.apply_size_preset(cfg[1])
		s.nation_count = cfg[2]
		var world := World.create(s)
		var sim := Simulation.new()
		for n in world.nations:
			_expect(n.state_religion >= 0, "у стартового государства нет веры")
		for y in years:
			sim.step(world)
			if y % 50 == 49:
				_check(world)
		var heresies := 0
		for r in world.religions:
			if r.is_heresy():
				heresies += 1
		var holy := 0
		for w in world.diplomacy.past_wars + world.diplomacy.wars:
			if w.cause in [&"holy", &"crusade", &"schism", &"religious"]:
				holy += 1
		print("seed %d: вер %d (живых %d, ересей %d), войн за веру %d" % [cfg[0], world.religions.size(),
			ReligionSystem.alive_count(world), heresies, holy])
		_expect(ReligionSystem.alive_count(world) <= ReligionSystem.MAX_RELIGIONS, "слишком много вер")

	# Ересь и новая вера по воле Бога.
	var s2 := MapSettings.new()
	s2.world_seed = 9
	var w2 := World.create(s2)
	var sim2 := Simulation.new()
	for y in 40:
		sim2.step(w2)
	var big: Nation = null
	for n in w2.nations:
		if n.alive and (big == null or n.region_counts.size() > big.region_counts.size()):
			big = n
	var before := w2.religions.size()
	var heresy := ReligionSystem.start_heresy(w2, big)
	_expect(heresy != null and heresy.is_heresy() and w2.religions.size() == before + 1, "ересь не создана")
	var found := false
	for rid in big.region_counts:
		if w2.regions[rid].faith.has(heresy.id):
			found = true
	for n in w2.nations:
		if n.state_religion == heresy.id:
			found = true  # раскол: ересь стала верой отколовшихся
	_expect(found, "ересь нигде не исповедуют")
	var faith := ReligionSystem.found_religion(w2, big)
	_expect(faith != null and big.state_religion == faith.id and not faith.is_heresy(), "новая вера не стала государственной")
	for y in 20:
		sim2.step(w2)
	_check(w2)

	# Единоверцы относятся друг к другу лучше, чем иноверцы.
	var a := w2.nations.filter(func(n: Nation) -> bool: return n.alive)
	if a.size() >= 2:
		var x: Nation = a[0]
		var y2: Nation = a[1]
		var keep := y2.state_religion
		y2.state_religion = x.state_religion
		var same := w2.diplomacy.opinion(w2, x.id, y2.id)
		y2.state_religion = (x.state_religion + 1) % w2.religions.size()
		var other := w2.diplomacy.opinion(w2, x.id, y2.id)
		y2.state_religion = keep
		_expect(same >= other, "единоверцы не ближе иноверцев")

	# Детерминизм: один seed — одна история вер.
	var h1 := _faith_digest(9, 60)
	var h2 := _faith_digest(9, 60)
	_expect(h1 == h2, "религии недетерминированы")

	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _faith_digest(seed: int, years: int) -> String:
	var s := MapSettings.new()
	s.world_seed = seed
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in years:
		sim.step(world)
	var parts: Array[String] = []
	for r in world.regions:
		parts.append(JSON.stringify(r.faith))
	for n in world.nations:
		parts.append(str(n.state_religion))
	return str(world.religions.size()) + "|" + "|".join(parts)


func _check(world: World) -> void:
	for region in world.regions:
		if region.faith.is_empty():
			continue
		var sum := 0.0
		for r in region.faith:
			if r < 0 or r >= world.religions.size():
				_expect(false, "неизвестная вера %d в регионе %d" % [r, region.id])
				return
			sum += region.faith[r]
		if absf(sum - 1.0) > 0.02:
			_expect(false, "доли вер региона %d в сумме %.3f" % [region.id, sum])
			return
	for n in world.nations:
		if n.alive and (n.state_religion < 0 or n.state_religion >= world.religions.size()):
			_expect(false, "у государства %s нет веры" % n.name)
			return
		if n.alive and (n.faith_unity < 0.0 or n.faith_unity > 1.001):
			_expect(false, "единство веры вне 0..1 у %s" % n.name)
			return


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
