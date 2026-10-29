class_name ArmySystem
extends RefCounted
## Армии, флоты, пираты и полководцы (этап 11.B). Вместо сражения «раз в год
## в день X» армии стоят на карте: собираются в столице, идут по регионам к
## осаждаемому региону (по рельефу, дорогами быстрее), сталкиваются, бьются,
## отступают, осаждают. Экономика войны прежняя: мощь армии — доля мощи
## государства (Nation.power()), потери — из Nation.army, счёт войны, осады
## и захват «волной» — как в WarSystem. Флоты высаживают десанты (замена
## прежнего упрощённого), бьются на море, блокируют порты; пираты грабят
## слабо защищённые порты и морские пути. Полководцы — герои-присяжные или
## обученные командиры: влияют на силу и дух, гибнут, попадают в плен,
## переходят на сторону врага, оставляют наследников.
##
## Ход: каждая война со своими армиями ходит раз в месяц (PERIOD дней) в «свой» день
## (id войны), а не все армии каждый день: движение (дни до следующего шага;
## встретив врага, армия останавливается), битвы при встрече, осада; приказы,
## снабжение и дух — раз в месяц в первый ход войны. Морские бои, пираты и
## полководцы — в конце месяца и года.

## Флот — эта доля армии государства (с морскими эффектами).
const FLEET_SHARE := 0.15
## Прибавка к силе от мастерства полководца (0..1).
const GENERAL_POWER := 0.35
## Меньше такой армии государство в поле не выводит.
const MIN_ARMY := 400.0
## В поле у стороны — не больше двух армий: вождя и сильнейшего союзника (с
## армией не меньше этой доли армии вождя). Отряды остальных (вдвое слабее: не
## своя земля, свои командиры) вливаются в армию вождя. Флот — только у вождя.
const MINOR_ALLY := 0.3
const ALLIED_SHARE := 0.5
## Сбор в столице, отступление (не меньше), дорога домой после войны (не больше), дней.
const MUSTER_DAYS := 15
const RETREAT_DAYS := 30
const HOME_DAYS := 120
## Встреча врагов: ближе стольких базовых клеток — битва (дальше, в пределах
## дозора профиля, — идут навстречу); «враг у ворот» — ополчение города выходит
## навстречу ближе GATES_RANGE, его сила — MILITIA_SHARE горожан.
const CONTACT := 1.5
## Противостояние без битвы (рано для новой) дольше стольких суток — слабейший отходит.
const STANDOFF_DAYS := 30
const GATES_RANGE := 4.0
const MILITIA_SHARE := 0.06
## Осада: дней на «одну прежнюю годовую осаду» (скорость как раньше, но непрерывно).
const SIEGE_DAYS := 90.0
## Между битвами одной войны — не меньше дней.
const BATTLE_COOLDOWN := 150
## Счёт за битву — доля прежнего «генерального сражения раз в год» (битв теперь больше).
const BATTLE_SCORE := 0.45
## Снабжение и дух: изменения в месяц.
const SUPPLY_HOME := 0.25
const SUPPLY_NEAR := -0.05
const SUPPLY_DEEP := -0.15
const SUPPLY_CUT := -0.25
const ATTRITION := 0.02
## Расписание: день хода — каждый TICK-й день; война (и её армии) ходит раз в
## PERIOD дней — в ходы с номером id % SLOTS; в каждом ходе — PERIOD дней пути и осады.
const TICK := 5
const PERIOD := 30
const SLOTS := 6
## Летопись битв: запоминаем последние для карты и хроник.
const RECENT_BATTLES := 40

var wars: WarSystem
## Пары соседних регионов с сухопутной дорогой и «есть ли гавань» — кэши на один
## ход (пересобираются в начале хода: зависят только от текущего мира, поэтому
## загруженный мир продолжает историю так же).
var _road_pairs := {}
var _road_tick := -1
var _road_world := 0
## Есть ли у государства гавань (кэш на месяц).
var _ports := {}
## Армии по войнам на текущий ход (строится раз за ход) и число войн государств.
var _war_armies := {}
var _war_count := {}
## Мощь государств на текущий ход (Nation.power() недёшев, а войн с одними и теми же участниками много).
var _power := {}
## Город у ворот на войну и день (кэш «врага у ворот»; пересобирается — результат тот же).
var _gate_city := {}
var _gate_world := 0


static func today(world: World) -> int:
	return world.year * 360 + world.month * 30 + world.day


static func armies_of_war(world: World, war_id: int) -> Array[Army]:
	var res: Array[Army] = []
	for a in world.armies:
		if a.alive and a.war == war_id:
			res.append(a)
	return res


static func armies_of(world: World, nation_id: int) -> Array[Army]:
	var res: Array[Army] = []
	for a in world.armies:
		if a.alive and a.nation == nation_id:
			res.append(a)
	return res


# ---------------------------------------------------------------------------
# Создание и роспуск
# ---------------------------------------------------------------------------

## Новая армия государства (war = -1 — гарнизон или по воле Бога). Собирается
## в столице (флот — у гавани); at_cell >= 0 — прямо там (воля Бога).
static func create(world: World, nation: Nation, war_id: int, kind: StringName = &"land", region: int = -1, at_cell: int = -1) -> Army:
	var a := Army.new()
	a.id = world.armies.size()
	a.nation = nation.id
	a.war = war_id
	a.kind = kind
	a.created_year = world.year
	var cell := at_cell
	if cell < 0:
		cell = _home_cell(world, nation, kind) if region < 0 else world.regions[region].center
	if kind == &"fleet" and cell >= 0 and world.map.is_land(cell):
		cell = Pathfinder.water_next_to(world, cell)
	a.m = Mover.new(cell, &"army" if kind == &"land" else &"fleet")
	a.m.nation = nation.id
	a.region = world.region_of[cell] if cell >= 0 and world.region_of[cell] >= 0 else (_home_region(world, nation, kind) if region < 0 else region)
	a.state = &"muster"
	a.state_until = today(world) + MUSTER_DAYS
	a.morale = _base_morale(world, nation)
	world.armies.append(a)
	if kind == &"land":
		assign_general(world, a)
	return a


## Где собирается армия: столица (флот — город с гаванью); -1 — нет городов.
static func _home_cell(world: World, nation: Nation, kind: StringName) -> int:
	if kind == &"fleet":
		for id in nation.city_ids:
			if world.cities[id].buildings.has(&"harbor"):
				return world.cities[id].cell
	if nation.capital_city >= 0:
		return world.cities[nation.capital_city].cell
	for rid in nation.region_counts:
		return world.regions[rid].center
	return -1


