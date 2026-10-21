class_name Pathfinder
extends RefCounted
## Поиск пути по клеткам (этап 12.B), иерархический:
##   1. маршрут по графу регионов («Дейкстра», вес — расстояние между центрами
##      по рельефу профиля движения);
##   2. уточнение по клеткам в «коридоре» маршрута: отрезок от клетки до
##      перехода в следующий регион — прямая линия, если она проходит по суше
##      своего региона, иначе A* внутри региона (бюджет по узлам). Отрезки
##      между переходами кэшируются (по паре регионов) — общий путь многих юнитов
##      считается один раз;
##   3. другая суша — через порт: путь до гавани, морем (A* по воде с весом
##      эвристики) к берегу цели, оттуда — пешком.
## Результат зависит только от карты (рельеф, регионы, гавани) — не от кэша и
## не от ГСЧ, поэтому загруженный мир ходит так же. Пути — без стартовой клетки,
## с конечной; пусто — не дойти.

const DIAG := 1.41421356
## Сколько отрезков, маршрутов регионов и морских путей держать в кэше.
const CACHE_MAX := 8000
## Бюджет A* по воде (узлов на базовую клетку² — × scale²) и внутри региона.
const WATER_BUDGET := 40000
const REGION_BUDGET := 6000
## Бюджет запасных поисков без ограничения регионом и по морю «напрямую» (неудача
## стоит не больше нескольких миллисекунд — юнит просто не идёт).
const FALLBACK_BUDGET := 1200
## Вес эвристики морского A* (быстрее, путь чуть длиннее кратчайшего).
const WATER_W := 1.6
## Вес эвристики грубого поиска по блокам моря (почти жадный: путь чуть длиннее, зато
## дальние плавания вокруг материков не обходят весь океан).
const COARSE_W := 3.0

static var _key := Vector3i(-1, -1, -1)
## Переходы между регионами: Vector2i(a, b) → Vector2i(клетка в a, соседняя клетка в b).
static var _portal: Dictionary = {}
## Отрезки внутри региона: Vector4i(от, до, регион, профиль) → путь (стоимость A*
## зависит от профиля — ключ без него сделал бы путь зависимым от истории кэша).
static var _seg: Dictionary = {}
## Маршруты по регионам: "от:до:профиль" → PackedInt32Array регионов.
static var _routes: Dictionary = {}
static var _sea: Dictionary = {}
## Связные «материки» регионов (id компоненты на регион).
static var _land := PackedInt32Array()
## Грубая сетка моря для морских путей: блок WATER_BLOCK × WATER_BLOCK базовых
## клеток проходим, если в нём заметная доля моря; компоненты связности блоков.
const WATER_BLOCK := 8
## Предел узлов грубого поиска по блокам (дальше — «не доплыть»).
const COARSE_BUDGET := 1500
static var _wb := 4
static var _ww := 0
static var _wh := 0
static var _wpass := PackedByteArray()
static var _wcomp := PackedInt32Array()
## Рабочие массивы A* (по клеткам карты, с метками вместо очистки).
static var _g := PackedFloat32Array()
static var _from := PackedInt32Array()
static var _seen := PackedInt32Array()
static var _done := PackedInt32Array()
static var _mark := 0
static var _heap := MinHeap.new()
## Сколько раз запускался A* (для профилирования и тестов).
static var searches := 0
## Профилирование (tests/profile_systems.gd): худшее время вызова по видам, мкс.
static var profile := false
static var worst: Dictionary = {}


static func _note(kind: String, t0: int) -> void:
	var dt := Time.get_ticks_usec() - t0
	if dt > int(worst.get(kind, 0)):
		worst[kind] = dt


