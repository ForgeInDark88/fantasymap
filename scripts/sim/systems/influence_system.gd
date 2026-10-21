class_name InfluenceSystem
extends RefCounted
## Влияние и освоение земли (этап 12.C) — вместо «каждый год случайные соседние
## клетки по одной» (ExpansionSystem, остался за Features.CLASSIC_EXPANSION).
##
## Источники влияния — столица, города и поселения (деревни, колонии, форты,
## аванпосты, data/settlement). От каждого влияние расходится по земле, теряя
## силу по рельефу (RaceDef.expansion_cost: дворфу горы дёшевы, эльфу — лес);
## World.infl[c] — «запас хода» до края влияния (≤ 0 — клетка в его пределах).
## Каждый год держава тратит очки освоения (те же, что прежде) на ничьи клетки
## своего фронта — ближние к источникам раньше (куча Nation.frontier), так что
## земля растёт цельными пятнами без дыр и одиночных клеток. Дальше предела
## влияния — только через поселенцев (SettlerSystem): новая деревня у края —
## новый источник, и рост идёт дальше. Пересчёт — локальный: новый источник
## «доливает» влияние вокруг себя; полная пересборка — лишь когда земля державы
## поменялась чужой рукой (войны, мятежи; Nation.infl_dirty).

## Множитель скорости освоения (как ExpansionSystem.RATE).
const RATE := 3.6
const AREA_POW := 0.25
## Степень цены рельефа для дальности влияния (1 — как цена освоения).
const TERRAIN_POW := 0.6
## Дальность влияния (в базовых клетках «лёгкой» земли): столица, город (+ за
## каждую ступень размера), прочее — SettlementDef.reach.
const CAPITAL_REACH := 13.0
const CITY_REACH := 7.25
const TIER_REACH := 1.25
## Фронт хранит ничьи клетки и чуть дальше предела влияния (на столько базовых
## клеток) — там поселенцы выбирают место для деревни.
const MARGIN := 5.0
## Сколько клеток за год можно занять при самом щедром запасе очков (× gs²).
const MAX_CLAIMS := 160
## Пересчёт влияния — порциями: не больше стольких шагов «Дейкстры» на державу
## за сутки (и столько же в её годовой ход), чтобы пересборка большой державы
## после войны не съедала кадр. Пока порция не доделана, держава не осваивает.
const WORK_BUDGET := 1500
## Запас хранится во float32 (World.infl), а считается в double: улучшение меньше
## EPS — не улучшение (иначе округление вверх запускает волну пересчёта заново).
const EPS := 1e-4
## Форты: шанс в год воюющей державы и предел числа (1 + города / 2).
const FORT_CHANCE := 0.25
## Деревни не ближе друг к другу и к городам (базовых клеток).
const SPACING := 5

var settlers := SettlerSystem.new()
## Профилирование частей хода (tests): имя → худший вызов, мкс.
static var profile := false
static var worst: Dictionary = {}


static func _note(part: String, t0: int) -> void:
	var dt := Time.get_ticks_usec() - t0
	if dt > int(worst.get(part, 0)):
		worst[part] = dt



