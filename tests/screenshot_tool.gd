extends SceneTree
## Запускает главную сцену, ждёт генерации и сохраняет скриншоты всех режимов карты.
## Нужен реальный рендер (не --headless), например под Xvfb:
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tests/screenshot_tool.gd -- <out_dir>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var bus := root.get_node("/root/EventBus")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await bus.world_generated
	for i in 5:
		await process_frame
	for mode in 4:
		bus.map_mode_changed.emit(mode)
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png(out_dir.path_join("screen_mode%d.png" % mode))
	# Зум к точке и наведение курсора — проверка камеры и подсказки.
	bus.map_mode_changed.emit(0)
	var cam: Camera2D = main.get_node("MapCamera")
	cam.call("_zoom_at", 4.0, Vector2(800, 450))
	var renderer: Node = main.get_node("MapRenderer")
	bus.cell_hovered.emit(renderer.call("cell_at", cam.position))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join("screen_zoom.png"))
	# Повторная генерация через UI с другим размером — проверка полного цикла.
	var hud: Node = main.get_node("HUD")
	(hud.get_node("%SeedEdit") as LineEdit).text = "Арда"
	(hud.get_node("%SizeOption") as OptionButton).select(0)
	(hud.get_node("%RegenButton") as Button).pressed.emit()
	var map: RefCounted = (await bus.world_generated)[0]
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join("screen_regen.png"))
	print("regenerated %dx%d seed=%d" % [map.width, map.height, map.settings.world_seed])
	print("screenshots saved to ", out_dir)
	quit(0)