static func _home_region(world: World, nation: Nation, kind: StringName) -> int:
	if kind == &"fleet":
		for id in nation.city_ids:
			if world.cities[id].buildings.has(&"harbor"):
				return world.region_of[world.cities[id].cell]
	if nation.capital_city >= 0:
		return world.region_of[world.cities[nation.capital_city].cell]
	for rid in nation.region_counts:
		return rid
	return -1


static func disband(world: World, a: Army) -> void:
	a.alive = false
	a.m.stop()
	if a.general >= 0:
		world.generals[a.general].army = -1


static func _base_morale(world: World, nation: Nation) -> float:
	var m := 0.5 + 0.25 * nation.stability
	if nation.race.has_trait(&"warlike"):
		m += 0.08
	if nation.state_religion >= 0 and nation.state_religion < world.religions.size():
		m += world.religions[nation.state_religion].zeal * 0.08
	return clampf(m, 0.2, 1.0)


# ---------------------------------------------------------------------------
# Полководцы
# ---------------------------------------------------------------------------

static func assign_general(world: World, a: Army) -> void:
	var nation := world.nations[a.nation]
	# Свободный полководец державы.
	for g in world.generals:
		if g.alive and int(g.nation) == nation.id and int(g.army) < 0 and int(g.captured_by) < 0:
			g.army = a.id
			a.general = int(g.id)
			return
	# Герой-присяжный — лучший полководец.
	for hid in nation.hero_ids:
		var h := world.heroes[hid]
		if h.alive and not h.is_ruler and not _commands(world, h.id):
			a.general = new_general(world, nation, h.display_name(), clampf(0.3 + h.level * 0.035, 0.3, 1.0), h.id)
			world.generals[a.general].army = a.id
			return
	# Обученный командир (у больших держав и с казармами — чаще).
	if world.rng.randf() < 0.5 + (0.3 if nation.base_area > 200 else 0.0):
		a.general = new_general(world, nation, NameGenerator.person_name(nation.race, world.rng), world.rng.randf_range(0.15, 0.6), -1)
		world.generals[a.general].army = a.id


static func _commands(world: World, hero_id: int) -> bool:
	for g in world.generals:
		if g.alive and int(g.hero) == hero_id:
			return true
	return false


static func new_general(world: World, nation: Nation, name: String, skill: float, hero_id: int, parent: int = -1) -> int:
	var id := world.generals.size()
	world.generals.append({"id": id, "name": name, "nation": nation.id, "skill": skill, "born": world.year,
		"alive": true, "captured_by": -1, "hero": hero_id, "army": -1, "parent": parent, "wins": 0})
	return id


static func general_name(world: World, gid: int) -> String:
	if gid < 0 or gid >= world.generals.size():
		return ""
	return String(world.generals[gid].name)


## Раз в год: старость, выкуп и переход пленных, наследники.
static func generals_yearly(world: World) -> void:
	var rng := world.rng
	for g in world.generals:
		if not g.alive:
			continue
		var hero := int(g.hero)
		if hero >= 0 and not world.heroes[hero].alive:
			_general_dies(world, g, "")
			continue
		if hero < 0 and world.year - int(g.born) > 35 and rng.randf() < 0.08:
			_general_dies(world, g, "умер от старости")
			continue
		var captor := int(g.captured_by)
		if captor >= 0:
			var home := world.nations[int(g.nation)]
			if not home.alive or not world.nations[captor].alive:
				g.captured_by = -1
			elif home.stock[Goods.GOLD] > 150.0 and rng.randf() < 0.4:
				home.stock[Goods.GOLD] -= 100.0
				world.nations[captor].stock[Goods.GOLD] += 100.0
				g.captured_by = -1
				world.log_event(&"battle", "%s выкупило из плена полководца %s." % [home.name, g.name], PackedInt32Array([home.id, captor]))
			elif rng.randf() < 0.12:
				g.nation = captor
				g.captured_by = -1
				g.army = -1
				world.log_event(&"battle", "Пленный полководец %s перешёл на службу государству %s." % [g.name, world.nations[captor].name],
						PackedInt32Array([captor, home.id]))


static func _general_dies(world: World, g: Dictionary, how: String) -> void:
	g.alive = false
	var army := int(g.army)
	if army >= 0 and army < world.armies.size() and world.armies[army].general == int(g.id):
		world.armies[army].general = -1
	g.army = -1
	if not how.is_empty():
		world.log_event(&"battle", "Полководец %s %s." % [g.name, how], PackedInt32Array([int(g.nation)]))
	# Династия полководцев: сын продолжает дело отца.
	var nation := world.nations[int(g.nation)]
	if nation.alive and int(g.hero) < 0 and world.rng.randf() < 0.45:
		new_general(world, nation, "%s Младший" % String(g.name).trim_suffix(" Младший"),
			clampf(float(g.skill) * world.rng.randf_range(0.7, 1.1), 0.1, 1.0), -1, int(g.id))


# ---------------------------------------------------------------------------
# Ход по дням
# ---------------------------------------------------------------------------

func tick_day(world: World) -> void:
	# Каждые сутки: армии идут по карте, встречаются и бьются там, где сошлись.
	_daily(world)
	if world.day % TICK != 0:
		return
	var d := world.diplomacy
	var day := today(world)
	var k := world.day / TICK
	var slot := k % SLOTS
	# Ход войны — раз в месяц, и в нём же месячные дела (приказы, снабжение);
	# при PERIOD < 30 месячные дела — только в первом ходе месяца.
	var monthly := k < SLOTS
	_ports.clear()
	_war_count.clear()
	_war_armies.clear()
	_power.clear()
	var by_war := {}
	for war in d.wars:
		by_war[war.id] = war
	for a in world.armies:
		if a.alive and a.kind != &"pirates":
			# Государство пало — армия распускается; война кончилась — идёт домой (_daily).
			if not world.nations[a.nation].alive:
				disband(world, a)
			elif a.war < 0 or a.state == &"home" or not by_war.has(a.war):
				pass
			elif _war_armies.has(a.war):
				_war_armies[a.war].append(a)
			else:
				_war_armies[a.war] = [a]
	for war in d.wars:
		if war.id % SLOTS != slot:
			continue
		if monthly:
			_ensure_armies(world, war)
			# Скорость осады — раз в квартал (и сразу при смене цели).
			if (world.month + war.id) % 3 == 0:
				update_siege_rate(world, war)
		_war_turn(world, war, by_war, day, monthly)
	# Армии вне войн (созданные Богом): месячные дела и путь — в ход своего государства
	# (не по id: id меняются при уплотнении списка, а ход должен быть тем же и после загрузки).
	for a in world.armies:
		if a.alive and a.war < 0 and a.kind != &"pirates" and a.nation % SLOTS == slot:
			if monthly:
				_count_wars(world)
				_monthly(world, a, by_war)
	_month_end(world, by_war)


