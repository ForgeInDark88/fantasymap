class_name Army
extends RefCounted
## Армия или флот на карте (ArmySystem). Армия — сосредоточенная сила
## государства в одной войне: её мощь — доля Nation.army (share), поэтому
## набор войск, потери и экономика войны остаются прежними, а армия лишь
## воплощает их на карте — собирается, идёт по регионам, сражается, осаждает,
## отступает. Флот — морская сила для десантов, блокад и морских боёв.
## Пираты — флот без государства (nation = -1). id = индекс в World.armies.

var id := -1
var nation := -1
var war := -1
## &"land", &"fleet", &"pirates".
var kind: StringName = &"land"
## Доля армии государства (для флота — доля морской силы).
var share := 1.0
## Мощь пиратов (у них нет государства).
var own_strength := 0.0
## Отряды мелких союзников, влитые в армию вождя стороны (их армии в поле не выходят).
var allied := 0.0
## Где армия: регион и клетка для показа; путь — регионы впереди; eta — дней до следующего шага.
var region := -1
var cell := -1
var path := PackedInt32Array()
var eta := 0
## &"muster" (сбор), &"march", &"siege", &"retreat", &"sail" (десант морем), &"idle".
var state: StringName = &"muster"
var state_until := 0
## Боевой дух и снабжение (0..1).
var morale := 0.7
var supply := 1.0
## Полководец: id в World.generals (-1 — нет).
var general := -1
var alive := true
var created_year := 0
var battles := 0
var wins := 0
## Куда идёт (регион цели) — для показа.
var target := -1


func strength(world: World) -> float:
	if kind == &"pirates":
		return own_strength
	if nation < 0 or nation >= world.nations.size() or not world.nations[nation].alive:
		return 0.0
	var n := world.nations[nation]
	if kind == &"fleet":
		return n.army * share * ArmySystem.FLEET_SHARE * n.effect(&"naval_mult")
	return n.power() * share + allied


## Боевая сила: мощь × дух × снабжение × полководец.
func fighting_power(world: World) -> float:
	var g := 1.0
	if general >= 0 and general < world.generals.size():
		g += float(world.generals[general].skill) * ArmySystem.GENERAL_POWER
	return strength(world) * (0.55 + 0.45 * morale) * (0.6 + 0.4 * supply) * g


func label(world: World) -> String:
	if kind == &"pirates":
		return "Пираты"
	var n := world.nations[nation]
	return ("Флот %s" if kind == &"fleet" else "Армия %s") % n.short_name
