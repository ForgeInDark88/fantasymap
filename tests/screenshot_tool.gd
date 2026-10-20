extends SceneTree
## Запускает главную сцену, прогоняет историю и сохраняет скриншоты режимов и панелей.
## Нужен реальный рендер (не --headless), например под Xvfb:
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tests/screenshot_tool.gd -- <out_dir> [seed] [государств] [лет]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://"
	var years := int(args[3]) if args.size() > 3 else 150
	var bus := root.get_node("/root/EventBus")
	var ws: Node = root.get_node("/root/WorldState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await bus.world_generated
	var hud: Node = main.get_node("HUD")
	if args.size() > 1:
		(hud.get_node("%SeedEdit") as LineEdit).text = args[1]
		if args.size() > 2:
			(hud.get_node("%NationsSpin") as SpinBox).value = int(args[2])
		(hud.get_node("%RegenButton") as Button).pressed.emit()
		await bus.world_generated
	var cam: Camera2D = main.get_node("MapCamera")
	var renderer: Node = main.get_node("MapRenderer")
	var world: RefCounted = ws.world
	# Прогон истории на максимальной скорости.
	_panel(hud, "Мир", false)
	ws.call("set_speed", 5)
	while world.year < years:
		await bus.year_passed
	ws.call("set_speed", 0)
	await _frames(3)
	for mode in MapMode.NAMES.size():
		bus.map_mode_changed.emit(mode)
		await _frames(2)
		_shot(out_dir, "mode%d.png" % mode)
	bus.map_mode_changed.emit(0)

	var biggest: RefCounted = world.nations[0]
	for n in world.nations:
		if n.alive and n.cell_count > biggest.cell_count:
			biggest = n
	var cap_cell: int = world.cities[biggest.capital_city].cell
	bus.cell_clicked.emit(cap_cell)
	bus.nation_selected.emit(biggest.id)
	await _frames(3)
	_shot(out_dir, "nation_card.png")

	for p in ["Летопись", "Статистика", "Герои", "Бог"]:
		_panel(hud, p, true)
		await _frames(30)  # панели обновляются по таймеру
		_shot(out_dir, "panel_%s.png" % p)
	if world.heroes.size() > 0:
		_panel(hud, "Герои", true)
		bus.hero_selected.emit(world.heroes[world.heroes.size() - 1].id)
		await _frames(30)
		_shot(out_dir, "panel_Герои_card.png")
	# Инструменты Бога тем же путём, что и клик мышью: поднять остров в океане и основать там государство.
	var sea := -1
	for i in world.map.cell_count():
		if world.map.biome[i] == Biome.OCEAN and world.map.cell_pos(i).x > world.map.width / 2 and world.map.cell_pos(i).y > 20:
			sea = i
			break
	bus.god_tool_changed.emit(&"raise", {"radius": 5})
	for k in 5:
		main.call("_on_map_clicked", renderer.call("cell_center", sea))
	bus.god_tool_changed.emit(&"create_nation", {"race": RaceDB.get_race(&"dwarves")})
	main.call("_on_map_clicked", renderer.call("cell_center", sea))
	bus.god_tool_changed.emit(&"", {})
	cam.position = renderer.call("cell_center", sea)
	cam.zoom = Vector2.ONE * 2.0
	await _frames(4)
	_shot(out_dir, "god_island.png")
	_panel(hud, "Бог", false)
	bus.nation_selected.emit(-1)

	# Великие деяния и Судьба: источник силы, портал, проклятый герой с троном.
	var sample_nation: RefCounted = biggest
	var sample_region: RefCounted = world.region_at(sample_nation.cells[0])
	var h: RefCounted = HeroSystem.spawn(world, sample_nation, sample_region, true)
	HeroSystem.power_source(world, h, sample_nation.cells[sample_nation.cells.size() / 3])
	var fallen: RefCounted = HeroSystem.spawn(world, sample_nation, sample_region, true)
	fallen.level = 9
	fallen.add_deed(world, "сразил дракона в регионе " + sample_region.name)
	fallen.die(world)
	var cursed: RefCounted = HeroSystem.spawn(world, sample_nation, sample_region, true)
	cursed.die(world)
	Fate.curse(world, cursed)
	for n in world.nations:
		if n.alive and n != sample_nation and n.cell_count > 80:
			HeroSystem.open_portal(world, n.cells[n.cells.size() / 2], null)
			break
	bus.year_passed.emit(world.year)
	var fate_panel: Control = hud.get("_fate_panel")
	fate_panel.call("open_panel")
	await _frames(4)
	_shot(out_dir, "fate.png")
	fate_panel.call("close_panel")
	ws.call("set_speed", 0)
	bus.map_mode_changed.emit(0)
	cam.call("fit_to", renderer.call("get_map_rect"))
	await _frames(4)
	_shot(out_dir, "landmarks.png")

	# Крупный план у столицы: регионы, города, герои.
	cam.position = renderer.call("cell_center", cap_cell)
	cam.zoom = Vector2.ONE * 2.4
	await _frames(4)
	_shot(out_dir, "closeup.png")
	print("year %d, nations alive %d, heroes %d, avg month %.2f ms" % [
		world.year, world.nations.filter(func(n: RefCounted) -> bool: return n.alive).size(),
		world.heroes.size(), ws.get("avg_tick_ms")])

	# Окно подземного мира.
	bus.underworld_window_requested.emit()
	await _frames(6)
	_shot(out_dir, "underworld.png")
	for c in hud.get_node("Root").get_children():
		if c.has_method("refresh") and c.get("_map_view") != null:
			c.visible = false

	# Окно технологий крупнейшего государства и новые графики статистики.
	bus.tech_window_requested.emit(biggest.id)
	await _frames(6)
	_shot(out_dir, "tech_window.png")
	for c in hud.get_node("Root").get_children():
		if c.has_method("refresh") and c.get("_columns") != null:
			c.visible = false
	_panel(hud, "Статистика", true)
	for view in [3, 4]:
		for c in hud.get_node("Root").get_children():
			if c.get("_chart") != null:
				c.set("_view", view)
				c.call("_refresh")
		await _frames(4)
		_shot(out_dir, "stats_view%d.png" % view)
	_panel(hud, "Статистика", false)

	# Окно героя: самый прославленный из живых.
	var star: RefCounted = null
	for cand in world.heroes:
		if cand.alive and not cand.is_ruler and (star == null or cand.level > star.level):
			star = cand
	if star != null:
		bus.hero_window_requested.emit(star.id)
		await _frames(6)
		_shot(out_dir, "hero_window.png")
		bus.hero_window_requested.emit(-1)
		for c in hud.get_node("Root").get_children():
			if c.has_method("close_window"):
				c.close_window()
		# Сыграй за героя: панель «Мой герой», путь и окно выбора.
		PlayerSystem.take_control(world, star.id)
		var far := -1
		for r in world.regions:
			var plan := PlayerSystem.plan_path(world, world.region_of[star.cell], r.id)
			if not plan.is_empty() and int(plan.months) >= 3:
				far = r.id
				break
		if far >= 0:
			PlayerSystem.command(world, &"travel", far)
		ws.call("step_month")
		star.gold = 120.0
		star.wounds = 0.35
		star.perk_points = 1
		PlayerQuests.open_board(world, star)
		if not world.player_offers.is_empty():
			PlayerSystem.choose(world, 0)
		world.player_choice = {}
		_panel(hud, "Мой герой", true)
		await _frames(6)
		_shot(out_dir, "my_hero.png")
		PlayerSystem.start_event(world, star)
		await _frames(6)
		_shot(out_dir, "hero_choice.png")
		PlayerSystem.choose(world, 0)
		PlayerSystem.release(world)
		_panel(hud, "Мой герой", false)

	# Хроники: ключевые события и история войны.
	bus.chronicles_window_requested.emit()
	await _frames(4)
	_shot(out_dir, "chronicles.png")
	for c in hud.get_node("Root").get_children():
		if c.get("_stories") != null:
			var list: ItemList = c.get("_list")
			for i in list.item_count:
				if list.get_item_text(i).begins_with("Войны"):
					list.select(i)
					c.call("_on_item", i)
					break
			await _frames(4)
			_shot(out_dir, "chronicles_war.png")
			c.visible = false

	# Достижения: окно и уведомление.
	bus.achievement_unlocked.emit(load("res://data/achievements/portal_closed.tres"))
	bus.achievements_window_requested.emit()
	await _frames(4)
	_shot(out_dir, "achievements.png")
	bus.achievements_window_requested.emit()
	for c in hud.get_node("Root").get_children():
		if c.get("_toasts") != null:
			(c.get("_window") as Control).visible = false

	# Сохранение и загрузка через интерфейс.
	cam.call("fit_to", renderer.call("get_map_rect"))
	ws.call("save_game", "Скриншот")
	_panel(hud, "Сохранения", true)
	await _frames(4)
	_shot(out_dir, "saves.png")
	ws.call("load_game", "Скриншот")
	await bus.world_generated
	await _frames(4)
	_shot(out_dir, "loaded.png")
	print("loaded: year %d" % ws.world.year)
	print("screenshots saved to ", out_dir)
	quit(0)


func _panel(hud: Node, panel_name: String, on: bool) -> void:
	var entry: Array = hud.get("_left_panels")[panel_name]
	(entry[0] as Button).button_pressed = on


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(dir: String, file_name: String) -> void:
	root.get_texture().get_image().save_png(dir.path_join(file_name))