## Годовой ход державы (в «её» день года, вместо ExpansionSystem.tick).
func tick(world: World, nation: Nation) -> void:
	var n := nation.cells.size()
	if n == 0:
		return
	var race := nation.race
	var map := world.map
	var cap := nation.total_capacity()
	var pressure := clampf(nation.population / cap, 0.0, 1.2) if cap > 0.0 else 1.0
	var gs := world.grid_scale
	# Очки растут медленнее периметра (площадь^AREA_POW): все очки уходят в землю
	# фронта, без промахов прежней «случайной клетки». Площадь — в базовых клетках.
	var rate := RATE * pow(nation.base_area, AREA_POW) * (gs * gs) * race.expansion * nation.effect(&"expansion_mult") * (0.2 + pressure) * (0.4 + nation.stability * 0.6)
	nation.expansion_points = minf(nation.expansion_points + rate, rate * 3.0 + 4.0 * (gs * gs))
	var t0 := Time.get_ticks_usec() if profile else 0
	if nation.frontier != null and not nation.infl_dirty:
		_refresh_sources(world, nation)
	if profile:
		_note("sources", t0)
		t0 = Time.get_ticks_usec()
	if nation.frontier == null or nation.infl_dirty:
		rebuild(world, nation)
	if nation.infl_work != null and not _work(world, nation, WORK_BUDGET):
		if profile:
			_note("rebuild", t0)
		return  # влияние ещё пересчитывается (доделается за следующие сутки)
	if profile:
		_note("rebuild", t0)
		t0 = Time.get_ticks_usec()
	var heap := nation.frontier
	var claimed := 0
	var limit := MAX_CLAIMS * gs * gs
	var own := nation.id
	while not heap.is_empty() and claimed < limit:
		var c := heap.top_item()
		var d := heap.top_priority()
		if world.owner[c] != -1:
			heap.pop()
			continue
		if d > 0.0:
			break
		var cost := race.expansion_cost(map.biome[c])
		if map.river[c] > 0:
			cost *= 0.85
		if cost > nation.expansion_points:
			break
		heap.pop()
		world.set_owner(c, own)
		world.infl[c] = d
		nation.expansion_points -= cost
		claimed += 1
		_spread(world, nation, c, d)
	# Расти некуда: копится «земельный голод» (повод для войн) — и уходят поселенцы.
	nation.stalled_years = nation.stalled_years + 1 if claimed == 0 else 0
	if profile:
		_note("claims", t0)
		t0 = Time.get_ticks_usec()
	settlers.consider(world, nation, pressure)
	if profile:
		_note("settlers", t0)
		t0 = Time.get_ticks_usec()
	if world.diplomacy.at_war(own):
		_maybe_fort(world, nation)
		if profile:
			_note("fort", t0)


## Цена шага влияния в клетку c (в базовых клетках).
static func step_cost(world: World, race: RaceDef, c: int) -> float:
	return _cost_table(race)[world.map.biome[c]] * (0.85 if world.map.river[c] > 0 else 1.0) / world.grid_scale


## Цена клетки по биому для расы (кэш: RaceDef.expansion_cost зависит только от них).
static var _costs: Dictionary = {}


static func _cost_table(race: RaceDef) -> PackedFloat32Array:
	var t: PackedFloat32Array = _costs.get(race.index, PackedFloat32Array())
	if t.is_empty():
		# Влияние смягчает разницу рельефа (степень TERRAIN_POW): иначе держава
		# забирает только лучшую землю и густеет сверх меры.
		for b in BiomeDB.all().size():
			t.append(pow(race.expansion_cost(b), TERRAIN_POW))
		_costs[race.index] = t
	return t


## Множитель дальности влияния державы — по расе (не по временным эффектам: иначе
## дальность «дрожит» каждый год и влияние пересчитывается заново; технологии и
## постройки ускоряют освоение через очки).
static func reach_mult(nation: Nation) -> float:
	return clampf(sqrt(nation.race.expansion), 0.6, 1.5)


## Дальность влияния города.
static func city_reach(world: World, nation: Nation, city: City) -> float:
	var r := CAPITAL_REACH if city.is_capital else CITY_REACH + TIER_REACH * city.tier()
	return r * reach_mult(nation)


## Из клетки c (своей, запас d) — дальше: свои клетки получают меньший запас,
## ничьи — в фронт.
static func _spread(world: World, nation: Nation, c: int, d: float) -> void:
	var map := world.map
	var w := map.width
	var x := c % w
	var own := nation.id
	var heap := nation.frontier
	for k in 4:
		var nb := -1
		if k == 0 and x > 0:
			nb = c - 1
		elif k == 1 and x < w - 1:
			nb = c + 1
		elif k == 2 and c >= w:
			nb = c - w
		elif k == 3 and c < world.owner.size() - w:
			nb = c + w
		if nb < 0 or not map.is_land(nb):
			continue
		var o := world.owner[nb]
		if o != -1 and o != own:
			continue
		var nd := d + step_cost(world, nation.race, nb)
		if nd > MARGIN:
			continue
		if o == -1:
			heap.push(nb, nd)
		elif nd < world.infl[nb] - EPS:
			world.infl[nb] = nd
			_relax(world, nation, nb, nd)


