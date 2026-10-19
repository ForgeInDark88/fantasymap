extends SceneTree
## Запускает главную сцену, ждёт создания мира и сохраняет скриншоты всех режимов карты.
## Нужен реальный рендер (не --headless), например под Xvfb:
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tests/screenshot_tool.gd -- <out_dir> [seed] [государств]

const MODE_COUNT := 6


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://"
	var bus := root.get_node("/root/EventBus")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await bus.world_generated
	var hud: Node = main.get_node("HUD")
	if args.size() > 1:
		# Пересоздаём мир с заданным seed (для воспроизводимых скриншотов).
		(hud.get_node("%SeedEdit") as LineEdit).text = args[1]
		if args.size() > 2:
			(hud.get_node("%NationsSpin") as SpinBox).value = int(args[2])
		(hud.get_node("%RegenButton") as Button).pressed.emit()
		await bus.world_generated
	await _frames(5)
	for mode in MODE_COUNT:
		bus.map_mode_changed.emit(mode)
		await _frames(2)
		_shot(out_dir, "screen_mode%d.png" % mode)

	# Выбор государства и приближение к его столице.
	bus.map_mode_changed.emit(0)
	var world: RefCounted = root.get_node("/root/WorldState").world
	var nation: RefCounted = world.nations[0]
	bus.nation_selected.emit(nation.id)
	var cam: Camera2D = main.get_node("MapCamera")
	var renderer: Node = main.get_node("MapRenderer")
	var capital: RefCounted = world.cities[nation.capital_city]
	cam.position = renderer.call("cell_center", capital.cell)
	cam.zoom = Vector2.ONE * 3.0
	bus.cell_hovered.emit(capital.cell)
	await _frames(3)
	_shot(out_dir, "screen_selected.png")
	cam.zoom = Vector2.ONE * 8.0
	await _frames(3)
	_shot(out_dir, "screen_closeup.png")

	# Симуляция: x10 до 200-го года, затем снимок карты и карточки крупнейшего государства.
	var ws: Node = root.get_node("/root/WorldState")
	bus.nation_selected.emit(-1)
	cam.call("fit_to", renderer.call("get_map_rect"))
	ws.call("set_speed", 4)
	while world.year < 200:
		await bus.year_passed
	ws.call("set_speed", 0)
	await _frames(3)
	_shot(out_dir, "screen_year200.png")
	var biggest: RefCounted = world.nations[0]
	for n in world.nations:
		if n.cell_count > biggest.cell_count:
			biggest = n
	bus.nation_selected.emit(biggest.id)
	await _frames(3)
	_shot(out_dir, "screen_year200_panel.png")
	print("year %d, avg tick %.2f ms" % [world.year, ws.get("avg_tick_ms")])

	# Повторная генерация через UI с другим размером — проверка полного цикла.
	bus.nation_selected.emit(-1)
	(hud.get_node("%SeedEdit") as LineEdit).text = "Арда"
	(hud.get_node("%SizeOption") as OptionButton).select(0)
	(hud.get_node("%RegenButton") as Button).pressed.emit()
	var regen: RefCounted = (await bus.world_generated)[0]
	await _frames(3)
	_shot(out_dir, "screen_regen.png")
	print("regenerated %dx%d, nations=%d" % [regen.map.width, regen.map.height, regen.nations.size()])
	print("screenshots saved to ", out_dir)
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(dir: String, file_name: String) -> void:
	root.get_texture().get_image().save_png(dir.path_join(file_name))
