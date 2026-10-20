extends SceneTree
## Headless-проверка режима «Сыграй за героя» (этап 10.2): полный цикл —
## старт (свой герой и взятый под управление), путешествие по графу регионов,
## события и встречи с выбором, все команды, бездействие без гибели,
## сохранение с ожидающим выбором, гибель → Чертоги Судьбы → наследник /
## выход в режим наблюдателя; мир при этом живёт дальше без ошибок.
##   godot --headless --path . -s res://tests/player_test.gd

var _failures := 0


func _initialize() -> void:
	var s := MapSettings.new()
	s.world_seed = 4242
	s.apply_size_preset(1)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 30:
		sim.step(world)
	# Старт: свой герой.
	var region := world.region_at(world.cities[world.nations[0].capital_city].cell)
	var hero := PlayerSystem.create_hero(world, world.nations[0].race, PoliticsDB.get_hero_class(&"warrior"), "Испытатель", region.id)
	_expect(hero != null and world.player == hero.id and hero.name == "Испытатель", "свой герой не создан")
	hero.max_age = hero.age + 500  # не умрёт от старости во время проверки
	# Бездействие: герой отдыхает и не гибнет (события решаем первым вариантом без риска).
	for m in 36:
		sim.step_month(world)
		_resolve_safe(world)
	_expect(hero.alive and world.player == hero.id, "бездействующий герой погиб или потерял управление")
	_expect(hero.goal_cell < 0 and hero.nation_id < 0, "автономное поведение не отключено")
	# Путешествие в далёкий регион.
	var target := _far_region(world, hero)
	var plan := PlayerSystem.plan_path(world, world.region_of[hero.cell], target)
	_expect(not plan.is_empty() and int(plan.months) > 0, "путь не проложен")
	_expect(PlayerSystem.command(world, &"travel", target) == "", "команда пути не принята")
	var months := 0
	while world.region_of[hero.cell] != target and months < 60 and hero.alive:
		sim.step_month(world)
		_resolve_safe(world)
		months += 1
	_expect(not hero.alive or world.region_of[hero.cell] == target, "герой не дошёл (%d мес.)" % months)
	_expect(not hero.alive or world.player_journal.any(func(j: Dictionary) -> bool: return String(j.text).begins_with("Вы пришли")), "в журнале нет прихода")
	# Событие с выбором: мир ждёт решения.
	_expect(PlayerSystem.start_event(world, hero) and not world.player_choice.is_empty(), "событие не началось")
	var day := world.day
	var choice_title: String = world.player_choice.title
	# Сохранение посреди выбора.
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded.player == world.player and loaded.player_choice.title == choice_title
		and loaded.player_journal.size() == world.player_journal.size(), "режим героя не сохранился")
	_expect(PlayerSystem.choose(loaded, 0) != "" and loaded.player_choice.is_empty(), "выбор в загруженном мире не сработал")
	_expect(PlayerSystem.choose(world, 0) != "" and world.player_choice.is_empty(), "выбор не сработал")
	_expect(world.day == day, "")
	# Встреча с другим героем.
	var other := HeroSystem.spawn(world, world.nations[0], world.region_at(hero.cell), true)
	other.cell = hero.cell
	PlayerSystem.encounter(world, hero, other, false)
	_expect((world.player_choice.options as Array).size() >= 2, "встреча без вариантов")
	PlayerSystem.choose(world, 0)
	# Все команды: либо выполняются, либо объясняют, почему нельзя.
	for c in PlayerSystem.COMMANDS:
		if c[0] == &"travel" or not hero.alive:
			continue
		var why := PlayerSystem.why_not(world, c[0])
		var res := PlayerSystem.command(world, c[0])
		_expect(res == why, "команда %s: «%s» ≠ «%s»" % [c[0], res, why])
		for m in 4:
			sim.step_month(world)
			_resolve_safe(world)
	# Гибель → Чертоги Судьбы → наследник.
	if not hero.alive:
		_expect(world.player_choice.get("kind", "") == "death" or world.player != hero.id, "гибель без Чертогов Судьбы")
		PlayerSystem.release(world)
		hero = PlayerSystem.create_hero(world, world.nations[0].race, PoliticsDB.get_hero_class(&"mage"), "", region.id)
	var kid := HeroSystem.spawn(world, world.nations[0], world.region_at(hero.cell), true)
	kid.parents.append(hero.id)
	hero.children.append(kid.id)
	hero.die(world)
	_expect(world.player_choice.get("kind", "") == "death", "нет Чертогов Судьбы")
	_expect(String(world.player_choice.options[0].act) == "heir", "наследник не предложен")
	PlayerSystem.choose(world, 0)
	_expect(world.player == kid.id and world.player_choice.is_empty(), "не перешли к наследнику")
	# Гибель наследника → выход в режим наблюдателя.
	kid.die(world)
	var observe := (world.player_choice.options as Array).size() - 1
	_expect(String(world.player_choice.options[observe].act) == "observe", "нет выхода к наблюдению")
	PlayerSystem.choose(world, observe)
	_expect(world.player == -1 and world.player_choice.is_empty() and world.player_cmd.is_empty(), "режим не завершился")
	# Мир живёт дальше; взять под управление обычного героя.
	for y in 5:
		sim.step(world)
	var npc: Hero = null
	for h in world.wandering_heroes():
		if h.alive:
			npc = h
	_expect(npc == null or PlayerSystem.take_control(world, npc.id), "не удалось взять героя под управление")
	for y in 3:
		sim.step(world)
		_resolve_safe(world)
	print("player_test: путь %d мес., журнал %d записей, репутаций %d" % [months, world.player_journal.size(), world.player_rep.size()])
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


## Решает ждущий выбор вариантом без боя (как осторожный игрок).
func _resolve_safe(world: World) -> void:
	var guard := 0
	while not world.player_choice.is_empty() and guard < 5:
		guard += 1
		var opts: Array = world.player_choice.options
		var pick := opts.size() - 1
		for i in opts.size():
			var act := String(opts[i].act)
			if act in ["pass", "flee", "talk", "heir"]:
				pick = i
				break
		if String(world.player_choice.kind) == "event":
			var ev := LoreDB.hero_event(StringName(world.player_choice.event))
			for i in ev.options.size():
				if not ev.options[i].has("power"):
					pick = i
					break
		PlayerSystem.choose(world, pick)


func _far_region(world: World, hero: Hero) -> int:
	var from := world.region_of[hero.cell]
	var best := from
	var best_m := 0
	for r in world.regions:
		if r.cells.is_empty() or r.id == from:
			continue
		var plan := PlayerSystem.plan_path(world, from, r.id)
		if not plan.is_empty() and int(plan.months) > best_m and int(plan.months) <= 8:
			best_m = int(plan.months)
			best = r.id
	return best


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
