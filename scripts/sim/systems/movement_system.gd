class_name MovementSystem
extends RefCounted
## Движение юнитов по клеткам (этап 12.B). Каждый движущийся юнит (Mover) идёт
## по своему пути со скоростью профиля (MoveProfileDef): рельеф, реки без моста,
## зима, чужая земля врага замедляют, дороги ускоряют; по морю — под парусом.
## Ход — каждые сутки, только у идущих юнитов; за сутки юнит проходит не больше
## max_cells() клеток (tests/movement_test.gd ловит «телепорты»). Мгновенное
## перемещение — только допустимое (teleport(): магия, портал, Судьба, Бог,
## появление; data/teleports) и с видимой вспышкой на карте.

## Сколько последних телепортов помнить (для вспышек на карте и тестов).
const TELEPORT_LOG := 48
## Месяцы зимы (зима замедляет в холодных краях) и порог холода клетки.
const WINTER_MONTHS := [11, 0, 1]
const WINTER_COLD := 0.4

## Дороги на клетках (кэш по road_version): число сухопутных дорог через клетку.
static var _road_key := Vector3i(-1, -1, -1)
static var road_mask := PackedByteArray()
## Клетки каждой дороги (id → путь от города a к городу b, без a).
static var _road_cells: Dictionary = {}


## Сутки хода: юнит продвигается по пути на days суток.
static func advance(world: World, m: Mover, days: float = 1.0) -> void:
	m.prev_cell = m.cell
	m.moved = 0
	m.arrived = false
	if m.step >= m.path.size():
		return
	var prof := m.prof()
	var map := world.map
	var biome := map.biome
	var winter := WINTER_MONTHS.has(world.month)
	_ensure_roads(world)
	var budget := days
	while budget > 0.0 and m.step < m.path.size():
		var nxt := m.path[m.step]
		var land := not Biome.is_water(biome[nxt])
		# Клетка ушла под воду (или вышла из воды для флота): путь негоден.
		if (prof.water_only and land) or (not land and not prof.water_only and not prof.can_sail):
			m.stuck += 1
			return
		var cost := _cost(world, prof, m.cell, nxt, m.nation, land, winter)
		var need := cost - m.frac
		if budget >= need:
			budget -= need
			m.frac = 0.0
			m.cell = nxt
			m.step += 1
			m.moved += 1
		else:
			m.frac += budget
			budget = 0.0
	m.stuck = 0
	if m.step >= m.path.size():
		m.arrived = true
		m.path = PackedInt32Array()
		m.step = 0


## Суток на шаг из клетки a в соседнюю b.
static func step_days(world: World, prof: MoveProfileDef, a: int, b: int, nation: int) -> float:
	_ensure_roads(world)
	return _cost(world, prof, a, b, nation, world.map.is_land(b), WINTER_MONTHS.has(world.month))


static func _cost(world: World, prof: MoveProfileDef, a: int, b: int, nation: int, land: bool, winter: bool) -> float:
	var map := world.map
	var w := map.width
	var dist := Pathfinder.DIAG if (a % w != b % w and a / w != b / w) else 1.0
	var speed := prof.speed
	if not land:
		speed = prof.speed * prof.mult(map.biome[b]) if prof.water_only else prof.sea_speed
	else:
		speed *= prof.mult(map.biome[b])
		if road_mask[b] > 0:
			speed *= prof.road_mult
		elif map.river[b] > 0:
			speed *= prof.river_mult
		if nation >= 0:
			var o := world.owner[b]
			if o >= 0 and o != nation and world.diplomacy.war_between(nation, o) != null:
				speed *= prof.enemy_mult
	if winter and map.temperature[b] < WINTER_COLD:
		speed *= prof.winter_mult
	return dist / maxf(0.01, speed * world.grid_scale)


## Наибольшее число клеток за сутки для профиля (проверка «телепортов»).
static func max_cells(world: World, profile_id: StringName) -> int:
	var prof := MoveDB.profile(profile_id)
	var best := 1.0
	for v in prof.biome_mult.values():
		best = maxf(best, float(v))
	var land := prof.speed * best * maxf(1.0, prof.road_mult)
	var sea := prof.speed * best if prof.water_only else prof.sea_speed
	return ceili(maxf(land, sea) * world.grid_scale) + 1


