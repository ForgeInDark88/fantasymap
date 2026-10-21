class_name RegionGenerator
extends RefCounted
## Нарезка суши на регионы.
##
## 1. Семена разбрасываются по суше с минимальным расстоянием (сетка-ускоритель).
## 2. Многоисточниковая «Дейкстра» с целыми стоимостями (алгоритм Дейла —
##    корзинная очередь, без кучи): горы, холмы, болота и пересечение рек дороги,
##    поэтому границы регионов ложатся по хребтам и рекам.
## 3. Острова без семян становятся отдельными регионами, мелкие обрезки
##    присоединяются к соседу.

## Средняя площадь региона на средней карте (384×240), в базовых клетках
## (при масштабе сетки — × scale²: регионы те же, клеток в них больше).
const BASE_REGION_SIZE := 90.0
const MAX_COST := 8192

var _world: World
var _map: WorldMap


func generate(world: World) -> Array[Region]:
	_world = world
	_map = world.map
	var n := _map.cell_count()
	var w := _map.width
	var rng := world.rng
	var gs := world.grid_scale
	var target := BASE_REGION_SIZE * float(w / gs) / 384.0 * (gs * gs)
	var spacing := sqrt(target) * 0.95

	var land := PackedInt32Array()
	for i in n:
		if _map.is_land(i):
			land.append(i)
	# Перемешиваем порядок обхода (Фишер–Йетс на RNG мира — детерминированно).
	for i in range(land.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := land[i]
		land[i] = land[j]
		land[j] = t

	# --- 1. Семена ---
	var grid := {}
	var seeds := PackedInt32Array()
	var g := maxf(spacing, 1.0)
	for cell in land:
		var p := Vector2(cell % w, cell / w)
		var gx := int(p.x / g)
		var gy := int(p.y / g)
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for other in grid.get(Vector2i(gx + dx, gy + dy), []):
					if p.distance_squared_to(other) < spacing * spacing:
						ok = false
						break
				if not ok:
					break
			if not ok:
				break
		if ok:
			var key := Vector2i(gx, gy)
			if not grid.has(key):
				grid[key] = []
			grid[key].append(p)
			seeds.append(cell)

	# --- 2. Рост по стоимости (алгоритм Дейла) ---
	var label := PackedInt32Array()
	label.resize(n)
	label.fill(-1)
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 30)
	var head := PackedInt32Array()
	head.resize(MAX_COST)
	head.fill(-1)
	var entry_cell := PackedInt32Array()
	var entry_next := PackedInt32Array()
	for r in seeds.size():
		var c := seeds[r]
		label[c] = r
		dist[c] = 0
		entry_cell.append(c)
		entry_next.append(head[0])
		head[0] = entry_cell.size() - 1
	var bucket := 0
	while bucket < MAX_COST:
		var e := head[bucket]
		if e == -1:
			bucket += 1
			continue
		head[bucket] = entry_next[e]
		var c := entry_cell[e]
		if dist[c] != bucket:
			continue  # устаревшая запись
		var cx := c % w
		for k in 4:
			var nb := -1
			match k:
				0: nb = c - 1 if cx > 0 else -1
				1: nb = c + 1 if cx < w - 1 else -1
				2: nb = c - w
				3: nb = c + w
			if nb < 0 or nb >= n or not _map.is_land(nb):
				continue
			var nd := mini(bucket + _step_cost(c, nb, rng), MAX_COST - 1)
			if nd < dist[nb]:
				dist[nb] = nd
				label[nb] = label[c]
				entry_cell.append(nb)
				entry_next.append(head[nd])
				head[nd] = entry_cell.size() - 1

	var count := seeds.size()
	# --- 3. Острова без семян: каждая связная область — свой регион ---
	for cell in land:
		if label[cell] != -1:
			continue
		var queue := PackedInt32Array([cell])
		label[cell] = count
		var qi := 0
		while qi < queue.size():
			var c := queue[qi]
			qi += 1
			for nb in _map.neighbors4(c):
				if label[nb] == -1 and _map.is_land(nb):
					label[nb] = count
					queue.append(nb)
		count += 1

	var regions := _build_regions(label, count)
	_merge_small(regions, label, target * 0.3)
	return _compact(regions, label)