## Ход одной войны (раз в месяц): приказы, снабжение, дух, осада. Движение и
## битвы — каждые сутки (_daily): армии сходятся на карте и бьются там, где встретились.
func _war_turn(world: World, war: War, by_war: Dictionary, _day: int, monthly: bool) -> void:
	var list: Array = _of_war(war.id)
	if list.is_empty():
		return
	if monthly:
		_count_wars(world)
		for a in list:
			if a.alive:
				_monthly(world, a, by_war)
	var by_region := {}
	for a in list:
		# Отступающие и плывущие осаде не мешают.
		if a.alive and a.kind == &"land" and a.state != &"retreat" and a.state != &"home" and a.region >= 0 and not a.at_sea(world):
			if by_region.has(a.region):
				by_region[a.region].append(a)
			else:
				by_region[a.region] = [a]
	_siege_day(world, war, by_region)


func _month_end(world: World, by_war: Dictionary) -> void:
	if world.day != 0:
		return
	_naval_month(world, by_war)
	PirateSystem.tick_month(world)
	if world.month == 0:
		generals_yearly(world)
	compact(world)


## У каждого участника войны — по армии (и флоту, если есть гавань); вышедшие из войны — идут домой.
func _ensure_armies(world: World, war: War) -> void:
	var members := war.attackers + war.defenders
	var have := {}
	var changed := _of_war(war.id).is_empty()
	for a in _of_war(war.id):
		if not a.alive:
			continue
		if not world.nations[a.nation].alive:
			disband(world, a)
			changed = true
			continue
		if not members.has(a.nation):
			_go_home(world, a)  # вышли из войны — домой
			changed = true
			continue
		have[Vector2i(a.nation, 0 if a.kind == &"land" else 1)] = true
	if war.siege_side == 0:
		_count_wars(world)
		var pa := _side_power(world, war, 1)
		var pd := _side_power(world, war, -1)
		war.siege_side = 1 if pa >= pd * 0.8 else -1
		wars._pick_target(world, war, war.siege_side)
	elif war.siege_region < 0 or not wars._is_valid_target(world, war, war.siege_region, war.siege_side):
		wars._pick_target(world, war, war.siege_side)
		war.siege_progress = 0.0
		update_siege_rate(world, war)
		changed = changed or war.siege_landing
	# Состав сил (кто в поле, отряды союзников) — раз в квартал или при переменах.
	if not changed and (world.month + war.id) % 3 != 1:
		return
	_count_wars(world)
	for side in [1, -1]:
		var side_members := war.members(side)
		var leader := -1
		for m in side_members:
			if world.nations[m].alive and (leader < 0 or world.nations[m].army > world.nations[leader].army):
				leader = m
		if leader < 0:
			continue
		var lead_army := world.nations[leader].army
		# Второй в поле — сильнейший крупный союзник; уже стоящий в поле держится,
		# пока не станет заметно слабее соперника (без пересоздания армий каждый месяц).
		var second := -1
		for m in side_members:
			var n := world.nations[m]
			if m == leader or not n.alive or n.army < MIN_ARMY or n.army < lead_army * MINOR_ALLY:
				continue
			var k := 1.25 if have.has(Vector2i(m, 0)) else 1.0
			if second < 0 or n.army * k > world.nations[second].army * (1.25 if have.has(Vector2i(second, 0)) else 1.0):
				second = m
		var allied := 0.0
		for m in side_members:
			var n := world.nations[m]
			if not n.alive:
				continue
			if m != leader and m != second:
				if n.army >= MIN_ARMY:
					allied += _power_of(n) / maxf(1.0, float(_war_count.get(m, 1))) * ALLIED_SHARE
				continue
			if n.army < MIN_ARMY:
				continue
			if not have.has(Vector2i(m, 0)):
				_cache_new(create(world, n, war.id, &"land"))
			# Флоты — только в войнах с десантом (морской фронт): там они высаживают и перехватывают.
			if m == leader and war.siege_landing and not have.has(Vector2i(m, 1)) and _has_port_cached(world, m):
				_cache_new(create(world, n, war.id, &"fleet"))
		for a in _of_war(war.id):
			if not a.alive or war.side_of(a.nation) != side:
				continue
			if a.state == &"home":
				continue
			if a.nation != leader and (a.nation != second or a.kind != &"land"):
				_go_home(world, a)
			elif a.kind == &"land":
				a.allied = allied if a.nation == leader else 0.0


## Мощь стороны (как WarSystem._side_power, но число войн — из кэша хода).
func _side_power(world: World, war: War, side: int) -> float:
	var total := 0.0
	for m in war.members(side):
		total += _power_of(world.nations[m]) / maxf(1.0, float(_war_count.get(m, 1)))
	return total


func _power_of(n: Nation) -> float:
	if not _power.has(n.id):
		_power[n.id] = n.power()
	return _power[n.id]


func _count_wars(world: World) -> void:
	if not _war_count.is_empty():
		return
	for w in world.diplomacy.wars:
		for m in w.attackers:
			_war_count[m] = _war_count.get(m, 0) + 1
		for m in w.defenders:
			_war_count[m] = _war_count.get(m, 0) + 1


func _cache_new(a: Army) -> void:
	if _war_armies.has(a.war):
		_war_armies[a.war].append(a)
	else:
		_war_armies[a.war] = [a]


func _of_war(war_id: int) -> Array:
	return _war_armies.get(war_id, [])


func _has_port_cached(world: World, nation_id: int) -> bool:
	if not _ports.has(nation_id):
		_ports[nation_id] = wars._has_port(world, PackedInt32Array([nation_id]))
	return _ports[nation_id]


## Раз в месяц: доля сил, снабжение, дух, приказ (куда идти).
func _monthly(world: World, a: Army, by_war: Dictionary) -> void:
	if a.kind == &"pirates":
		return
	var nation := world.nations[a.nation] if a.nation >= 0 else null
	if nation == null or not nation.alive:
		disband(world, a)
		return
	var war: War = by_war.get(a.war, null)
	if a.state == &"home" or (a.war >= 0 and war == null):
		return  # идёт домой (_daily)
	if a.war < 0 and world.year - a.created_year > 5:
		disband(world, a)
		return
	a.share = 1.0 / maxf(1.0, float(_war_count.get(a.nation, 1)))
	if a.kind == &"fleet":
		if war != null:
			_fleet_orders(world, a, war)
		return
	_supply(world, a, war)
	var base := _base_morale(world, nation)
	if a.general >= 0:
		base += float(world.generals[a.general].skill) * 0.15
	a.morale = clampf(lerpf(a.morale, base, 0.15), 0.05, 1.0)
	if war != null and a.state != &"retreat" and a.state != &"muster" and not a.at_sea(world):
		_orders(world, a, war)


