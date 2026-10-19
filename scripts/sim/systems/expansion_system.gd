class_name ExpansionSystem
extends RefCounted
## Мирная экспансия на ничьи соседние клетки.
##
## Государство копит «очки экспансии» (больше при высоком давлении населения
## и стабильности, растёт с периметром ~ √площади) и тратит их на клетки:
## стоимость клетки зависит от биома и расы (RaceDef.expansion_cost), так что
## дворфы легко занимают горы, а эльфы почти не выходят из лесов.

## Множитель скорости экспансии.
const RATE := 0.5
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]


func tick(world: World, nation: Nation) -> void:
	var n := nation.cells.size()
	if n == 0:
		return
	var race := nation.race
	var map := world.map
	var rng := world.rng
	var cap := nation.total_capacity()
	var pressure := clampf(nation.population / cap, 0.0, 1.2) if cap > 0.0 else 1.0
	var rate := RATE * sqrt(n) * race.expansion * (0.2 + pressure) * (0.4 + nation.stability * 0.6)
	nation.expansion_points = minf(nation.expansion_points + rate, rate * 3.0 + 4.0)

	var attempts := int(rate * 5.0) + 6
	while attempts > 0 and nation.expansion_points > 0.0:
		attempts -= 1
		var c := nation.cells[rng.randi_range(0, n - 1)]
		var d := DIRS[rng.randi_range(0, 7)]
		var x := c % map.width + d.x
		var y := c / map.width + d.y
		if not map.in_bounds(x, y):
			continue
		var nb := map.index_of(x, y)
		if world.owner[nb] != -1 or not map.is_land(nb):
			continue
		var cost := race.expansion_cost(map.biome[nb])
		if map.river[nb] > 0:
			cost *= 0.85
		if cost > nation.expansion_points:
			# Дорогая клетка: иногда копим на неё, иногда ищем дешевле.
			if rng.randf() < 0.3:
				break
			continue
		world.set_owner(nb, nation.id)
		nation.expansion_points -= cost
		n += 1