static func _ensure(world: World) -> void:
	var key := Vector3i(_wid(world), world.terrain_version, world.map.cell_count())
	if key == _key:
		return
	# Рельеф сменился — все пути (их стоимость) пересчитываются заново: кэш не должен
	# помнить старый рельеф, иначе загруженный мир (с пустым кэшем) пошёл бы иначе.
	_key = key
	_portal.clear()
	_seg.clear()
	_routes.clear()
	_sea.clear()
	var n := world.map.cell_count()
	if _g.size() != n:
		_g.resize(n)
		_from.resize(n)
		_seen.resize(n)
		_done.resize(n)
		_seen.fill(0)
		_done.fill(0)
		_mark = 0
	# Материки: компоненты графа регионов.
	_land.resize(world.regions.size())
	_land.fill(-1)
	var comp := 0
	for r in world.regions.size():
		if _land[r] >= 0 or world.regions[r].cells.is_empty():
			continue
		var stack := PackedInt32Array([r])
		_land[r] = comp
		while not stack.is_empty():
			var cur := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			for nb in world.regions[cur].neighbors:
				if _land[nb] < 0 and not world.regions[nb].cells.is_empty():
					_land[nb] = comp
					stack.append(nb)
		comp += 1


## Грубая сетка моря — лениво и только когда суша и вода поменялись местами.
static var _water_key := Vector3i(-1, -1, -1)


static func _ensure_water(world: World) -> void:
	var key := Vector3i(_wid(world), world.coast_version, world.map.cell_count())
	if key == _water_key:
		return
	var t0 := Time.get_ticks_usec() if profile else 0
	# Тот же мир, лишь несколько клеток сменили сушу на воду — пересчёт их блоков.
	if key.x == _water_key.x and key.z == _water_key.z and not world.coast_cells.is_empty() and world.coast_cells.size() < 4096:
		_water_key = key
		_patch_water(world)
	else:
		_water_key = key
		_build_water(world)
	world.coast_cells = PackedInt32Array()
	if profile:
		_note("water_grid", t0)


## Пересчёт блоков, где суша и вода поменялись; компоненты — если проходимость блока сменилась.
static func _patch_water(world: World) -> void:
	var map := world.map
	var blocks := {}
	for c in world.coast_cells:
		blocks[_block(map, c)] = true
	var flipped := false
	var need := maxi(1, _wb * _wb / 4)
	for b in blocks:
		var x0: int = (b % _ww) * _wb
		var y0: int = (b / _ww) * _wb
		var count := 0
		for y in range(y0, mini(y0 + _wb, map.height)):
			for x in range(x0, mini(x0 + _wb, map.width)):
				if _sea_cell(map, y * map.width + x):
					count += 1
		var p := 1 if count >= need else 0
		if p != _wpass[b]:
			_wpass[b] = p
			flipped = true
	if flipped:
		_label_water()


static func _build_water(world: World) -> void:
	var map := world.map
	_wb = WATER_BLOCK * world.grid_scale
	_ww = ceili(float(map.width) / _wb)
	_wh = ceili(float(map.height) / _wb)
	var counts := PackedInt32Array()
	counts.resize(_ww * _wh)
	var biome := map.biome
	var w := map.width
	for y in map.height:
		var row := (y / _wb) * _ww
		var base := y * w
		for x in w:
			var b := biome[base + x]
			if b == Biome.OCEAN or b == Biome.SEA:
				counts[row + x / _wb] += 1
	_wpass.resize(_ww * _wh)
	var need := maxi(1, _wb * _wb / 4)
	for i in counts.size():
		_wpass[i] = 1 if counts[i] >= need else 0
	_label_water()