func _supply(world: World, a: Army, war: War) -> void:
	var side := war.side_of(a.nation) if war != null else 0
	var region := world.regions[a.region]
	var ctrl := region.controller()
	var delta := SUPPLY_HOME
	if not _friendly(a, war, side, ctrl):
		delta = SUPPLY_DEEP
		for nb in region.neighbors:
			if _friendly(a, war, side, world.regions[nb].controller()):
				delta = SUPPLY_NEAR
				break
		if delta == SUPPLY_DEEP and _road_between_any(world, a.region, region.neighbors):
			delta = SUPPLY_NEAR
		# Враг перерезает пути: его армия рядом, а своих земель рядом нет.
		if delta == SUPPLY_DEEP and war != null:
			for e in _of_war(war.id):
				if e.kind == &"land" and war.side_of(e.nation) == -side and region.neighbors.has(e.region):
					delta += SUPPLY_CUT
					break
	a.supply = clampf(a.supply + delta, 0.0, 1.0)
	if a.supply < 0.5:
		var n := world.nations[a.nation]
		n.army = maxf(0.0, n.army - n.army * a.share * ATTRITION * (1.0 - a.supply) * 2.0)
		a.morale = maxf(0.05, a.morale - 0.03)


static func _friendly(a: Army, war: War, side: int, o: int) -> bool:
	return o == a.nation or (war != null and o >= 0 and side != 0 and war.side_of(o) == side)


func _road_between_any(world: World, rid: int, others: PackedInt32Array) -> bool:
	_refresh_roads(world)
	for o in others:
		if _road_pairs.has(Vector2i(mini(rid, o), maxi(rid, o))):
			return true
	return false


func _refresh_roads(world: World) -> void:
	if _road_tick == world.road_version and _road_world == world.get_instance_id():
		return
	_road_tick = world.road_version
	_road_world = world.get_instance_id()
	_road_pairs.clear()
	for road in world.roads:
		if not road.alive or road.sea:
			continue
		var ra := world.region_of[world.cities[road.a].cell]
		var rb := world.region_of[world.cities[road.b].cell]
		if ra != rb and ra >= 0 and rb >= 0:
			_road_pairs[Vector2i(mini(ra, rb), maxi(ra, rb))] = true


## Приказ армии (раз в месяц): наступающая сторона идёт к осаждаемому городу,
## обороняющаяся — туда же навстречу; посуху не дойти — десант морем из своей
## гавани (если война морская), иначе ждать.
func _orders(world: World, a: Army, war: War) -> void:
	var side := war.side_of(a.nation)
	if side == 0:
		return
	if a.kind == &"fleet":
		_fleet_orders(world, a, war)
		return
	# Цель осады выбирается раз в месяц на войну (_ensure_armies), а не каждой армией.
	var goal := war.siege_region
	if goal < 0:
		goal = _home_region(world, world.nations[a.nation], &"land")
	if goal < 0:
		return
	if a.region == goal and not a.at_sea(world):
		a.target = goal
		a.m.stop()
		a.goal = -1
		a.state = &"siege" if side == war.siege_side else &"idle"
		if a.state == &"siege":
			_log_siege(world, war, a)
		return
	var cell := _goal_cell(world, war, goal, side)
	# Путь пересчитывается, только если цель сменилась (или путь кончился);
	# недостижимую цель не ищем заново каждый месяц.
	if a.target == goal and ((a.m.walking() and a.goal == cell) or a.unreachable == cell):
		return
	a.target = goal
	a.goal = cell
	var ok := false
	var land := Pathfinder.land_path(world, a.cell, cell, MoveDB.profile(&"army"))
	if not land.is_empty():
		a.m.set_path(land)
		ok = true
	elif side == war.siege_side and war.siege_landing and world.regions[goal].coastal:
		# Десант: из своей (союзной) гавани морем к берегу цели.
		ok = MovementSystem.send(world, a.m, cell, war.members(side))
	if ok:
		a.unreachable = -1
		a.state = &"march"
	else:
		a.m.stop()
		a.state = &"idle"
		a.unreachable = cell


## Клетка цели в регионе: город, который осаждают (или центр региона).
func _goal_cell(world: World, war: War, rid: int, side: int) -> int:
	var city := wars._region_city(world, rid, war.members(-side))
	if city == null:
		city = wars._region_city(world, rid, war.members(side))
	return city.cell if city != null else world.regions[rid].center


## Флот: в морской войне — к берегу осаждаемого края (прикрыть десант), иначе у своей гавани.
func _fleet_orders(world: World, a: Army, war: War) -> void:
	var goal := -1
	if war.siege_landing and war.siege_region >= 0:
		var landing := Pathfinder.landing_cell(world, _goal_cell(world, war, war.siege_region, war.side_of(a.nation)))
		if landing >= 0:
			goal = Pathfinder.water_next_to(world, landing)
	if goal < 0:
		var home := _home_cell(world, world.nations[a.nation], &"fleet")
		goal = Pathfinder.water_next_to(world, home) if home >= 0 else -1
	if goal < 0 or goal == a.cell or (a.m.walking() and a.m.dest == goal) or a.unreachable == goal:
		return
	if MovementSystem.send(world, a.m, goal):
		a.state = &"march"
		a.unreachable = -1
	else:
		a.unreachable = goal


## Армия встала под стенами крупного города — запись в летописи (раз на осаду).
func _log_siege(world: World, war: War, a: Army) -> void:
	if war == null or war.siege_logged == war.siege_region:
		return
	war.siege_logged = war.siege_region
	var city := wars._region_city(world, war.siege_region, war.members(-war.siege_side))
	if city != null and city.tier() >= 2:
		world.log_event(&"siege", "%s осаждает город %s." % [world.nations[a.nation].short_name, city.name],
				PackedInt32Array(war.attackers + war.defenders))


func _fleet_of(world: World, war: War, nation_id: int) -> Army:
	for f in _of_war(war.id):
		if f.kind == &"fleet" and f.nation == nation_id:
			return f
	return null


# ---------------------------------------------------------------------------
# Сутки: движение и встречи
# ---------------------------------------------------------------------------

