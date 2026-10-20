class_name StageSystem
extends RefCounted
## Растянутые во времени удары (этап 11.A): чума, голод, саранча, чудовища,
## драконы, наводнения бьют не одним днём, а по месяцам — интенсивность по
## кривой «быстрый подъём, долгий спад». Итоговые потери те же, что у
## мгновенного удара: доли перемножаются, (1 − L) = Π (1 − l_i).
## Состояние — World.staged_effects: {nation, months, step, pop, army, stab, gold, food, id}.

## Доля длительности, за которую удар достигает пика.
const PEAK := 0.25


## Вес месяца i из n по кривой (сумма весов = 1).
static func weight(i: int, n: int) -> float:
	var total := 0.0
	var w_i := 0.0
	for k in n:
		var t := (k + 0.5) / n
		var w := t / PEAK if t < PEAK else (1.0 - t) / (1.0 - PEAK)
		total += w
		if k == i:
			w_i = w
	return w_i / total if total > 0.0 else 1.0 / n


static func push(world: World, nation: Nation, months: int, pop: float, army: float, stab: float, gold: float, food: float, id: StringName) -> void:
	world.staged_effects.append({"nation": nation.id, "months": months, "step": 0, "pop": pop, "army": army,
		"stab": stab, "gold": gold, "food": food, "id": String(id)})
	# Первый месяц — сразу (удар начинается в день события).
	tick_entry(world, world.staged_effects[world.staged_effects.size() - 1])


## Мгновенный удар (события «в один день»).
static func hit(world: World, nation: Nation, pop: float, army: float, stab: float, gold: float, food: float) -> void:
	if pop > 0.0:
		for r in nation.pop.size():
			nation.pop[r] *= 1.0 - pop
		for id in nation.city_ids:
			world.cities[id].population *= 1.0 - pop
	nation.army *= 1.0 - army
	nation.stability = clampf(nation.stability + stab, 0.0, 1.0)
	nation.stock[Goods.GOLD] -= maxf(0.0, nation.stock[Goods.GOLD]) * gold
	nation.stock[Goods.FOOD] *= 1.0 - food


## Доля мультипликативной потери за месяц с весом w: 1 − (1 − L)^w.
static func part(total: float, w: float) -> float:
	return 1.0 - pow(1.0 - clampf(total, 0.0, 0.999), w)


static func tick_entry(world: World, e: Dictionary) -> void:
	var nation := world.nations[int(e.nation)]
	var w := weight(int(e.step), int(e.months))
	e.step = int(e.step) + 1
	if not nation.alive:
		e.step = int(e.months)
		return
	hit(world, nation, part(float(e.pop), w), part(float(e.army), w), float(e.stab) * w, part(float(e.gold), w), part(float(e.food), w))


## Раз в месяц (первый день): следующий шаг каждого удара.
static func tick_month(world: World) -> void:
	if world.staged_effects.is_empty():
		return
	var i := 0
	while i < world.staged_effects.size():
		var e: Dictionary = world.staged_effects[i]
		if int(e.step) >= int(e.months):
			world.staged_effects.remove_at(i)
			continue
		tick_entry(world, e)
		i += 1
