extends Node
## Глобальное состояние мира (autoload «WorldState»).
##
## Хранит текущую карту и настройки. На следующих этапах здесь появятся
## государства, города и движок симуляции. Генерация идёт в фоновом потоке,
## чтобы интерфейс не зависал даже на огромных картах.

var map: WorldMap
var settings: MapSettings
var is_generating := false

var _task_id := -1
var _gen_started_ms := 0


func _ready() -> void:
	# Данные биомов грузим заранее в главном потоке: дальше их только читают.
	BiomeDB.ensure_loaded()
	EventBus.generate_requested.connect(generate)


## Запускает генерацию в фоне. Результат придёт сигналом EventBus.world_generated.
func generate(new_settings: MapSettings) -> void:
	if is_generating:
		return
	settings = new_settings.duplicate() as MapSettings
	is_generating = true
	_gen_started_ms = Time.get_ticks_msec()
	EventBus.generation_started.emit()
	_task_id = WorkerThreadPool.add_task(_generate_task.bind(settings), false, "World generation")


## Синхронная генерация (для тестов и инструментов).
func generate_now(new_settings: MapSettings) -> WorldMap:
	settings = new_settings.duplicate() as MapSettings
	map = MapGenerator.new().generate(settings)
	return map


func _generate_task(s: MapSettings) -> void:
	var result := MapGenerator.new().generate(s)
	_on_generation_finished.call_deferred(result)


func _on_generation_finished(result: WorldMap) -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	map = result
	is_generating = false
	EventBus.world_generated.emit(map, Time.get_ticks_msec() - _gen_started_ms)