## Каждые сутки: встречи армий врагов (битва там, где сошлись; дозор замечает
## врага издали и идёт навстречу), затем шаг по пути, затем события прихода.
func _daily(world: World) -> void:
	if world.armies.is_empty():
		return
	var day := today(world)
	var by_war := {}
	for war in world.diplomacy.wars:
		by_war[war.id] = war
	# Где стоят сухопутные армии — для узких мест (брод, перевал: одна колонна за раз).
	var occupied := {}
	for a in world.armies:
		if not a.blocked and a.standoff > 0:
			a.standoff = 0
		a.blocked = false
		if a.alive and a.kind == &"land" and a.cell >= 0:
			occupied[a.cell] = a
	_contacts(world, by_war, day)
	for a in world.armies:
		if not a.alive:
			continue
		if a.kind != &"pirates":
			if a.nation < 0 or not world.nations[a.nation].alive:
				disband(world, a)
				continue
			if a.war >= 0 and not by_war.has(a.war) and a.state != &"home":
				_go_home(world, a)
		var am := a.m
		if am.step >= am.path.size() and (a.state == &"siege" or a.state == &"idle"):
			# Стоит (осада, ожидание): только сутки без движения.
			am.prev_cell = am.cell
			am.moved = 0
			am.arrived = false
			continue
		if a.m.walking() and not a.blocked and a.kind == &"land":
			var nxt := a.m.next_cell()
			var other: Army = occupied.get(nxt, null)
			# Затор: по броду или перевалу сейчас идёт другая колонна (стоящую — обходят).
			if other != null and other != a and other.alive and other.m.walking() and narrow(world, nxt):
				a.blocked = true
		if a.m.walking() and not a.blocked:
			var from := a.cell
			MovementSystem.advance(world, a.m)
			if occupied.get(from, null) == a:
				occupied.erase(from)
			occupied[a.cell] = a
		else:
			a.m.prev_cell = a.m.cell
			a.m.moved = 0
			a.m.arrived = false
		if a.cell >= 0 and world.region_of[a.cell] >= 0:
			a.region = world.region_of[a.cell]
		if a.m.stuck > 3:
			# Путь негоден (рельеф изменился) — встать, приказ — в следующий месяц.
			a.m.stop()
			a.goal = -1
			a.unreachable = -1
			if a.state == &"march":
				a.state = &"idle"
		_after_step(world, a, by_war.get(a.war, null), day)


## Что делать армии после шага: сбор кончился, дошла до цели, отступила, вернулась домой, высадилась.
func _after_step(world: World, a: Army, war: War, day: int) -> void:
	match a.state:
		&"home":
			if not a.m.walking() or day >= a.state_until:
				disband(world, a)
		&"muster":
			if day >= a.state_until:
				a.state = &"idle"
				if war != null:
					_orders(world, a, war)
		&"retreat":
			if not a.m.walking() and day >= a.state_until:
				a.state = &"idle"
				if war != null:
					_orders(world, a, war)
		&"march":
			if a.kind == &"land" and war != null and a.m.moved > 0 and a.m.prev_cell >= 0 \
					and not world.map.is_land(a.m.prev_cell) and world.map.is_land(a.cell):
				_landing(world, a, war)
				if not a.alive or a.state != &"march":
					return
			if a.kind == &"land" and war != null and a.m.walking():
				_gates(world, a, war)
			if not a.m.walking():
				if a.kind == &"land" and war != null and a.region == war.siege_region and war.side_of(a.nation) == war.siege_side:
					a.state = &"siege"
					_log_siege(world, war, a)
				else:
					a.state = &"idle"


static var _scout := -1.0


static func _scout_range() -> float:
	if _scout < 0.0:
		_scout = MoveDB.profile(&"army").scout_range
	return _scout


## Встречи армий одной войны: в пределах CONTACT клеток — битва (если пора);
## в пределах дозора — идут навстречу; рано для битвы — стоят, мимо не проходят.
static func _cheb(map: WorldMap, a: int, b: int) -> int:
	if a < 0 or b < 0:
		return 1 << 20
	var pa := map.cell_pos(a)
	var pb := map.cell_pos(b)
	return maxi(absi(pa.x - pb.x), absi(pa.y - pb.y))


func _contacts(world: World, by_war: Dictionary, day: int) -> void:
	var lists := {}
	for a in world.armies:
		if a.alive and a.kind == &"land" and a.war >= 0 and by_war.has(a.war) and a.state != &"home" and a.state != &"muster" \
				and a.cell >= 0 and not a.at_sea(world):
			if lists.has(a.war):
				lists[a.war].append(a)
			else:
				lists[a.war] = [a]
	var contact := world.gd(CONTACT)
	var scout := world.gd(_scout_range())
	var map := world.map
	for wid in lists:
		var list: Array = lists[wid]
		if list.size() < 2:
			continue
		var war: War = by_war[wid]
		var ready := day - war.last_battle >= BATTLE_COOLDOWN
		var fought := false
		for i in list.size():
			var a: Army = list[i]
			if fought or not a.alive:
				break
			var sa := war.side_of(a.nation)
			for j in range(i + 1, list.size()):
				var b: Army = list[j]
				if not b.alive or war.side_of(b.nation) != -sa:
					continue
				var pa := map.cell_pos(a.cell)
				var pb := map.cell_pos(b.cell)
				var d := maxi(absi(pa.x - pb.x), absi(pa.y - pb.y))
				if d <= contact:
					if ready and (a.state != &"retreat" or b.state != &"retreat"):
						_engage(world, war, a, b, list, scout)
						fought = true
						break
					# Рано для новой битвы: стоят друг против друга, мимо не проходят;
					# долгое противостояние — слабейший отходит к своим.
					# После противостояния у сильного — «прорыв» (standoff < 0): идёт мимо.
					for x in [a, b]:
						var ar: Army = x
						if ar.state == &"retreat":
							continue
						if ar.standoff < 0:
							ar.standoff += 1
							continue
						ar.blocked = true
						ar.standoff += 1
					if maxi(a.standoff, b.standoff) >= STANDOFF_DAYS:
						var weak := a if a.fighting_power(world) < b.fighting_power(world) else b
						var strong := b if weak == a else a
						weak.standoff = 0
						strong.standoff = -STANDOFF_DAYS
						strong.blocked = false
						weak.morale = maxf(0.05, weak.morale - 0.05)
						if weak.state != &"retreat":
							_retreat(world, weak)
				elif d <= scout and ready:
					# Дозор заметил врага: обороняющиеся перехватывают, наступающие на марше — тоже.
					for pair in [[a, b], [b, a]]:
						var me: Army = pair[0]
						var foe: Army = pair[1]
						if me.state == &"retreat" or (me.state == &"siege" and war.side_of(me.nation) == war.siege_side):
							continue
						# Путь — заново, только если враг ушёл от прежней цели дальше клетки
						# (иначе — каждые сутки поиск пути на каждую пару в дозоре).
						if not me.m.walking() or _cheb(map, me.m.dest, foe.cell) > world.gd(1):
							# Враг рядом — прямо по суше; не выходит — общий путь.
							var p := Pathfinder.line(world, me.cell, foe.cell, -1)
							if p.is_empty():
								p = Pathfinder.land_path(world, me.cell, foe.cell, MoveDB.profile(&"army"))
							if not p.is_empty():
								me.m.set_path(p)
								me.state = &"march"