## Компоненты связности проходимых блоков моря (4-связность: дёшево; блоки,
## связанные лишь углом, — разные компоненты, путь между ними ищет запасной A*).
static func _label_water() -> void:
	var n := _ww * _wh
	_wcomp.resize(n)
	_wcomp.fill(-1)
	var comp := 0
	var queue := PackedInt32Array()
	queue.resize(n)
	for start in n:
		if _wpass[start] == 0 or _wcomp[start] >= 0:
			continue
		var head := 0
		var tail := 1
		queue[0] = start
		_wcomp[start] = comp
		while head < tail:
			var b := queue[head]
			head += 1
			var bx := b % _ww
			if bx > 0 and _wpass[b - 1] == 1 and _wcomp[b - 1] < 0:
				_wcomp[b - 1] = comp
				queue[tail] = b - 1
				tail += 1
			if bx < _ww - 1 and _wpass[b + 1] == 1 and _wcomp[b + 1] < 0:
				_wcomp[b + 1] = comp
				queue[tail] = b + 1
				tail += 1
			if b >= _ww and _wpass[b - _ww] == 1 and _wcomp[b - _ww] < 0:
				_wcomp[b - _ww] = comp
				queue[tail] = b - _ww
				tail += 1
			if b + _ww < n and _wpass[b + _ww] == 1 and _wcomp[b + _ww] < 0:
				_wcomp[b + _ww] = comp
				queue[tail] = b + _ww
				tail += 1
		comp += 1


static var _prof_ids: Dictionary = {}


static func _prof_index(prof: MoveProfileDef) -> int:
	if not _prof_ids.has(prof.id):
		_prof_ids[prof.id] = _prof_ids.size()
	return _prof_ids[prof.id]


static func _cap(d: Dictionary) -> void:
	if d.size() > CACHE_MAX:
		d.clear()


## Подготовить кэши мира заранее (при создании и загрузке — в фоновом потоке),
## чтобы первый морской путь не стоил кадра.
static func prepare(world: World) -> void:
	_ensure(world)
	_ensure_water(world)


## Материк клетки (-1 — вода).
static func landmass(world: World, cell: int) -> int:
	_ensure(world)
	var r := world.region_of[cell]
	return _land[r] if r >= 0 and r < _land.size() else -1


# ---------------------------------------------------------------------------
# Общий путь
# ---------------------------------------------------------------------------

