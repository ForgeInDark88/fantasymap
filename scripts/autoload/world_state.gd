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
## Плавная скорость: отображаемый множитель разгоняется к SPEEDS[speed_index]
## за ~0,4 с (пауза — мягкое торможение). Логика дней от этого не меняется:
## симулируются те же дни, только их темп в реальном времени плавный.
const SPEED_K := 9.0
## Торможение быстрее разгона: после паузы мир почти сразу замирает.
const SPEED_K_DOWN := 22.0
var speed_now := 1.0
## Среднее время одного дня (мс) — для отладки и панели статистики.
var avg_tick_ms := 0.0
## Снимки истории и ветви (этап 11.F): авто — раз в Snapshots.AUTO_YEARS лет.
var snapshots := Snapshots.new()


func _ready() -> void:
	# Данные грузим заранее в главном потоке: дальше их только читают.
	BiomeDB.ensure_loaded()
	RaceDB.ensure_loaded()
	EconomyDB.ensure_loaded()
	PoliticsDB.ensure_loaded()
	ReligionDB.ensure_loaded()
	TechDB.ensure_loaded()
	OrgDB.ensure_loaded()
	CrisisDB.ensure_loaded()
	LoreDB.ensure_loaded()
	SmoothSettings.load_settings()
	Loc.init()
	EventBus.generate_requested.connect(generate)
	EventBus.year_passed.connect(func(_y: int) -> void:
		if world != null and not is_generating:
			snapshots.maybe_auto(world))


func _process(delta: float) -> void:
	var target := float(SPEEDS[speed_index])
	var k := SPEED_K if target > speed_now else SPEED_K_DOWN
	speed_now = SmoothSettings.damp(speed_now, target, k, delta) if SmoothSettings.ui_anim else target
	if absf(speed_now - target) < 0.02:
		speed_now = target
	if world == null or is_generating or speed_now <= 0.001:
		return
	# Герой игрока ждёт решения — мир стоит.
	if not world.player_choice.is_empty():
		return
	_day_accum += delta * speed_now * DAYS_PER_SECOND
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
	if world == null or is_generating or not world.player_choice.is_empty():
		return
	simulation.step(world)
	EventBus.year_passed.emit(world.year)


## Ровно один день (кнопка «+1 день»).
func step_day() -> void:
	if world == null or is_generating or not world.player_choice.is_empty():
		return
	simulation.step_day(world)
	EventBus.year_passed.emit(world.year)


## Ровно один месяц (кнопка «+1 мес.»).
func step_month() -> void:
	if world == null or is_generating or not world.player_choice.is_empty():
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


## Сохраняет текущий мир под именем name (user://saves/<name>.json).
func save_game(save_name: String) -> Error:
	if world == null or is_generating:
		return ERR_UNAVAILABLE
	return SaveSystem.save_world(world, SaveSystem.save_path(save_name))


## Загружает мир в фоне; результат — тот же сигнал EventBus.world_generated.
func load_game(save_name: String) -> bool:
	var path := SaveSystem.save_path(save_name)
	if is_generating or not FileAccess.file_exists(path):
		return false
	is_generating = true
	_gen_started_ms = Time.get_ticks_msec()
	EventBus.generation_started.emit()
	_task_id = WorkerThreadPool.add_task(_load_task.bind(path), false, "World loading")
	return true


func _load_task(path: String) -> void:
	_on_generation_finished.call_deferred(SaveSystem.load_world(path))


func _generate_task(s: MapSettings) -> void:
	var result := World.create(s)
	_on_generation_finished.call_deferred(result)


func _on_generation_finished(result: World) -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	is_generating = false
	if result == null:
		# Загрузка не удалась — остаёмся в прежнем мире.
		if world != null:
			EventBus.world_generated.emit(world, 0)
		return
	# Новый или загруженный мир — новая история: прежние снимки к ней не относятся.
	if result != world:
		snapshots = Snapshots.new()
	world = result
	settings = world.settings
	_day_accum = 0.0
	EventBus.world_generated.emit(world, Time.get_ticks_msec() - _gen_started_ms)


## Сделать снимок истории сейчас (окно «История мира»).
func take_snapshot() -> void:
	if world != null and not is_generating:
		snapshots.take(world)


## Вернуться к снимку: мир продолжится оттуда новой ветвью (прежние снимки остаются).
func restore_snapshot(index: int) -> bool:
	if is_generating:
		return false
	var w := snapshots.restore(index)
	if w == null:
		return false
	world = w
	settings = world.settings
	_day_accum = 0.0
	set_speed(0)
	EventBus.world_generated.emit(world, 0)
	return true