## Битва там, где сошлись a и b; к ним присоединяются армии сторон в пределах дозора.
func _engage(world: World, war: War, a: Army, b: Army, list: Array, scout: float) -> void:
	var map := world.map
	var sa := war.side_of(a.nation)
	var side_a: Array[Army] = []
	var side_b: Array[Army] = []
	var pa := map.cell_pos(a.cell)
	for x in list:
		var o: Army = x
		if not o.alive or o.state == &"retreat":
			continue
		var po := map.cell_pos(o.cell)
		if maxi(absi(po.x - pa.x), absi(po.y - pa.y)) > scout and o != a and o != b:
			continue
		if war.side_of(o.nation) == sa:
			side_a.append(o)
		elif war.side_of(o.nation) == -sa:
			side_b.append(o)
	if not side_a.has(a):
		side_a.append(a)
	if not side_b.has(b):
		side_b.append(b)
	# Поле боя — там, где стоит сторона, что держит эту землю (иначе — где стоит a).
	var cell := a.cell
	var ctrl := world.owner[b.cell]
	if ctrl >= 0 and war.side_of(ctrl) == -sa:
		cell = b.cell
	battle(world, war, side_a, side_b, cell)


## Армия на берегу после моря: у врага флот сильнее — разбит у берега и отходит домой.
func _landing(world: World, a: Army, war: War) -> void:
	var side := war.side_of(a.nation)
	var ours := 0.0
	var theirs := 0.0
	for f in world.armies:
		if f.alive and f.kind == &"fleet" and f.war == war.id:
			if war.side_of(f.nation) == side:
				ours += f.fighting_power(world)
			else:
				theirs += f.fighting_power(world)
	var n := world.nations[a.nation]
	var region := world.regions[a.region] if a.region >= 0 else null
	if theirs > 0.0 and world.rng.randf() > (ours + 1.0) / (ours + theirs + 1.0):
		n.army -= n.army * a.share * 0.25
		a.morale = maxf(0.05, a.morale - 0.25)
		world.log_event(&"battle", "Флот врага разбил десант государства %s у берегов региона %s." % [n.short_name, region.name if region != null else "?"],
				PackedInt32Array(war.attackers + war.defenders))
		_retreat(world, a)
		return
	war.siege_landing = true
	if region != null:
		world.ensure_region_name(region)
		world.log_event(&"siege", "%s высаживает десант в регионе %s." % [n.short_name, region.name],
				PackedInt32Array(war.attackers + war.defenders))


## «Враг у ворот»: наступающие подошли к городу, гарнизон и ополчение выходят навстречу.
func _gates(world: World, a: Army, war: War) -> void:
	if war.side_of(a.nation) != war.siege_side or war.siege_region < 0 or war.gates == war.siege_region:
		return
	# Город цели — один на войну за сутки (кэш), а не поиск для каждой армии.
	# Кэш — id города, а не сам город, и только для своего мира: одна Simulation может
	# вести два мира (тесты сохранения), и чужой город менял бы чужую историю.
	if _gate_world != world.get_instance_id():
		_gate_world = world.get_instance_id()
		_gate_city.clear()
	var key := Vector2i(war.id, ArmySystem.today(world))
	if not _gate_city.has(key):
		if _gate_city.size() > 64:
			_gate_city.clear()
		var found: City = wars._region_city(world, war.siege_region, war.members(-war.siege_side))
		_gate_city[key] = found.id if found != null else -1
	var cid: int = _gate_city[key]
	if cid < 0:
		return
	var city := world.cities[cid]
	var pa := world.map.cell_pos(a.cell)
	var pc := world.map.cell_pos(city.cell)
	if maxi(absi(pa.x - pc.x), absi(pa.y - pc.y)) > world.gd(GATES_RANGE):
		return
	war.gates = war.siege_region
	var n := world.nations[a.nation]
	var defender := world.nations[city.nation_id]
	# Ополчение — горожане и стража: держится тем дольше, чем крупнее город и крепче стены.
	var militia := city.population * MILITIA_SHARE * (1.5 if city.buildings.has(&"walls") else 1.0)
	var power := a.fighting_power(world)
	var loss := minf(n.army * a.share * 0.04, militia * 0.6) * clampf(militia / maxf(1.0, power), 0.1, 1.0)
	n.army = maxf(0.0, n.army - loss)
	a.morale = maxf(0.05, a.morale - 0.05 * clampf(militia / maxf(1.0, power), 0.0, 1.0))
	defender.stability = maxf(0.0, defender.stability - 0.01)
	if city.tier() >= 2:
		world.log_event(&"siege", "Враг у ворот: войско государства %s подошло к городу %s — ополчение вышло навстречу." % [n.short_name, city.name],
				PackedInt32Array(war.attackers + war.defenders))


## Война кончилась: армия идёт домой и распускается там (не дольше HOME_DAYS).
func _go_home(world: World, a: Army) -> void:
	a.state = &"home"
	a.state_until = today(world) + HOME_DAYS
	a.goal = -1
	if a.kind == &"pirates":
		return
	var home := _home_cell(world, world.nations[a.nation], a.kind)
	if a.kind == &"fleet" and home >= 0:
		home = Pathfinder.water_next_to(world, home)
	if home < 0 or not MovementSystem.send(world, a.m, home, PackedInt32Array([a.nation])):
		disband(world, a)


# ---------------------------------------------------------------------------
# Битвы и осады
# ---------------------------------------------------------------------------

