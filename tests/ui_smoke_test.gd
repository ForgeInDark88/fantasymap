extends SceneTree
## Дым-проверка интерфейса без экрана: главная сцена загружается (все скрипты
## интерфейса разбираются), мир создаётся, проходит год, открываются окна
## (Хроники, Рынок, Дипломатия, Достижения, карточки) и режимы карты.
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
	for mode in 15:
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
	# Меню «☰»: справочник, история, уведомления, миникарта, обучение (экспорт — в usability_test).
	if hud.has_method("_on_menu"):
		var dummy := PopupMenu.new()
		for id in [0, 1, 2, 6, 6, 7]:
			hud.call("_on_menu", id, dummy)
			await _frames(3)
		dummy.free()
	bus.toast_requested.emit("проверка")
	await _frames(3)
	print("интерфейс: сцена, %d режимов карты, окна и карточки — без падений" % 15)
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
