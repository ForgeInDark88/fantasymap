class_name Simulation
extends RefCounted
## Движок симуляции: один вызов step() = один год.
##
## Чистая логика без нод и отрисовки: работает с World и ничего не знает об
## интерфейсе. Каждая система отвечает за свой аспект; порядок вызова — порядок
## событий внутри года. Время одного тика не зависит от размера карты — системы
## трогают только свои государства, их границы и города.

var economy := EconomySystem.new()
var population := PopulationSystem.new()
var expansion := ExpansionSystem.new()
var cities := CitySystem.new()
var rulers := RulerSystem.new()
var unrest := UnrestSystem.new()
var events := EventSystem.new()
var diplomacy := DiplomacySystem.new()
var wars := WarSystem.new()


func step(world: World) -> void:
	world.year += 1
	var count := world.nations.size()
	if count == 0:
		return
	events.flush_pending(world)
	# Начинаем обход с разных государств, чтобы никто не получал «первый ход» всегда.
	# Восстания и распады добавляют государства по ходу — их очередь со следующего года.
	var offset := world.year % count
	for k in count:
		var nation := world.nations[(k + offset) % count]
		if not nation.alive:
			continue
		economy.tick(world, nation)
		population.tick(world, nation)
		expansion.tick(world, nation)
		cities.tick(world, nation)
		rulers.tick(world, nation)
		unrest.tick(world, nation)
		events.tick(world, nation)
	# Межгосударственное — после внутренних дел.
	diplomacy.tick(world)
	wars.tick(world)
	world.cleanup_dead()