## Битва армий в клетке cell (там, где они встретились). Логика потерь, счёта и
## осад — как у прежнего генерального сражения, но силы — армий на месте, а
## рельеф поля боя помогает тем, кто держит эту землю.
func battle(world: World, war: War, side_a: Array[Army], side_b: Array[Army], cell: int) -> void:
	var region := world.region_of[cell] if cell >= 0 and world.region_of[cell] >= 0 else side_a[0].region
	var rng := world.rng
	var sa := war.side_of(side_a[0].nation)
	var pa := 0.0
	var pb := 0.0
	for x in side_a:
		pa += x.fighting_power(world)
	for x in side_b:
		pb += x.fighting_power(world)
	# Обороняющимся на своей земле помогает рельеф и знание местности.
	var ctrl := world.regions[region].controller()
	var ground := terrain_bonus(world, cell)
	if ctrl >= 0 and war.side_of(ctrl) == sa:
		pa *= 1.1 * ground
	elif ctrl >= 0 and war.side_of(ctrl) == -sa:
		pb *= 1.1 * ground
	var share := pa / (pa + pb) if pa + pb > 0.0 else 0.5
	var p := clampf(0.5 + (share - 0.5) * 1.4, 0.05, 0.95)
	var a_wins := rng.randf() < p
	var winner_side := sa if a_wins else -sa
	var winners: Array[Army] = side_a if a_wins else side_b
	var losers: Array[Army] = side_b if a_wins else side_a
	var margin := absf(share - 0.5) * 2.0
	war.battles += 1
	war.last_battle = today(world)
	var fallen := 0.0
	var lost_losers := 0.0
	_player_battle(world, winners, losers)
	for x in losers:
		var n := world.nations[x.nation]
		var loss := n.army * x.share * rng.randf_range(0.06, 0.14) * (1.5 if n.race.has_trait(&"cowardly") else 1.0)
		n.army -= loss
		fallen += loss
		lost_losers += loss
		x.morale = maxf(0.05, x.morale - 0.25)
		x.battles += 1
		_retreat(world, x)
		_general_fate(world, x, winners[0].nation)
	for x in winners:
		var n := world.nations[x.nation]
		var loss := n.army * x.share * rng.randf_range(0.02, 0.06)
		n.army -= loss
		fallen += loss
		x.morale = minf(1.0, x.morale + 0.15)
		x.battles += 1
		x.wins += 1
		if n.race.has_trait(&"raise_dead"):
			n.army += fallen * 0.25
		if x.general >= 0:
			var g: Dictionary = world.generals[x.general]
			g.skill = minf(1.0, float(g.skill) + 0.02)
			g.wins = int(g.wins) + 1
	war.casualties += fallen
	war.score += winner_side * (4.0 + 8.0 * rng.randf()) * (0.6 + margin) * BATTLE_SCORE
	HeroSystem.on_battle(world, war, winner_side)
	# Усталость от войны — как от прежнего сражения раз в год, но битв теперь больше.
	for m in war.attackers + war.defenders:
		var n := world.nations[m]
		n.stability = maxf(0.0, n.stability - 0.006 * BATTLE_SCORE)
		n.stock[Goods.GOLD] -= n.army * 0.002 * BATTLE_SCORE
	# Запись для просмотра боя (этап 12.E; без ГСЧ мира).
	var lost_winners := fallen - lost_losers
	BattleLog.battle(world, side_a, side_b, pa, pb, lost_losers if not a_wins else lost_winners,
			lost_winners if not a_wins else lost_losers, a_wins, cell if cell >= 0 else world.regions[region].center)
	world.recent_battles.append({"region": region, "cell": cell, "year": world.year, "month": world.month, "day": world.day,
		"war": war.id, "winner": winners[0].nation, "fallen": fallen})
	while world.recent_battles.size() > RECENT_BATTLES:
		world.recent_battles.remove_at(0)
	var rname := world.regions[region].name if not world.regions[region].name.is_empty() else "безымянного края"
	# В летопись — только крупные или решительные битвы.
	if (margin > 0.6 and fallen > 3000.0) or fallen > 15000.0 or rng.randf() < 0.03:
		world.log_event(&"battle", "Битва в регионе %s: %s одержало победу над %s (%s павших)." % [rname,
			world.nations[winners[0].nation].name, world.nations[losers[0].nation].name, _num(fallen)],
			PackedInt32Array(war.attackers + war.defenders))
	# Победитель перехватывает инициативу.
	if war.siege_side != winner_side or not wars._is_valid_target(world, war, war.siege_region, winner_side):
		var old_target := war.siege_region
		war.siege_side = winner_side
		war.siege_progress = 0.0
		wars._pick_target(world, war, winner_side)
		update_siege_rate(world, war)
		for x in winners:
			_orders(world, x, war)


static func _num(v: float) -> String:
	if v >= 1000.0:
		return "%d тыс." % roundi(v / 1000.0)
	return str(roundi(v))


## Узкое место: брод (река без моста-дороги) или горный перевал — проходит одна колонна за раз.
static func narrow(world: World, cell: int) -> bool:
	if cell < 0:
		return false
	var map := world.map
	if map.biome[cell] == Biome.MOUNTAINS:
		return true
	return map.river[cell] > 0 and not MovementSystem.on_road(world, cell)


## Помощь рельефа обороняющимся на поле боя: холмы и горы, лес, болото, река (брод).
static func terrain_bonus(world: World, cell: int) -> float:
	if cell < 0:
		return 1.0
	var k := 1.0
	match world.map.biome[cell]:
		Biome.HILLS, Biome.MOUNTAINS:
			k = 1.15
		Biome.FOREST, Biome.JUNGLE:
			k = 1.08
		Biome.SWAMP:
			k = 1.05
	if world.map.river[cell] > 0:
		k *= 1.1
	return k


## Разбитая армия отходит к ближайшему своему городу (по карте; её могут настигнуть).
func _retreat(world: World, a: Army) -> void:
	a.state = &"retreat"
	a.state_until = today(world) + RETREAT_DAYS
	a.goal = -1
	var n := world.nations[a.nation]
	var p := world.map.cell_pos(a.cell)
	var best := -1
	var best_d := INF
	for id in n.city_ids:
		var c := world.cities[id]
		var d := Vector2(world.map.cell_pos(c.cell) - p).length_squared()
		if d > 0.0 and d < best_d and Pathfinder.landmass(world, c.cell) == Pathfinder.landmass(world, a.cell):
			best_d = d
			best = c.cell
	if best < 0:
		best = _home_cell(world, n, &"land")
	if best < 0 or not MovementSystem.send(world, a.m, best, PackedInt32Array([a.nation])):
		a.m.stop()


