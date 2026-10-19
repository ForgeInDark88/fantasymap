extends Node
## Глобальное состояние мира (autoload «WorldState»).
##
## Хранит текущий World и «часы» симуляции. Создание мира идёт в фоновом
## потоке; годы симулирует Simulation в главном потоке с бюджетом времени на кадр,
## поэтому интерфейс остаётся плавным на любой скорости.

## Множители скорости: пауза, x1, x2, x5, x10, x50.
const SPEEDS: Array[int] = [0, 1, 2, 5, 10, 50]
const SPEED_NAMES: Array[String] = ["Пауза", "x1", "x2", "x5", "x10", "x50"]
## Сколько дней проходит за секунду на скорости x1 (год — 360 дней ≈ 36 секунд).
const DAYS_PER_SECOND := 10.0
## Сколько времени кадра можно потратить на симуляцию (мкс).
const FRAME_BUDGET_USEC := 20000

var world: World
var settings: MapSettings
var simulation := Simulation.new()
var is_generating := false
var speed_index := 1
## Карта текущего мира (сокращение для world.map).
var map: WorldMap:
	get:
		return world.map if world != null else null

var _task_id := -1
var _gen_started_ms := 0
var _day_accum := 0.0
var _last_speed := 1
## Среднее время одного дня (мс) — для отладки и панели статистики.
var avg_tick_ms := 0.0


func _ready() -> void:
	# Данные грузим заранее в главном потоке: дальше их только читают.
	BiomeDB.ensure_loaded()
	RaceDB.ensure_loaded()
	EconomyDB.ensure_loaded()
	PoliticsDB.ensure_loaded()
	EventBus.generate_requested.connect(generate)


func _process(delta: float) -> void:
	if world == null or is_generating or speed_index == 0:
		return
	_day_accum += delta * SPEEDS[speed_index] * DAYS_PER_SECOND
	var start := Time.get_ticks_usec()
	var ticks := 0
	while _day_accum >= 1.0:
		var t0 := Time.get_ticks_usec()
		simulation.step_day(world)
		avg_tick_ms = lerpf(avg_tick_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.02)
		_day_accum -= 1.0
		ticks += 1
		if Time.get_ticks_usec() - start > FRAME_BUDGET_USEC:
			# Не успеваем — замедляемся, но не копим долг (иначе «снежный ком»).
			_day_accum = minf(_day_accum, 1.0)
			break
	if ticks > 0:
		EventBus.year_passed.emit(world.year)


func set_speed(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
	if speed_index > 0:
		_last_speed = speed_index
	EventBus.speed_changed.emit(speed_index)


func toggle_pause() -> void:
	set_speed(_last_speed if speed_index == 0 else 0)


## Ровно один год (кнопка «+1 год»).
func step_year() -> void:
	if world == null or is_generating:
		return
	simulation.step(world)
	EventBus.year_passed.emit(world.year)


## Ровно один день (кнопка «+1 день»).
func step_day() -> void:
	if world == null or is_generating:
		return
	simulation.step_day(world)
	EventBus.year_passed.emit(world.year)


## Ровно один месяц (кнопка «+1 мес.»).
func step_month() -> void:
	if world == null or is_generating:
		return
	simulation.step_month(world)
	EventBus.year_passed.emit(world.year)


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
	_day_accum = 0.0
	EventBus.world_generated.emit(world, Time.get_ticks_msec() - _gen_started_ms)
