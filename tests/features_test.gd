extends SceneTree
## Флаги возможностей (этап 12.0): режим «Сыграй за героя» скрыт. Сохранение
## с героем игрока при выключенном флаге грузится с автономным героем (без
## команд, выбора и плена), мир живёт дальше без ошибок; пересохранённый мир
## при включённом флаге возвращает герою игрока управление. Скрыты достижения,
## разделы справочника и шаг обучения режима.
##   godot --headless --path . -s res://tests/features_test.gd

var _failures := 0


func _initialize() -> void:
	var s := MapSettings.new()
	s.world_seed = 31337
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 10:
		sim.step(world)
	var hero: Hero = null
	for h in world.wandering_heroes():
		if h.alive and not h.is_ruler:
			hero = h
			break
	_expect(hero != null, "нет героя-странника")
	if hero == null:
		_finish()
		return
	# Выключенный флаг: взять героя нельзя.
	Features.HERO_PLAY = false
	_expect(not PlayerSystem.take_control(world, hero.id), "режим скрыт, но героя можно взять")
	# Включённый: берём, отдаём команду, ждём выбора — и сохраняем.
	Features.HERO_PLAY = true
	_expect(PlayerSystem.take_control(world, hero.id), "режим включён, но героя взять нельзя")
	world.player_choice = {"title": "проверка", "options": []}
	hero.captive_by = 0
	var data := SaveSystem.to_dict(world)
	# Скрытый режим: герой автономен, мир не стоит на выборе.
	Features.HERO_PLAY = false
	var loaded := SaveSystem.from_dict(JSON.parse_string(JSON.stringify(data)))
	_expect(loaded.player == -1, "скрытый режим: герой игрока остался под управлением")
	_expect(loaded.player_dormant == hero.id, "скрытый режим: id героя игрока не запомнен")
	_expect(loaded.player_choice.is_empty() and loaded.player_cmd.is_empty(), "скрытый режим: висят команда или выбор")
	_expect(loaded.heroes[hero.id].captive_by == -1, "скрытый режим: герой остался в плену у игровой механики")
	var sim2 := Simulation.new()
	for m in 24:
		sim2.step_month(loaded)
	_expect(loaded.player == -1, "скрытый режим: управление вернулось само")
	# Пересохранили при скрытом режиме → включили → герой снова под управлением.
	var data2 := SaveSystem.to_dict(loaded)
	Features.HERO_PLAY = true
	var back := SaveSystem.from_dict(JSON.parse_string(JSON.stringify(data2)))
	_expect(back.player == hero.id or not back.heroes[hero.id].alive, "включённый флаг: герой игрока не вернулся")
	# Скрытые достижения, справочник, обучение.
	Features.HERO_PLAY = false
	var tracker := AchievementTracker.new("user://features_test_ach.cfg")
	for d in tracker.defs:
		_expect(not d.hero_play, "скрытый режим: видно достижение «%s»" % d.title)
	for sec in Reference.sections():
		_expect(sec.title != "Команды героя" and sec.title != "Задания героя", "скрытый режим: в справочнике раздел «%s»" % sec.title)
	Features.HERO_PLAY = true
	var with_hero := AchievementTracker.new("user://features_test_ach.cfg")
	_expect(with_hero.defs.size() > tracker.defs.size(), "включённый флаг: достижения режима не вернулись")
	Features.HERO_PLAY = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://features_test_ach.cfg"))
	print("флаги: режим героя скрыт и возвращается; сохранение с героем игрока — без управления")
	_finish()


func _finish() -> void:
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
