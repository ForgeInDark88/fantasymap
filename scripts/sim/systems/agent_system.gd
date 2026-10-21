class_name AgentSystem
extends RefCounted
## Гонцы (этап 12.B): посольства и лазутчики идут по карте, а не «телепортируют»
## сделки и заговоры. Государство решает предложить сделку (DealSystem) или
## провести операцию (SpySystem) — из его столицы выходит гонец; дошёл до
## столицы адресата — переговоры (условия — на день прихода) или операция.
## Нет пути — поручение не выходит; в пути дольше MAX_DAYS или погиб кто-то из
## сторон — пропадает.

const MAX_DAYS := 360

var deals: DealSystem
var spies: SpySystem


## Отправить гонца из столицы from в столицу to. null — не выйти (нет столицы или пути).
static func send(world: World, kind: StringName, from: Nation, to: Nation, task: StringName) -> Agent:
	if from.capital_city < 0 or to.capital_city < 0:
		return null
	var a := Agent.new()
	a.id = world.agents.size()
	a.kind = kind
	a.from = from.id
	a.to = to.id
	a.task = task
	a.m = Mover.new(world.cities[from.capital_city].cell, &"envoy")
	a.m.nation = from.id
	a.born = ArmySystem.today(world)
	if not MovementSystem.send(world, a.m, world.cities[to.capital_city].cell):
		return null
	world.agents.append(a)
	world.count(&"envoys" if kind == &"envoy" else &"spies_sent")
	return a


func tick_day(world: World) -> void:
	if world.agents.is_empty():
		return
	var today := ArmySystem.today(world)
	var any_dead := false
	for a in world.agents:
		if not a.alive:
			any_dead = true
			continue
		var from := world.nations[a.from]
		var to := world.nations[a.to]
		if not from.alive or not to.alive or today - a.born > MAX_DAYS:
			a.alive = false
			any_dead = true
			continue
		# Столица адресата переехала — идти к новой.
		if to.capital_city >= 0 and not a.m.walking() and a.cell != world.cities[to.capital_city].cell:
			if not MovementSystem.send(world, a.m, world.cities[to.capital_city].cell):
				a.alive = false
				any_dead = true
			continue
		MovementSystem.advance(world, a.m)
		if a.m.arrived:
			a.alive = false
			any_dead = true
			_arrive(world, a, from, to)
	if any_dead:
		var keep: Array[Agent] = []
		for a in world.agents:
			if a.alive:
				a.id = keep.size()
				keep.append(a)
		world.agents = keep


## Гонец дошёл: посол предлагает сделку на сегодняшних условиях, лазутчик действует.
func _arrive(world: World, a: Agent, from: Nation, to: Nation) -> void:
	if a.kind == &"envoy":
		if deals == null:
			return
		var offer := deals._offer(world, a.task, from, to)
		if not offer.is_empty():
			DealSystem.propose(world, offer)
	elif a.kind == &"spy":
		var op: SpyOpDef = null
		for res in OrgDB.ops():
			if (res as SpyOpDef).id == a.task:
				op = res
		if op != null and (spies == null or spies._feasible(world, from, to, op)):
			SpySystem.run(world, from, to, op)