## Дейкстра по своей земле от клетки start с запасом d (локальный пересчёт).
static func _relax(world: World, nation: Nation, start: int, d: float) -> void:
	var h := MinHeap.new()
	h.push(start, d)
	_run(world, nation, h)


## Отложенный пересчёт: клетка с новым запасом — в очередь державы.
static func _queue(nation: Nation, cell: int, d: float) -> void:
	if nation.infl_work == null:
		nation.infl_work = MinHeap.new()
	nation.infl_work.push(cell, d)


## Порция отложенного пересчёта. true — очередь пуста.
static func _work(world: World, nation: Nation, budget: int) -> bool:
	if nation.infl_work == null:
		return true
	if nation.frontier == null:
		nation.infl_work = null
		return true
	if _run(world, nation, nation.infl_work, budget):
		nation.infl_work = null
		return true
	return false


## Сутки: порции пересчёта у держав, где он идёт (обычно ни одной).
func tick_day(world: World) -> void:
	for n in world.nations:
		if n.infl_work != null and n.alive:
			_work(world, n, WORK_BUDGET)


## Дейкстра по своей земле от клеток в куче h (их запас уже записан в World.infl);
## budget ≥ 0 — не больше стольких шагов. true — куча опустела.
static func _run(world: World, nation: Nation, h: MinHeap, budget: int = -1) -> bool:
	var map := world.map
	var w := map.width
	var n := world.owner.size()
	var own := nation.id
	var owner := world.owner
	var infl := world.infl
	var costs := _cost_table(nation.race)
	var inv := 1.0 / world.grid_scale
	var biome := map.biome
	var river := map.river
	var front := nation.frontier
	while not h.is_empty():
		if budget == 0:
			return false
		budget -= 1
		var p := h.top_priority()
		var c := h.pop()
		if p > infl[c]:
			continue
		var x := c % w
		for k in 4:
			var nb := -1
			if k == 0 and x > 0:
				nb = c - 1
			elif k == 1 and x < w - 1:
				nb = c + 1
			elif k == 2 and c >= w:
				nb = c - w
			elif k == 3 and c < n - w:
				nb = c + w
			if nb < 0:
				continue
			var o := owner[nb]
			if o != -1 and o != own:
				continue
			var b := biome[nb]
			if b <= Biome.LAKE:
				continue
			var nd := p + costs[b] * (0.85 if river[nb] > 0 else 1.0) * inv
			if nd > MARGIN:
				continue
			if o == -1:
				front.push(nb, nd)
			elif nd < infl[nb] - EPS:
				infl[nb] = nd
				h.push(nb, nd)
	return true


## Источники меняются: город вырос (дальше — доливаем влияние), уменьшился или
## перестал быть столицей (меньше — пересборка). Дальность поселений постоянна;
## пропавшее или перешедшее поселение помечает державу к пересборке (tick_year).
static func _refresh_sources(world: World, nation: Nation) -> void:
	for id in nation.city_ids:
		var city := world.cities[id]
		if city.alive and not _check_source(world, nation, city.cell, city_reach(world, nation, city)):
			return


## false — источник ослаб: держава помечена к пересборке.
static func _check_source(world: World, nation: Nation, cell: int, reach: float) -> bool:
	if world.owner[cell] != nation.id:
		return true
	var v := world.infl[cell]
	# Запас клетки источника ниже его силы, а соседних сильнее нет — источник ослаб.
	if v < -reach - 1e-4 and _own_source_weaker(world, nation, cell, v):
		nation.infl_dirty = true
		return false
	if v > -reach + EPS:
		add_source(world, nation, cell, reach)
	return true


