class_name Simulation
extends RefCounted
## Движок симуляции. Базовый шаг — месяц (step_month); step() — целый год.
##
## Годовые дела каждого государства (экономика, рост, экспансия, города,
## правители, восстания, события, дипломатия) выполняются в «его» месяц
## (id % 12): нагрузка размазана по году, а карта меняется плавно. Войны
## тоже сражаются раз в год — в месяц своего начала. Герои живут помесячно.
##
## Чистая логика без нод и отрисовки: работает с World и ничего не знает об
## интерфейсе. Время тика не зависит от размера карты линейно — системы
## трогают только свои государства, их границы и города.

const MONTHS := 12

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


## Один год (12 месяцев).
func step(world: World) -> void:
	for m in MONTHS:
		step_month(world)


func step_month(world: World) -> void:
	world.month += 1
	if world.month >= MONTHS:
		world.month = 0
		world.year += 1
		_new_year(world)
	var count := world.nations.size()
	for k in count:
		var nation := world.nations[k]
		if not nation.alive or nation.id % MONTHS != world.month:
			continue
		economy.tick(world, nation)
		population.tick(world, nation)
		expansion.tick(world, nation)
		cities.tick(world, nation)
		rulers.tick(world, nation)
		unrest.tick(world, nation)
		events.tick(world, nation)
		diplomacy.tick_nation(world, nation)
		enclaves.tick(world, nation)
	wars.tick_month(world)
	heroes.tick_month(world)
	world.cleanup_dead()


## Раз в год для всего мира: эпидемии от соседей, забывание обид, коалиции, статистика.
func _new_year(world: World) -> void:
	events.flush_pending(world)
	diplomacy.tick_year(world)
	world.record_history()
