extends SceneTree
## Headless-проверка этапа 10.3: летописец собирает истории всех видов по
## шаблонам data/chronicle_templates (без незаполненных подстановок), тексты
## стабильны и не трогают ГСЧ мира, фильтры и поиск, значимость и ключевые
## события, закладки (и их сохранение), экспорт в Markdown.
##   godot --headless --path . -s res://tests/chronicles_test.gd -- [годы]

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 250
	var s := MapSettings.new()
	s.world_seed = 1337
	s.apply_size_preset(1)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in years:
		sim.step(world)
	var rng_state := world.rng.state
	var t0 := Time.get_ticks_msec()
	var list := Chronicler.stories(world)
	var list_ms := Time.get_ticks_msec() - t0
	var topics := {}
	for st in list:
		topics[st.topic] = topics.get(st.topic, 0) + 1
	print("историй %d за %d мс: %s" % [list.size(), list_ms, topics])
	for topic in [&"era", &"war", &"hero", &"nation", &"religion"]:
		_expect(topics.get(topic, 0) > 0, "нет историй вида %s" % topic)
	t0 = Time.get_ticks_msec()
	var longest := ""
	for st in list:
		var text := Chronicler.text(world, st)
		_expect(not text.is_empty(), "пустая история %s" % st.id)
		_expect(not text.contains("{") and not text.contains("[") and not st.title.contains("{"), "незаполненная подстановка в %s: %s" % [st.id, text.left(200)])
		_expect(Chronicler.text(world, st) == text, "текст %s нестабилен" % st.id)
		if text.length() > longest.length() and st.topic == &"war":
			longest = text
	print("тексты за %d мс; пример:\n%s\n" % [Time.get_ticks_msec() - t0, longest.left(900)])
	_expect(world.rng.state == rng_state, "летописец тронул ГСЧ мира")
	# Фильтры.
	var n0: int = list.filter(func(st: Dictionary) -> bool: return st.topic == &"war")[0].nations[0]
	var by_nation := list.filter(func(st: Dictionary) -> bool: return Chronicler.matches(world, st, {"nation": n0}))
	_expect(not by_nation.is_empty() and by_nation.all(func(st: Dictionary) -> bool: return (st.nations as PackedInt32Array).has(n0)), "фильтр по державе")
	var only_wars := list.filter(func(st: Dictionary) -> bool: return Chronicler.matches(world, st, {"topic": &"war"}))
	_expect(only_wars.size() == topics[&"war"], "фильтр по виду")
	var era_f := list.filter(func(st: Dictionary) -> bool: return Chronicler.matches(world, st, {"era": 0}))
	_expect(not era_f.is_empty() and era_f.size() < list.size(), "фильтр по эпохе")
	var race := world.nations[n0].race_id
	_expect(list.any(func(st: Dictionary) -> bool: return Chronicler.matches(world, st, {"race": race})), "фильтр по расе")
	var q: String = world.nations[n0].name
	_expect(list.any(func(st: Dictionary) -> bool: return Chronicler.matches(world, st, {"text": q})), "поиск")
	_expect(not list.any(func(st: Dictionary) -> bool: return Chronicler.matches(world, st, {"text": "ыыыщщщ"})), "поиск находит несуществующее")
	# Значимость и закладки.
	var keys := Chronicler.key_events(world)
	_expect(not keys.is_empty() and keys.all(func(e: Dictionary) -> bool: return Chronicler.significance(e) >= Chronicler.KEY_EVENT), "ключевые события")
	_expect(Chronicler.toggle_bookmark(world, keys[0]) and Chronicler.is_bookmarked(world, keys[0]), "закладка не поставилась")
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded.bookmarks.size() == 1 and Chronicler.is_bookmarked(loaded, keys[0]), "закладки не сохранились")
	_expect(not Chronicler.toggle_bookmark(world, keys[0]) and world.bookmarks.is_empty(), "закладка не снялась")
	# Экспорт.
	var war: Dictionary = list.filter(func(st: Dictionary) -> bool: return st.topic == &"war")[0]
	var path := Chronicler.export_markdown(world, war)
	_expect(not path.is_empty() and FileAccess.file_exists(path), "экспорт не записан")
	var md := FileAccess.get_file_as_string(path)
	_expect(md.begins_with("# ") and md.contains("## Упомянутые") and md.contains("](#nation-"), "в Markdown нет заголовка или ссылок")
	DirAccess.remove_absolute(path)
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