## Запас клетки не объясняется соседями (значит, его дал прежний, более сильный источник здесь).
static func _own_source_weaker(world: World, nation: Nation, cell: int, v: float) -> bool:
	var step := step_cost(world, nation.race, cell)
	for nb in world.map.neighbors4(cell):
		if world.owner[nb] == nation.id and absf(world.infl[nb] + step - v) <= 1e-4:
			return false
	return true


## Новый источник влияния в своей клетке cell (город, поселение): локальный пересчёт.
static func add_source(world: World, nation: Nation, cell: int, reach: float) -> void:
	if nation.frontier == null or nation.infl_dirty or world.owner[cell] != nation.id:
		return  # пересоберётся целиком в свой год
	if -reach < world.infl[cell] - EPS:
		world.infl[cell] = -reach
		_queue(nation, cell, -reach)


## Полная пересборка влияния и фронта державы: Дейкстра от всех источников по
## своей земле (только в пределах влияния и MARGIN за ним).
static func rebuild(world: World, nation: Nation) -> void:
	nation.frontier = MinHeap.new()
	nation.infl_dirty = false
	for c in nation.cells:
		world.infl[c] = World.INFL_FAR
	var h := MinHeap.new()
	nation.infl_work = h
	for id in nation.city_ids:
		var city := world.cities[id]
		if city.alive:
			_seed(world, nation, h, city.cell, city_reach(world, nation, city))
	for s in world.settlements:
		if s.alive and s.nation == nation.id:
			_seed(world, nation, h, s.cell, s.def.reach * reach_mult(nation))
	# Ни одного источника (державу собрали из отколовшихся краёв без города) —
	# влияние держит хотя бы её «дом».
	if h.is_empty() and nation.home_cell >= 0:
		_seed(world, nation, h, nation.home_cell, CITY_REACH * reach_mult(nation))


static func _seed(world: World, nation: Nation, h: MinHeap, cell: int, reach: float) -> void:
	if world.owner[cell] == nation.id and -reach < world.infl[cell] - EPS:
		world.infl[cell] = -reach
		h.push(cell, -reach)


## Основать поселение kind в клетке cell: свою или ничью. Деревня и колония
## занимают и ближние ничьи клетки (не одиночная клетка, а пятно).
static func found(world: World, nation: Nation, kind: StringName, cell: int, people: float = 0.0) -> Settlement:
	var def := SettlementDB.find(kind)
	if def == null or not world.map.is_land(cell):
		return null
	var o := world.owner[cell]
	if o != -1 and o != nation.id:
		return null
	var s := Settlement.new()
	s.id = world.settlements.size()
	s.def = def
	s.kind = kind
	s.cell = cell
	s.nation = nation.id
	s.founded = world.year
	s.name = NameGenerator.unique(world.used_names, NameGenerator.place_name.bind(nation.race, world.rng))
	world.settlements.append(s)
	if o == -1:
		world.set_owner(cell, nation.id)
	if kind == &"village" or kind == &"colony":
		var p := world.map.cell_pos(cell)
		var r := world.gdi(1)
		for y in range(maxi(0, p.y - r), mini(world.map.height, p.y + r + 1)):
			for x in range(maxi(0, p.x - r), mini(world.map.width, p.x + r + 1)):
				var c := world.map.index_of(x, y)
				if world.owner[c] == -1 and world.map.is_land(c):
					world.set_owner(c, nation.id)
	if people > 0.0:
		var ri := nation.race.index
		nation.pop[ri] += people
	add_source(world, nation, cell, def.reach * reach_mult(nation))
	world.count(StringName("settle_" + str(kind)))
	return s


## Можно ли поставить деревню в клетку (место под будущий город, не у другого поселения).
static func site_ok(world: World, cell: int) -> bool:
	if not world.map.is_land(cell) or not world.can_place_city(cell):
		return false
	var p := world.map.cell_pos(cell)
	var r := world.gdi(SPACING)
	for s in world.settlements:
		if s.alive:
			var q := world.map.cell_pos(s.cell)
			if maxi(absi(p.x - q.x), absi(p.y - q.y)) < r:
				return false
	return true