## Путь из from в to для профиля prof (суша, а если нужно и можно — морем через порт).
## ports — чьими гаванями можно пользоваться (id государств; пусто — любыми).
static func route(world: World, from: int, to: int, prof: MoveProfileDef, ports: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	if from < 0 or to < 0 or from == to:
		return PackedInt32Array()
	_ensure(world)
	var map := world.map
	if prof.water_only:
		return water_path(world, from, to)
	if not map.is_land(from):
		# Юнит на воде (плывёт): к ближайшему берегу цели морем, дальше пешком.
		var landing := landing_cell(world, to)
		if landing < 0:
			return PackedInt32Array()
		var w2 := water_next_to(world, landing)
		var sea := water_path(world, from, w2) if w2 != from else PackedInt32Array()
		if sea.is_empty() and w2 != from:
			return PackedInt32Array()
		var out := sea
		out.append(landing)
		out.append_array(land_path(world, landing, to, prof))
		return out
	var p := land_path(world, from, to, prof)
	if not p.is_empty() or not prof.can_sail or not map.is_land(to):
		return p
	if landmass(world, from) == landmass(world, to):
		return p
	# Другой материк: до гавани, морем, от берега.
	var port := nearest_port(world, from, ports)
	var landing := landing_cell(world, to)
	if port < 0 or landing < 0:
		return PackedInt32Array()
	var w1 := water_next_to(world, port)
	var w2 := water_next_to(world, landing)
	if w1 < 0 or w2 < 0:
		return PackedInt32Array()
	var sea := water_path(world, w1, w2) if w1 != w2 else PackedInt32Array()
	if sea.is_empty() and w1 != w2:
		return PackedInt32Array()
	var out := land_path(world, from, port, prof) if port != from else PackedInt32Array()
	if out.is_empty() and port != from:
		return PackedInt32Array()
	out.append(w1)
	out.append_array(sea)
	out.append(landing)
	out.append_array(land_path(world, landing, to, prof))
	return out


## Гавань (город с портом) на материке клетки, ближайшая к ней; -1 — нет.
static func nearest_port(world: World, cell: int, ports: PackedInt32Array = PackedInt32Array()) -> int:
	var lm := landmass(world, cell)
	var p := world.map.cell_pos(cell)
	var best := -1
	var best_d := INF
	for city in world.cities:
		if not city.alive or not city.buildings.has(&"harbor") or landmass(world, city.cell) != lm:
			continue
		if not ports.is_empty() and not ports.has(city.nation_id):
			continue
		var d := Vector2(world.map.cell_pos(city.cell) - p).length_squared()
		if d < best_d:
			best_d = d
			best = city.cell
	return best


## Береговая клетка на материке цели, ближайшая к ней (сюда высаживаются с моря).
static func landing_cell(world: World, target: int) -> int:
	var map := world.map
	if world.is_coastal(target):
		return target
	var tr := world.region_of[target]
	if tr < 0:
		return -1
	var tp := Vector2(map.cell_pos(target))
	var lm := landmass(world, target)
	# Береговые регионы того же материка, ближайшие к цели.
	var best_region := -1
	var best_d := INF
	for r in world.regions:
		if not r.coastal or r.cells.is_empty() or _land[r.id] != lm:
			continue
		var d := Vector2(map.cell_pos(r.center)).distance_squared_to(tp)
		if d < best_d:
			best_d = d
			best_region = r.id
	if best_region < 0:
		return -1
	var best := -1
	best_d = INF
	for c in world.regions[best_region].cells:
		if world.is_coastal(c):
			var d := Vector2(map.cell_pos(c)).distance_squared_to(tp)
			if d < best_d:
				best_d = d
				best = c
	return best


## Морская клетка (океан или море) рядом с клеткой суши; -1 — нет.
static func water_next_to(world: World, cell: int) -> int:
	var map := world.map
	if not map.is_land(cell):
		return cell
	for nb in map.neighbors4(cell):
		var b := map.biome[nb]
		if b == Biome.OCEAN or b == Biome.SEA:
			return nb
	return -1


# ---------------------------------------------------------------------------
# Суша: регионы → отрезки
# ---------------------------------------------------------------------------

static func land_path(world: World, from: int, to: int, prof: MoveProfileDef) -> PackedInt32Array:
	if from == to:
		return PackedInt32Array()
	_ensure(world)
	var rf := world.region_of[from]
	var rt := world.region_of[to]
	if rf < 0 or rt < 0 or _land[rf] != _land[rt]:
		return PackedInt32Array()
	var regions := region_route(world, rf, rt, prof)
	if regions.is_empty():
		return PackedInt32Array()
	var out := PackedInt32Array()
	var cur := from
	for i in range(1, regions.size()):
		var pr := portal(world, regions[i - 1], regions[i])
		if pr.x < 0:
			return PackedInt32Array()
		var seg := segment(world, cur, pr.x, regions[i - 1], prof)
		if seg.is_empty() and cur != pr.x:
			return PackedInt32Array()
		out.append_array(seg)
		out.append(pr.y)
		cur = pr.y
	var last := segment(world, cur, to, rt, prof)
	if last.is_empty() and cur != to:
		return PackedInt32Array()
	out.append_array(last)
	return out


## Маршрут по графу регионов (включая начальный и конечный).
static func region_route(world: World, from: int, to: int, prof: MoveProfileDef) -> PackedInt32Array:
	if from == to:
		return PackedInt32Array([from])
	var key := "%d:%d:%s" % [from, to, prof.id]
	if _routes.has(key):
		return _routes[key]
	var t0 := Time.get_ticks_usec() if profile else 0
	var res := _region_route(world, from, to, prof)
	if profile:
		_note("regions", t0)
	_cap(_routes)
	_routes[key] = res
	return res


## Рабочие массивы «Дейкстры» по регионам (метки вместо очистки).
static var _rd := PackedFloat32Array()
static var _rp := PackedInt32Array()
static var _rs := PackedInt32Array()
static var _rmark := 0
static var _rheap := MinHeap.new()


static func _region_route(world: World, from: int, to: int, prof: MoveProfileDef) -> PackedInt32Array:
	# Соседний край — сразу (так ходят почти все странники, племена и чудовища).
	if world.regions[from].neighbors.has(to):
		return PackedInt32Array([from, to])
	var n := world.regions.size()
	if _rd.size() < n:
		_rd.resize(n)
		_rp.resize(n)
		_rs.resize(n)
		_rs.fill(0)
	_rmark += 1
	var mark := _rmark
	var dist := _rd
	var prev := _rp
	var heap := _rheap
	heap.clear()
	dist[from] = 0.0
	prev[from] = -1
	_rs[from] = mark
	heap.push(from, 0.0)
	var map := world.map
	var found := false
	while not heap.is_empty():
		var d := heap.top_priority()
		var r := heap.pop()
		if d > dist[r]:
			continue
		if r == to:
			found = true
			break
		var pr := Vector2(map.cell_pos(world.regions[r].center))
		for nb in world.regions[r].neighbors:
			var region := world.regions[nb]
			if region.cells.is_empty() or region.center < 0:
				continue
			var len := pr.distance_to(Vector2(map.cell_pos(region.center)))
			var nd := d + len / _mult(world, prof, region.center)
			if _rs[nb] != mark or nd < dist[nb]:
				_rs[nb] = mark
				dist[nb] = nd
				prev[nb] = r
				heap.push(nb, nd)
	var res := PackedInt32Array()
	if found:
		var cur := to
		while cur >= 0:
			res.append(cur)
			cur = prev[cur]
		res.reverse()
	return res


## Переход из региона a в соседний b: клетка в a у границы, ближайшая к середине
## между центрами, и её сосед в b.
static func portal(world: World, a: int, b: int) -> Vector2i:
	var key := Vector2i(a, b)
	if _portal.has(key):
		return _portal[key]
	var map := world.map
	var mid := (Vector2(map.cell_pos(world.regions[a].center)) + Vector2(map.cell_pos(world.regions[b].center))) * 0.5
	var best := Vector2i(-1, -1)
	var best_d := INF
	for c in world.regions[a].cells:
		for nb in map.neighbors4(c):
			if world.region_of[nb] == b:
				var d := Vector2(map.cell_pos(c)).distance_squared_to(mid)
				if d < best_d:
					best_d = d
					best = Vector2i(c, nb)
				break
	_cap(_portal)
	_portal[key] = best
	return best


## Отрезок внутри региона r: прямая, если она идёт по его суше, иначе A*.
static func segment(world: World, from: int, to: int, r: int, prof: MoveProfileDef) -> PackedInt32Array:
	if from == to:
		return PackedInt32Array()
	var key := Vector4i(from, to, r, _prof_index(prof))
	if _seg.has(key):
		return _seg[key]
	var res := line(world, from, to, r)
	if res.is_empty():
		res = astar(world, from, to, r, prof, REGION_BUDGET * world.grid_scale * world.grid_scale)
	if res.is_empty():
		# Регион разрезан (рельеф менялся) — без ограничения регионом.
		res = astar(world, from, to, -2, prof, FALLBACK_BUDGET * world.grid_scale * world.grid_scale)
	_cap(_seg)
	_seg[key] = res
	return res


## Прямая по клеткам (8-связная) от from до to; пусто — сходит с суши региона r
## (r = -1 — любая суша).
static func line(world: World, from: int, to: int, r: int) -> PackedInt32Array:
	var map := world.map
	var a := map.cell_pos(from)
	var b := map.cell_pos(to)
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := 1 if b.x > a.x else -1
	var sy := 1 if b.y > a.y else -1
	var err := dx - dy
	var x := a.x
	var y := a.y
	var out := PackedInt32Array()
	while x != b.x or y != b.y:
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		var c := map.index_of(x, y)
		if not map.is_land(c) or (r >= 0 and world.region_of[c] != r):
			return PackedInt32Array()
		out.append(c)
	return out


## A* по суше (region >= 0 — только в этом регионе; -2 — везде), бюджет узлов.
static func astar(world: World, from: int, to: int, region: int, prof: MoveProfileDef, budget: int) -> PackedInt32Array:
	if not profile:
		return _astar(world, from, to, region, prof, budget)
	var t0 := Time.get_ticks_usec()
	var res := _astar(world, from, to, region, prof, budget)
	_note("astar" if region >= 0 else "astar_free", t0)
	return res


static func _astar(world: World, from: int, to: int, region: int, prof: MoveProfileDef, budget: int) -> PackedInt32Array:
	searches += 1
	var map := world.map
	var w := map.width
	var h := map.height
	_mark += 1
	var mark := _mark
	var heap := _heap
	heap.clear()
	var tp := map.cell_pos(to)
	var hmin := 1.0 / _max_mult(prof)
	_g[from] = 0.0
	_seen[from] = mark
	_from[from] = -1
	heap.push(from, 0.0)
	var expanded := 0
	var found := false
	while not heap.is_empty():
		var c := heap.pop()
		if _done[c] == mark:
			continue
		_done[c] = mark
		if c == to:
			found = true
			break
		expanded += 1
		if expanded > budget:
			break
		var cx := c % w
		var cy := c / w
		var gc := _g[c]
		for k in 8:
			var nx := cx + (1 if k == 0 or k == 4 or k == 6 else (-1 if k == 1 or k == 5 or k == 7 else 0))
			var ny := cy + (1 if k == 2 or k == 4 or k == 5 else (-1 if k == 3 or k == 6 or k == 7 else 0))
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nb := ny * w + nx
			if _done[nb] == mark or not map.is_land(nb):
				continue
			if region >= 0 and world.region_of[nb] != region:
				continue
			var step := (DIAG if k >= 4 else 1.0) / _mult(world, prof, nb)
			var ng := gc + step
			if _seen[nb] != mark or ng < _g[nb]:
				_seen[nb] = mark
				_g[nb] = ng
				_from[nb] = c
				var ddx := absi(nx - tp.x)
				var ddy := absi(ny - tp.y)
				heap.push(nb, ng + (maxi(ddx, ddy) + (DIAG - 1.0) * mini(ddx, ddy)) * hmin)
	if not found:
		return PackedInt32Array()
	var out := PackedInt32Array()
	var cur := to
	while cur != from:
		out.append(cur)
		cur = _from[cur]
	out.reverse()
	return out


# ---------------------------------------------------------------------------
# Вода
# ---------------------------------------------------------------------------

static func _sea_cell(map: WorldMap, c: int) -> bool:
	var b := map.biome[c]
	return b == Biome.OCEAN or b == Biome.SEA


## Путь по морю (океан и море) между морскими клетками, иерархически: A* по
## грубой сетке блоков (компоненты связности отсекают недостижимое сразу), затем
## по клеткам — прямыми по воде между блоками, а где прямая задевает сушу —
## небольшим A* в окрестности.
static func water_path(world: World, from: int, to: int) -> PackedInt32Array:
	if from == to:
		return PackedInt32Array()
	_ensure(world)
	var key := Vector2i(from, to)
	if _sea.has(key):
		return _sea[key]
	var t0 := Time.get_ticks_usec() if profile else 0
	var out := _water_path(world, from, to)
	if profile:
		_note("water", t0)
	_cap(_sea)
	_sea[key] = out
	return out


## Рабочие массивы A* по блокам моря.
static var _bg := PackedFloat32Array()
static var _bprev := PackedInt32Array()
static var _bseen := PackedInt32Array()
static var _bmark := 0
static var _bheap := MinHeap.new()


static func _block(map: WorldMap, c: int) -> int:
	return (c / map.width) / _wb * _ww + (c % map.width) / _wb


## Компоненты блоков у клетки (сам блок и соседи — у берега блок бывает «сухим»).
static func _comps_near(map: WorldMap, c: int) -> PackedInt32Array:
	var b := _block(map, c)
	var bx := b % _ww
	var by := b / _ww
	var res := PackedInt32Array()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := bx + dx
			var ny := by + dy
			if nx >= 0 and ny >= 0 and nx < _ww and ny < _wh and _wcomp[ny * _ww + nx] >= 0 and not res.has(_wcomp[ny * _ww + nx]):
				res.append(_wcomp[ny * _ww + nx])
	return res


static func _water_path(world: World, from: int, to: int) -> PackedInt32Array:
	_ensure_water(world)
	var map := world.map
	var ca := _comps_near(map, from)
	var cb := _comps_near(map, to)
	var shared := -1
	for c in ca:
		if cb.has(c):
			shared = c
			break
	var fb := _block(map, from)
	var tb := _block(map, to)
	if shared < 0 and fb != tb:
		# Разные моря — или узкий пролив мельче блока: прямой поиск с небольшим бюджетом.
		return _water_astar(world, from, to, -1, FALLBACK_BUDGET)
	# 1. A* по блокам.
	searches += 1
	var blocks := PackedInt32Array()
	if fb != tb:
		var n := _ww * _wh
		if _bg.size() != n:
			_bg.resize(n)
			_bprev.resize(n)
			_bseen.resize(n)
			_bseen.fill(0)
		_bmark += 1
		var bm := _bmark
		var g := _bg
		var prev := _bprev
		var heap := _bheap
		heap.clear()
		g[fb] = 0.0
		prev[fb] = -1
		_bseen[fb] = bm
		heap.push(fb, 0.0)
		var tx := tb % _ww
		var ty := tb / _ww
		var found := false
		var expanded := 0
		while not heap.is_empty():
			var pr := heap.top_priority()
			var b := heap.pop()
			if b == tb:
				found = true
				break
			expanded += 1
			if expanded > COARSE_BUDGET:
				break
			var bx := b % _ww
			var by := b / _ww
			if pr - (maxi(absi(bx - tx), absi(by - ty))) * COARSE_W > g[b] + 0.001:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := bx + dx
					var ny := by + dy
					if nx < 0 or ny < 0 or nx >= _ww or ny >= _wh:
						continue
					var nb := ny * _ww + nx
					if nb != tb and (_wpass[nb] == 0 or (shared >= 0 and _wcomp[nb] != shared)):
						continue
					var ng := g[b] + (DIAG if dx != 0 and dy != 0 else 1.0)
					if _bseen[nb] != bm or ng < g[nb]:
						_bseen[nb] = bm
						g[nb] = ng
						prev[nb] = b
						heap.push(nb, ng + maxi(absi(nx - tx), absi(ny - ty)) * COARSE_W)
		if not found:
			return _water_astar(world, from, to, -1, FALLBACK_BUDGET)
		var cur := tb
		while cur != fb:
			blocks.append(cur)
			cur = prev[cur]
		blocks.reverse()
	# 2. По клеткам: точки — морские клетки у центров блоков пути.
	var points := PackedInt32Array([from])
	for i in range(0, blocks.size() - 1):
		var c := _sea_in_block(map, blocks[i])
		if c >= 0:
			points.append(c)
	points.append(to)
	var out := PackedInt32Array()
	for i in range(1, points.size()):
		var seg := _sea_line(map, points[i - 1], points[i])
		if seg.is_empty():
			seg = _water_astar(world, points[i - 1], points[i], _wb * 3, _wb * _wb * 40)
			if seg.is_empty():
				return PackedInt32Array()
		out.append_array(seg)
	return out


## Морская клетка блока, ближайшая к его центру (-1 — нет).
static func _sea_in_block(map: WorldMap, b: int) -> int:
	var x0 := (b % _ww) * _wb
	var y0 := (b / _ww) * _wb
	var cx := x0 + _wb / 2
	var cy := y0 + _wb / 2
	var best := -1
	var best_d := 1 << 30
	for y in range(y0, mini(y0 + _wb, map.height)):
		for x in range(x0, mini(x0 + _wb, map.width)):
			var c := y * map.width + x
			if _sea_cell(map, c):
				var d := (x - cx) * (x - cx) + (y - cy) * (y - cy)
				if d < best_d:
					best_d = d
					best = c
	return best


## Прямая по воде (8-связная); пусто — задевает сушу.
static func _sea_line(map: WorldMap, from: int, to: int) -> PackedInt32Array:
	var a := map.cell_pos(from)
	var b := map.cell_pos(to)
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := 1 if b.x > a.x else -1
	var sy := 1 if b.y > a.y else -1
	var err := dx - dy
	var x := a.x
	var y := a.y
	var out := PackedInt32Array()
	while x != b.x or y != b.y:
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		var c := map.index_of(x, y)
		if c != to and not _sea_cell(map, c):
			return PackedInt32Array()
		out.append(c)
	return out


## A* по морским клеткам (radius >= 0 — только в окрестности отрезка), бюджет узлов.
static func _water_astar(world: World, from: int, to: int, radius: int, budget: int) -> PackedInt32Array:
	searches += 1
	var map := world.map
	var w := map.width
	var h := map.height
	_mark += 1
	var mark := _mark
	var heap := _heap
	heap.clear()
	var fp := map.cell_pos(from)
	var tp := map.cell_pos(to)
	var lo := Vector2i(mini(fp.x, tp.x) - radius, mini(fp.y, tp.y) - radius)
	var hi := Vector2i(maxi(fp.x, tp.x) + radius, maxi(fp.y, tp.y) + radius)
	_g[from] = 0.0
	_seen[from] = mark
	_from[from] = -1
	heap.push(from, 0.0)
	var expanded := 0
	var found := false
	while not heap.is_empty():
		var c := heap.pop()
		if _done[c] == mark:
			continue
		_done[c] = mark
		if c == to:
			found = true
			break
		expanded += 1
		if expanded > budget:
			break
		var cx := c % w
		var cy := c / w
		var gc := _g[c]
		for k in 8:
			var nx := cx + (1 if k == 0 or k == 4 or k == 6 else (-1 if k == 1 or k == 5 or k == 7 else 0))
			var ny := cy + (1 if k == 2 or k == 4 or k == 5 else (-1 if k == 3 or k == 6 or k == 7 else 0))
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if radius >= 0 and (nx < lo.x or ny < lo.y or nx > hi.x or ny > hi.y):
				continue
			var nb := ny * w + nx
			if _done[nb] == mark or (nb != to and not _sea_cell(map, nb)):
				continue
			var ng := gc + (DIAG if k >= 4 else 1.0)
			if _seen[nb] != mark or ng < _g[nb]:
				_seen[nb] = mark
				_g[nb] = ng
				_from[nb] = c
				var ddx := absi(nx - tp.x)
				var ddy := absi(ny - tp.y)
				heap.push(nb, ng + (maxi(ddx, ddy) + (DIAG - 1.0) * mini(ddx, ddy)) * WATER_W)
	var out := PackedInt32Array()
	if found:
		var cur := to
		while cur != from:
			out.append(cur)
			cur = _from[cur]
		out.reverse()
	return out


# ---------------------------------------------------------------------------
# Стоимость
# ---------------------------------------------------------------------------

## Множитель скорости профиля в клетке (рельеф и река; дороги и зима — при ходьбе).
static func _mult(world: World, prof: MoveProfileDef, cell: int) -> float:
	var map := world.map
	var m := prof.mult(map.biome[cell])
	if map.river[cell] > 0:
		m *= prof.river_mult
	return maxf(m, 0.05)


static func _max_mult(prof: MoveProfileDef) -> float:
	var m := 1.0
	for v in prof.biome_mult.values():
		m = maxf(m, float(v))
	return m


## Ключ мира для кэшей (Vector3i — 32-битный): весь id объекта, свёрнутый хэшем
## (младших 31 бита мало — у двух миров в одном процессе они могут совпасть).
static func _wid(world: World) -> int:
	return hash(world.get_instance_id()) & 0x7fffffff