## Герой игрока служит в одной из армий битвы (PlayerWorld решает его судьбу).
func _player_battle(world: World, winners: Array[Army], losers: Array[Army]) -> void:
	var pa := world.player_army
	if world.player < 0 or pa.is_empty():
		return
	for x in winners:
		if x.kind == &"land" and x.war == int(pa.war) and x.nation == int(pa.nation):
			PlayerWorld.on_battle(world, x, true)
			return
	for x in losers:
		if x.kind == &"land" and x.war == int(pa.war) and x.nation == int(pa.nation):
			PlayerWorld.on_battle(world, x, false)
			return


## Судьба полководца разбитой армии: гибель или плен.
func _general_fate(world: World, a: Army, captor: int) -> void:
	if a.general < 0:
		return
	var g: Dictionary = world.generals[a.general]
	if int(g.hero) >= 0 and int(g.hero) == world.player:
		return  # судьбу героя игрока решает PlayerWorld.on_battle
	var roll := world.rng.randf()
	if roll < 0.08:
		if int(g.hero) >= 0:
			return  # герой гибнет по своим правилам (HeroSystem.on_battle)
		_general_dies(world, g, "пал в бою")
	elif roll < 0.16:
		g.captured_by = captor
		g.army = -1
		a.general = -1
		world.log_event(&"battle", "Полководец %s попал в плен к государству %s." % [g.name, world.nations[captor].name],
				PackedInt32Array([captor, a.nation]))


## Осада идёт каждый день, пока наступающие стоят у цели, а врагов там нет.
## Скорость (War.siege_rate) пересчитывается раз в месяц и при смене цели.
func _siege_day(world: World, war: War, by_region: Dictionary) -> void:
	if war.siege_region < 0 or war.siege_side == 0:
		return
	var list: Array = by_region.get(war.siege_region, [])
	if list.is_empty():
		return
	var besiegers := false
	for x in list:
		var a: Army = x
		if a.war != war.id:
			continue
		var s := war.side_of(a.nation)
		if s == -war.siege_side:
			return  # защитники на месте — сначала битва
		if s == war.siege_side and a.state == &"siege":
			besiegers = true
	if not besiegers:
		return
	war.siege_progress += war.siege_rate * PERIOD
	if war.siege_progress >= 1.0:
		if wars._is_valid_target(world, war, war.siege_region, war.siege_side):
			wars._capture(world, war, world.regions[war.siege_region], war.siege_side)
		war.siege_progress = 0.0
		# Сразу следующая цель — армии не уходят домой до месячного приказа.
		wars._pick_target(world, war, war.siege_side)
		update_siege_rate(world, war)


## Дневная скорость осады: перевес сил, оборона региона, подкоп, десант.
func update_siege_rate(world: World, war: War) -> void:
	war.siege_rate = 0.0
	if war.siege_region < 0 or war.siege_side == 0 or not wars._is_valid_target(world, war, war.siege_region, war.siege_side):
		return
	var winner := war.siege_side
	_count_wars(world)
	var pa := _side_power(world, war, winner)
	var pd := _side_power(world, war, -winner)
	var margin := clampf((pa / maxf(1.0, pa + pd) - 0.5) * 2.0, 0.0, 1.0)
	var region := world.regions[war.siege_region]
	var target_city := wars._region_city(world, war.siege_region, war.members(-winner))
	var defense := wars._city_defense(world, region, target_city)
	var attacker := world.nations[war.leader(winner)]
	var speed := (0.35 + 0.5 * margin) * attacker.effect(&"siege_mult")
	if UndergroundSystem.sapping(world, war.members(winner), war.siege_region):
		speed *= UndergroundSystem.SAP_SIEGE
	# Дорога к осаждаемому городу от города наступающих — подвоз и переброска войск.
	if target_city != null:
		for rid in world.city_roads.get(target_city.id, PackedInt32Array()):
			var road := world.roads[rid]
			if road.alive and not road.sea and war.members(winner).has(world.cities[road.other(target_city.id)].nation_id):
				speed *= 1.25
				break
	if war.siege_landing:
		speed *= 0.6 * attacker.effect(&"naval_mult") * (1.25 if wars._has_building(world, war.members(winner), &"shipyard") else 1.0)
	war.siege_rate = speed / (1.0 + defense) / SIEGE_DAYS


## Раз в месяц: морские бои флотов и блокада портов.
func _naval_month(world: World, by_war: Dictionary) -> void:
	var blockaded := {}
	for wid in by_war:
		var war: War = by_war[wid]
		var power := {1: 0.0, -1: 0.0}
		var fleets := {1: [], -1: []}
		for f in _of_war(war.id):
			if f.kind != &"fleet":
				continue
			var s := war.side_of(f.nation)
			if s == 0:
				continue
			power[s] += f.fighting_power(world)
			fleets[s].append(f)
		if power[1] > 0.0 and power[-1] > 0.0 and world.rng.randf() < 0.25:
			var p: float = power[1] / (power[1] + power[-1])
			var win := 1 if world.rng.randf() < p else -1
			for f in fleets[-win]:
				var n := world.nations[(f as Army).nation]
				n.army -= n.army * (f as Army).share * FLEET_SHARE * 0.3
			war.score += win * 3.0
			if world.rng.randf() < 0.35:
				world.log_event(&"battle", "Морское сражение: флот государства %s одолел флот государства %s." % [
					world.nations[(fleets[win][0] as Army).nation].short_name, world.nations[(fleets[-win][0] as Army).nation].short_name],
					PackedInt32Array(war.attackers + war.defenders))
		# Блокада: сильный флот запирает порты слабой стороны.
		for s in [1, -1]:
			if power[s] > 0.0 and power[s] > power[-s] * 1.5:
				for m in war.members(-s):
					blockaded[m] = true
	for n in world.nations:
		if not n.alive or (not blockaded.has(n.id) and not n.effect_sources.has(&"blockade")):
			continue
		var on := blockaded.has(n.id) and _has_port_cached(world, n.id)
		if on and not n.effect_sources.has(&"blockade"):
			n.set_effects(&"blockade", {&"trade_mult": 0.75})
		elif not on and n.effect_sources.has(&"blockade"):
			n.set_effects(&"blockade", {})


## Раз в год: распущенные армии забываются; id живых пересчитываются (ссылки
## полководцев на армии обновляются).
static func compact(world: World) -> void:
	var keep: Array[Army] = []
	var remap := {}
	for a in world.armies:
		if a.alive:
			remap[a.id] = keep.size()
			a.id = keep.size()
			keep.append(a)
	if keep.size() == world.armies.size():
		return
	world.armies = keep
	for g in world.generals:
		var old := int(g.army)
		g.army = remap.get(old, -1) if old >= 0 else -1
