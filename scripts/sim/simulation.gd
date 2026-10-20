class_name Simulation
extends RefCounted
## Движок симуляции. Базовый шаг — день (step_day); месяц = 30 дней, год = 12 месяцев.
##
## Годовые дела каждого государства (экономика, рост, экспансия, города,
## правители, восстания, события, дипломатия) выполняются в «его» день года
## (месяц id % 12, день (id / 12) % 30): нагрузка размазана по году, а карта
## меняется плавно. Войны сражаются раз в год — в свой день; герои действуют
## раз в месяц — тоже каждый в свой день.
##
## Чистая логика без нод и отрисовки: работает с World и ничего не знает об
## интерфейсе. При profile = true копит время каждой системы (tests/profile_systems.gd).

const MONTHS := 12
const DAYS := 30

var economy := EconomySystem.new()
var population := PopulationSystem.new()
var expansion := ExpansionSystem.new()
var cities := CitySystem.new()
var rulers := RulerSystem.new()
var unrest := UnrestSystem.new()
var events := EventSystem.new()
var diplomacy := DiplomacySystem.new()
var wars := WarSystem.new()
var heroes := HeroSystem.new()
var enclaves := EnclaveSystem.new()
var religion := ReligionSystem.new()

var profile := false
## Имя системы → [суммарные мкс, худший вызов мкс].
var timings: Dictionary = {}


## Один год.
func step(world: World) -> void:
	for d in MONTHS * DAYS:
		step_day(world)


## Один месяц.
func step_month(world: World) -> void:
	for d in DAYS:
		step_day(world)


func step_day(world: World) -> void:
	world.day += 1
	if world.day >= DAYS:
		world.day = 0
		world.month += 1
		if world.month >= MONTHS:
			world.month = 0
			world.year += 1
			_t("new_year", _new_year.bind(world))
	# День года государства однозначно задаётся его id: id = месяц + 12·день + 360·k.
	var id := world.month + MONTHS * world.day
	while id < world.nations.size():
		var nation := world.nations[id]
		id += MONTHS * DAYS
		if not nation.alive:
			continue
		_t("economy", economy.tick.bind(world, nation))
		_t("population", population.tick.bind(world, nation))
		_t("expansion", expansion.tick.bind(world, nation))
		_t("cities", cities.tick.bind(world, nation))
		_t("rulers", rulers.tick.bind(world, nation))
		_t("unrest", unrest.tick.bind(world, nation))
		_t("events", events.tick.bind(world, nation))
		_t("religion", religion.tick.bind(world, nation))
		_t("diplomacy", diplomacy.tick_nation.bind(world, nation))
		_t("enclaves", enclaves.tick.bind(world, nation))
	_t("wars", wars.tick_day.bind(world))
	_t("heroes", heroes.tick_day.bind(world))
	world.cleanup_dead()


## Раз в год для всего мира: эпидемии от соседей, забывание обид, коалиции, статистика.
func _new_year(world: World) -> void:
	events.flush_pending(world)
	diplomacy.tick_year(world)
	religion.tick_year(world)
	_portals(world)
	world.record_history()


## Врата бездны каждый год выпускают легионы — пока демоны их удерживают.
func _portals(world: World) -> void:
	for lm in world.active_landmarks(&"portal"):
		var demons := world.nations[lm.hero_id] if lm.hero_id >= 0 and lm.hero_id < world.nations.size() else null
		var holder := world.owner[lm.cell]
		if demons != null and demons.alive and holder == demons.id:
			demons.army += 6000.0
		else:
			lm.active = false
			var region := world.region_at(lm.cell)
			var who := world.nations[holder].short_name if holder >= 0 else "свет"
			world.log_event(&"great", "Врата бездны в регионе %s закрыты — их запечатал %s." % [
				region.name if region != null else "?", who], PackedInt32Array([holder]) if holder >= 0 else PackedInt32Array())


func _t(system: String, call: Callable) -> void:
	if not profile:
		call.call()
		return
	var t0 := Time.get_ticks_usec()
	call.call()
	var dt := Time.get_ticks_usec() - t0
	var entry: Array = timings.get(system, [0, 0])
	entry[0] += dt
	entry[1] = maxi(entry[1], dt)
	timings[system] = entry