## Регионы по готовой разметке world.region_of (при загрузке сохранения).
func rebuild(world: World, count: int) -> Array[Region]:
	_world = world
	_map = world.map
	var label := world.region_of.duplicate()
	var regions := _build_regions(label, count)
	# id регионов сохраняются как есть (даже пустые — ушедшие под воду), чтобы данные совпали.
	_finalize(regions, label)
	return regions


## Целая стоимость шага: рельеф + пересечение реки + немного шума для «живых» границ.
func _step_cost(from: int, to: int, rng: RandomNumberGenerator) -> int:
	var cost := 4
	match _map.biome[to]:
		Biome.MOUNTAINS, Biome.SNOW:
			cost = 14
		Biome.HILLS:
			cost = 7
		Biome.SWAMP, Biome.JUNGLE:
			cost = 6
	if (_map.river[to] > 0) != (_map.river[from] > 0):
		cost += 10  # вход в реку или выход из неё — реки становятся границами
	return cost + rng.randi_range(0, 2)


func _build_regions(label: PackedInt32Array, count: int) -> Array[Region]:
	var regions: Array[Region] = []
	for r in count:
		var region := Region.new()
		region.id = r
		regions.append(region)
	for i in label.size():
		if label[i] >= 0:
			regions[label[i]].cells.append(i)
	return regions


## Слишком мелкие регионы (кроме островов) вливаются в соседа с самой длинной общей границей.
func _merge_small(regions: Array[Region], label: PackedInt32Array, min_size: float) -> void:
	for region in regions:
		if region.cells.is_empty() or region.cells.size() >= min_size:
			continue
		var border := {}
		for c in region.cells:
			for nb in _map.neighbors4(c):
				var other := label[nb]
				if other >= 0 and other != region.id:
					border[other] = border.get(other, 0) + 1
		var best := -1
		var best_len := 0
		for other in border:
			if border[other] > best_len:
				best_len = border[other]
				best = other
		if best < 0:
			continue
		var target := regions[best]
		for c in region.cells:
			label[c] = best
			target.cells.append(c)
		region.cells.clear()


## Убирает пустые регионы, переназначает id, считает центры, соседей и побережье.
func _compact(regions: Array[Region], label: PackedInt32Array) -> Array[Region]:
	var result: Array[Region] = []
	var remap := PackedInt32Array()
	remap.resize(regions.size())
	remap.fill(-1)
	for region in regions:
		if region.cells.is_empty():
			continue
		remap[region.id] = result.size()
		region.id = result.size()
		result.append(region)
	for i in label.size():
		label[i] = remap[label[i]] if label[i] >= 0 else -1
	_finalize(result, label)
	return result


## Центры, соседи и побережье регионов; записывает разметку в мир.
func _finalize(result: Array[Region], label: PackedInt32Array) -> void:
	var w := _map.width
	for region in result:
		if region.cells.is_empty():
			continue
		# Порядок клеток — по индексу, как при пересборке из сохранения (детерминизм).
		region.cells.sort()
		var sx := 0.0
		var sy := 0.0
		var nbs := {}
		for c in region.cells:
			sx += c % w
			sy += c / w
			for nb in _map.neighbors4(c):
				var other := label[nb]
				if other >= 0 and other != region.id:
					nbs[other] = true
				elif other < 0 and (_map.biome[nb] == Biome.OCEAN or _map.biome[nb] == Biome.SEA):
					region.coastal = true
		var cx := sx / region.cells.size()
		var cy := sy / region.cells.size()
		var best_d := INF
		for c in region.cells:
			var d := Vector2(c % w - cx, c / w - cy).length_squared()
			if d < best_d:
				best_d = d
				region.center = c
		region.neighbors = PackedInt32Array(nbs.keys())
	_world.region_of = label