## Отправить юнит в клетку to: путь по Pathfinder. false — не дойти (стоит на месте).
## ports — чьими гаванями можно плыть (id государств; пусто — любыми).
static func send(world: World, m: Mover, to: int, ports: PackedInt32Array = PackedInt32Array()) -> bool:
	if to < 0 or to == m.cell:
		m.stop()
		return to == m.cell
	if m.walking() and m.dest == to:
		return true
	var p := Pathfinder.route(world, m.cell, to, MoveDB.profile(m.profile), ports)
	if p.is_empty():
		m.stop()
		return false
	# Недошагнутая доля суток к прежней следующей клетке сгорает — честно, без прыжков.
	m.set_path(p)
	return true


## Допустимое мгновенное перемещение (data/teleports): с записью для вспышки на карте.
static func teleport(world: World, m: Mover, cell: int, reason: StringName) -> void:
	var def := MoveDB.teleport(reason)
	if def == null:
		push_error("MovementSystem: недопустимый телепорт «%s»" % reason)
		return
	var from := m.cell
	m.cell = cell
	m.prev_cell = cell
	m.stop()
	log_teleport(world, def, from, cell)


static func log_teleport(world: World, def: TeleportDef, from: int, to: int) -> void:
	world.teleports.append({"kind": def.id, "from": from, "to": to, "day": ArmySystem.today(world)})
	if world.teleports.size() > TELEPORT_LOG:
		world.teleports.remove_at(0)
	world.count(&"teleports")


# ---------------------------------------------------------------------------
# Дороги на клетках
# ---------------------------------------------------------------------------

## Какие дороги уже учтены в маске (по id).
static var _counted := PackedByteArray()
## Чей мир в кэше (id объекта, а не ссылка: статическая ссылка на World держит
## его до выгрузки скриптов, и при выходе движок падает).
static var _road_world := 0
static var _road_v := -1
static var _road_t := -1


static func _ensure_roads(world: World) -> void:
	# Быстрая проверка (на каждом шаге каждого юнита): тот же мир и те же версии.
	if world.get_instance_id() == _road_world and world.road_version == _road_v and world.terrain_version == _road_t:
		return
	var full := world.get_instance_id() != _road_world or world.terrain_version != _road_t or road_mask.size() != world.map.cell_count()
	_road_world = world.get_instance_id()
	_road_v = world.road_version
	_road_t = world.terrain_version
	if full:
		# Новый мир или рельеф: маска заново.
		road_mask.resize(world.map.cell_count())
		road_mask.fill(0)
		_road_cells.clear()
		_counted.clear()
	# Изменились лишь дороги: добавить построенные, вычесть погибшие (без обхода карты).
	if _counted.size() < world.roads.size():
		var old := _counted.size()
		_counted.resize(world.roads.size())
		for i in range(old, _counted.size()):
			_counted[i] = 0
	for r in world.roads:
		var want := 1 if r.alive and not r.sea else 0
		if _counted[r.id] == want:
			continue
		_counted[r.id] = want
		var delta := 1 if want == 1 else -1
		for c in road_cells(world, r):
			road_mask[c] = clampi(road_mask[c] + delta, 0, 255)


## Клетки дороги от города a к городу b (без клетки a); морской путь — по воде.
static func road_cells(world: World, road: Road) -> PackedInt32Array:
	if _road_cells.has(road.id):
		return _road_cells[road.id]
	var a := world.cities[road.a].cell
	var b := world.cities[road.b].cell
	var res := PackedInt32Array()
	if road.sea:
		var w1 := Pathfinder.water_next_to(world, a)
		var w2 := Pathfinder.water_next_to(world, b)
		if w1 >= 0 and w2 >= 0:
			res.append(w1)
			res.append_array(Pathfinder.water_path(world, w1, w2))
			res.append(b)
	else:
		res = Pathfinder.line(world, a, b, -1)
		if res.is_empty():
			# Рельеф поменялся (дорогу размыло) — в обход по суше.
			res = Pathfinder.land_path(world, a, b, MoveDB.profile(&"caravan"))
	_road_cells[road.id] = res
	return res


## Путь вдоль дороги из города from_city (в сторону другого конца).
static func along_road(world: World, road: Road, from_city: int) -> PackedInt32Array:
	var cells := road_cells(world, road)
	if from_city == road.a:
		return cells
	# Обратно: от b к a — тот же путь задом наперёд (без b, с a).
	var back := PackedInt32Array()
	for i in range(cells.size() - 2, -1, -1):
		back.append(cells[i])
	back.append(world.cities[road.a].cell)
	return back


## Клетка на дороге между городами (для показа и сравнения).
static func on_road(world: World, cell: int) -> bool:
	_ensure_roads(world)
	return cell >= 0 and cell < road_mask.size() and road_mask[cell] > 0