## Пограничный форт у врага (воюющая держава, раз в год, если есть средства).
func _maybe_fort(world: World, nation: Nation) -> void:
	var def := SettlementDB.find(&"fort")
	if def == null or world.rng.randf() > FORT_CHANCE:
		return
	if nation.stock[Goods.GOLD] < def.cost_gold or nation.stock[Goods.STONE] < def.cost_stone or nation.stock[Goods.WOOD] < def.cost_wood:
		return
	var forts := 0
	for s in world.settlements:
		if s.alive and s.nation == nation.id and s.kind == &"fort":
			forts += 1
	if forts >= 1 + nation.city_ids.size() / 2:
		return
	var map := world.map
	var best := -1
	for k in 24:
		var c := nation.cells[world.rng.randi_range(0, nation.cells.size() - 1)]
		var enemy := false
		for nb in map.neighbors4(c):
			var o := world.owner[nb]
			if o >= 0 and o != nation.id and world.diplomacy.war_between(nation.id, o) != null:
				enemy = true
				break
		if not enemy or world.city_cell[c] >= 0:
			continue
		var p := map.cell_pos(c)
		var near := false
		for s in world.settlements:
			if s.alive and s.nation == nation.id and s.kind != &"village":
				var q := map.cell_pos(s.cell)
				if maxi(absi(p.x - q.x), absi(p.y - q.y)) < world.gd(6):
					near = true
					break
		if not near:
			best = c
			break
	if best < 0:
		return
	nation.stock[Goods.GOLD] -= def.cost_gold
	nation.stock[Goods.STONE] -= def.cost_stone
	nation.stock[Goods.WOOD] -= def.cost_wood
	var s := found(world, nation, &"fort", best)
	if s != null:
		world.log_event(&"settle", "%s возводит у границы форт %s." % [nation.short_name, s.name], PackedInt32Array([nation.id]))


## Аванпост в завоёванном крае без города (WarSystem._capture).
static func on_capture(world: World, nation: Nation, region: Region) -> void:
	var c := region.center
	if c < 0 or world.owner[c] != nation.id or world.city_cell[c] >= 0:
		return
	for s in world.settlements:
		if s.alive and world.region_of[s.cell] == region.id and s.nation == nation.id:
			return
	found(world, nation, &"outpost", c)


## Деревня, готовая стать городом (CitySystem): самая старая из выросших.
static func town_site(world: World, nation: Nation) -> Settlement:
	var best: Settlement = null
	for s in world.settlements:
		if s.alive and s.nation == nation.id and s.def.town_after > 0 and world.year - s.founded >= s.def.town_after \
				and world.owner[s.cell] == nation.id and world.can_place_city(s.cell):
			if best == null or s.founded < best.founded:
				best = s
	return best


## Оборона края от поселений в нём (форты, аванпосты).
static func region_defense(world: World, region: Region, nation_id: int) -> float:
	var d := 0.0
	for s in world.settlements:
		if s.alive and s.nation == nation_id and world.region_of[s.cell] == region.id:
			d += s.def.defense
	return d


## Раз в год для мира: поселения на чужой земле переходят к хозяину земли, на
## ничьей — пустеют; ставшие городом — уходят из списка.
func tick_year(world: World) -> void:
	var any_dead := false
	for s in world.settlements:
		if not s.alive:
			any_dead = true
			continue
		var o := world.owner[s.cell]
		if world.city_cell[s.cell] >= 0 or o < 0:
			s.alive = false
			any_dead = true
			if s.nation >= 0 and world.city_cell[s.cell] < 0:
				world.nations[s.nation].infl_dirty = true
		elif o != s.nation:
			world.nations[s.nation].infl_dirty = true
			world.nations[o].infl_dirty = true
			if s.kind == &"fort":
				world.log_event(&"settle", "Форт %s переходит к державе %s." % [s.name, world.nations[o].short_name],
						PackedInt32Array([o, s.nation]))
			s.nation = o
	if any_dead:
		var keep: Array[Settlement] = []
		for s in world.settlements:
			if s.alive:
				s.id = keep.size()
				keep.append(s)
		world.settlements = keep
