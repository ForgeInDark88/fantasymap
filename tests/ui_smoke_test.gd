extends SceneTree
## Дым-проверка интерфейса без экрана: главная сцена загружается (все скрипты
## интерфейса разбираются), мир создаётся, проходит год, открываются окна
## (Хроники, Рынок, Дипломатия, Достижения, карточки), режимы карты и F5/F9.
## Ошибки скриптов видны в выводе как SCRIPT ERROR (CI их ловит).
##   godot --headless --path . -s res://tests/ui_smoke_test.gd

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var bus := root.get_node("/root/EventBus")
	var ws: Node = root.get_node("/root/WorldState")
	var scene: PackedScene = load("res://scenes/main.tscn")
	_expect(scene != null, "главная сцена не загрузилась")
	if scene == null:
		_finish()
		return
	var main: Node = scene.instantiate()
	root.add_child(main)
	await bus.world_generated
	var world: RefCounted = ws.world
	_expect(world != null, "мир не создан")
	ws.call("step_month")
	for m in 12:
		ws.call("step_month")
	await _frames(3)
	for mode in MapMode.NAMES.size():
		bus.map_mode_changed.emit(mode)
		await _frames(2)
	bus.map_mode_changed.emit(0)
	bus.chronicles_window_requested.emit()
	await _frames(3)
	bus.market_window_requested.emit(-1)
	await _frames(3)
	bus.diplomacy_window_requested.emit(-1)
	await _frames(3)
	bus.achievements_window_requested.emit()
	await _frames(3)
	var lairs: Array = world.get("lairs")
	if not lairs.is_empty():
		bus.wild_selected.emit(lairs[0])
		await _frames(3)
	var armies: Array = world.get("armies")
	if not armies.is_empty():
		bus.army_selected.emit(armies[0])
		await _frames(3)
	bus.nation_selected.emit(0)
	await _frames(5)
	# Интерфейс действительно собран (скрипт HUD разобран, а не пуст).
	var hud: Node = main.get_node("HUD")
	_expect(hud.get_script() != null and hud.has_method("_on_menu"), "скрипт интерфейса не загрузился")
	# Режим «Сыграй за героя» скрыт (Features.HERO_PLAY): в дереве нет его узлов.
	for n in _all_nodes(main):
		var path: String = n.get_script().resource_path if n.get_script() != null else ""
		var text: String = (n as Button).text if n is Button else ""
		_expect(not path.ends_with("my_hero_panel.gd") and text != "Мой герой" and text != "Играть за героя"
				and not text.begins_with("Создать своего героя"), "узел скрытого режима героя: %s «%s»" % [n.name, text])
	# Меню «☰»: справочник, история, уведомления, миникарта, обучение (экспорт — в usability_test).
	if hud.has_method("_on_menu"):
		var dummy := PopupMenu.new()
		for id in [0, 1, 2, 6, 6, 7]:
			hud.call("_on_menu", id, dummy)
			await _frames(3)
		dummy.free()
	bus.toast_requested.emit("проверка")
	await _frames(3)
	# F5 — быстрое сохранение, F9 — его загрузка: мир возвращается в ту же дату
	# (на паузе, чтобы часы не шли между проверками).
	ws.call("set_speed", 0)
	var date: String = ws.world.call("date_text")
	var nations: int = ws.world.get("nations").size()
	hud.call("_unhandled_input", _key(KEY_F5))
	_expect(FileAccess.file_exists(SaveSystem.save_path("быстрое")), "F5 не создал быстрое сохранение")
	ws.call("step_month")
	hud.call("_unhandled_input", _key(KEY_F9))
	await bus.world_generated
	await _frames(3)
	_expect(ws.world.call("date_text") == date and ws.world.get("nations").size() == nations, "F9 не вернул мир к быстрому сохранению")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.save_path("быстрое")))
	print("интерфейс: сцена, %d режимов карты, окна и карточки — без падений" % MapMode.NAMES.size())
	_finish()


func _all_nodes(n: Node) -> Array[Node]:
	var res: Array[Node] = [n]
	for c in n.get_children():
		res.append_array(_all_nodes(c))
	return res


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


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
