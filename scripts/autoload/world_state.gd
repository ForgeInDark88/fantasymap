extends Node
## Глобальное состояние мира (autoload «WorldState»).
##
## Хранит текущий World (карта + государства + города) и настройки.
## Создание мира идёт в фоновом потоке, чтобы интерфейс не зависал даже
## на огромных картах. На этапе 3 здесь появится движок тиков симуляции.

var world: World
var settings: MapSettings
var is_generating := false
## Карта текущего мира (сокращение для world.map).
var map: WorldMap:
	get:
		return world.map if world != null else null

var _task_id := -1
var _gen_started_ms := 0


func _ready() -> void:
	# Данные грузим заранее в главном потоке: дальше их только читают.
	BiomeDB.ensure_loaded()
	RaceDB.ensure_loaded()
	EventBus.generate_requested.connect(generate)


## Запускает создание мира в фоне. Результат придёт сигналом EventBus.world_generated.
func generate(new_settings: MapSettings) -> void:
	if is_generating:
		return
	settings = new_settings.duplicate() as MapSettings
	is_generating = true
	_gen_started_ms = Time.get_ticks_msec()
	EventBus.generation_started.emit()
	_task_id = WorkerThreadPool.add_task(_generate_task.bind(settings), false, "World generation")


func _generate_task(s: MapSettings) -> void:
	var result := World.create(s)
	_on_generation_finished.call_deferred(result)


func _on_generation_finished(result: World) -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	world = result
	is_generating = false
	EventBus.world_generated.emit(world, Time.get_ticks_msec() - _gen_started_ms)
