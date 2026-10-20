class_name CrisisSystem
extends RefCounted
## Мировые кризисы (data/crises; раз в год для всего мира).
##
## Раз в сотни лет (не раньше CRISIS_GAP лет после прошлого) на мир
## обрушивается кризис: Великая чума, ледниковый век, нашествие из-за края
## мира, пробуждение титана, великая засуха, звёздный дождь, война богов.
## Он идёт стадиями, на каждой — эффекты для всех государств, урожай, гибель
## жителей и множители шансов событий; особое поведение (ледник, Орда, титан,
## звездопад, гнев богов) — ниже. Против Орды и титана народы собирают
## Великий союз (организация с общей обороной).

## Шанс кризиса в год (когда можно) и наименьший промежуток между кризисами.
const CRISIS_CHANCE := 0.005
const CRISIS_GAP := 150
## Нашествие: армия Орды при высадке и подкрепления в год.
const HORDE_ARMY := 60000.0
const HORDE_REINFORCE := 8000.0
## Титан: сила, шаг в год (клетки), радиус разрушения городов.
const TITAN_POWER := 40000.0
const TITAN_STEP := 9.0
const TITAN_RADIUS := 3.0


func tick_year(world: World) -> void:
	var c := world.crisis
	if c.is_empty():
		var since := world.year - world.last_crisis_end
		if since >= CRISIS_GAP and world.rng.randf() < CRISIS_CHANCE:
			var def := _pick(world)
			if def != null:
				start(world, def)
		return
	var def := CrisisDB.find(StringName(c.id))
	if def == null:
		world.crisis = {}
		return
	var stage: int = c.stage
	if world.year - int(c.stage_start) >= def.stage_years[stage]:
		stage += 1
		if stage >= def.stage_years.size():
			finish(world, def)
			return
		c.stage = stage
		c.stage_start = world.year
		world.log_event(&"crisis", "%s: %s." % [def.display_name, def.stage_names[stage].to_lower()])
	_apply_stage(world, def, stage)
	_special(world, def, stage)


func _pick(world: World) -> CrisisDef:
	var options: Array[CrisisDef] = []
	var total := 0.0
	for res in CrisisDB.all():
		var d := res as CrisisDef
		if world.year >= d.min_year:
			options.append(d)
			total += d.weight
	if options.is_empty():
		return null
	var roll := world.rng.randf() * total
	for d in options:
		roll -= d.weight
		if roll <= 0.0:
			return d
	return options[options.size() - 1]


## Начало кризиса (панель Бога — тоже сюда).
static func start(world: World, def: CrisisDef) -> void:
	if not world.crisis.is_empty():
		finish(world, CrisisDB.find(StringName(world.crisis.id)))
	world.crisis = {"id": str(def.id), "stage": 0, "stage_start": world.year, "start": world.year,
		"invader": -1, "titan_cell": -1, "titan_power": 0.0, "titan_name": ""}
	world.count(&"crises")
	world.log_event(&"crisis", def.start_text)
	_begin_special(world, def)
	_apply_stage(world, def, 0)
	if def.unite:
		var union := OrgDB.find_org(&"great_alliance")
		if union != null:
			OrgSystem.try_form(world, union)


## Конец кризиса: эффекты снимаются, Великий союз распадётся сам.
static func finish(world: World, def: CrisisDef) -> void:
	if world.crisis.is_empty():
		return
	world.crisis_history.append({"id": world.crisis.id, "name": def.display_name if def != null else str(world.crisis.id),
		"start": int(world.crisis.start), "end": world.year})
	world.crisis = {}
	world.last_crisis_end = world.year
	world.crisis_harvest = 1.0
	world.crisis_events = {}
	for n in world.nations:
		n.set_effects(&"crisis", {})
	world.count(&"crises_survived")
	if def != null:
		world.count(StringName("survived_" + String(def.id)))
		world.log_event(&"crisis", def.end_text)


static func _apply_stage(world: World, def: CrisisDef, stage: int) -> void:
	var effects: Dictionary = def.stage_effects[stage] if stage < def.stage_effects.size() else {}
	var loss := def.stage_pop_loss[stage] if stage < def.stage_pop_loss.size() else 0.0
	for n in world.nations:
		if not n.alive:
			continue
		var immune := false
		for t in def.immune_traits:
			immune = immune or n.race.has_trait(t)
		n.set_effects(&"crisis", {} if immune else effects)
		if loss > 0.0 and not immune:
			for r in n.pop.size():
				n.pop[r] *= 1.0 - loss
	world.crisis_harvest = def.stage_harvest[stage] if stage < def.stage_harvest.size() else 1.0
	for z in 3:
		world.zone_harvest[z] *= world.crisis_harvest
	world.crisis_events = def.stage_events[stage] if stage < def.stage_events.size() else {}


static func _begin_special(world: World, def: CrisisDef) -> void:
	var rng := world.rng
	match def.special:
		&"invasion":
			var race := RaceDB.get_race(def.invader_race)
			var cell := _edge_landing(world)
			if race == null or cell < 0:
				return
			var horde := GodTools.create_nation(world, race, cell, false)
			if horde == null:
				return
			horde.name = "Орда %s" % horde.short_name
			horde.army = HORDE_ARMY
			horde.stock[Goods.GOLD] = 1500.0
			horde.stock[Goods.METAL] = 800.0
			world.crisis.invader = horde.id
			world.log_event(&"crisis", "%s высаживается в регионе %s." % [horde.name, world.region_label(cell, "у края мира")],
					PackedInt32Array([horde.id]))
			for other in horde.borders.keys():
				world.diplomacy.declare_war(world, horde.id, other, &"invasion")
		&"titan":
			var cell := world.volcanoes[rng.randi_range(0, world.volcanoes.size() - 1)] if not world.volcanoes.is_empty() else _edge_landing(world)
			world.crisis.titan_cell = cell
			world.crisis.titan_power = TITAN_POWER * rng.randf_range(0.8, 1.3)
			world.crisis.titan_name = "Титан %s" % NameGenerator.place_name(RaceDB.all()[rng.randi_range(0, RaceDB.count() - 1)], rng)
			world.log_event(&"crisis", "%s поднимается в регионе %s." % [world.crisis.titan_name, world.region_label(cell, "в диких горах")])
		&"drought":
			for z in 3:
				world.zone_events[z] = {"kind": "drought", "until": world.year + def.stage_years[0] + def.stage_years[1]}


static func _special(world: World, def: CrisisDef, stage: int) -> void:
	var rng := world.rng
	match def.special:
		&"ice":
			# Холод наступает (дрейф климата ускоряется) — и отступает на последней стадии.
			var target := -0.12 if stage < def.stage_years.size() - 1 else 0.0
			world.temp_shift = move_toward(world.temp_shift, target, 0.008)
		&"invasion":
			var horde_id: int = world.crisis.invader
			if horde_id >= 0 and horde_id < world.nations.size():
				var horde := world.nations[horde_id]
				if not horde.alive:
					finish(world, def)
					return
				if stage < def.stage_years.size() - 1:
					horde.army += HORDE_REINFORCE
				for other in horde.borders.keys():
					if world.diplomacy.war_between(horde_id, other) == null and rng.randf() < 0.5:
						world.diplomacy.declare_war(world, horde_id, other, &"invasion")
		&"titan":
			_titan(world, def)
		&"star_fall":
			if stage >= 1:
				for k in rng.randi_range(1, 2):
					_star_strike(world)
		&"gods_war":
			# Гнев небес: держава случайной веры получает божью кару, вражда двух крупнейших вер растёт.
			var alive := world.nations.filter(func(n: Nation) -> bool: return n.alive)
			if not alive.is_empty() and rng.randf() < 0.5:
				var victim: Nation = alive[rng.randi_range(0, alive.size() - 1)]
				victim.stability = maxf(0.0, victim.stability - 0.12)
				world.log_event(&"crisis", "Божья кара обрушилась на государство %s: молнии жгут храмы, народ в смятении." % victim.name,
						PackedInt32Array([victim.id]))
			for faith in world.religions:
				faith.zeal = minf(1.0, faith.zeal + 0.01)


## Титан бредёт к крупнейшему городу и крушит города на пути; сильный герой или армия могут его одолеть.
static func _titan(world: World, def: CrisisDef) -> void:
	var rng := world.rng
	var cell: int = world.crisis.titan_cell
	if cell < 0:
		return
	var map := world.map
	var target: City = null
	for city in world.cities:
		if city.alive and (target == null or city.population > target.population):
			target = city
	var pos := Vector2(map.cell_pos(cell))
	if target != null:
		var goal := Vector2(map.cell_pos(target.cell))
		pos = pos.move_toward(goal, TITAN_STEP)
		var p := Vector2i(roundi(pos.x), roundi(pos.y))
		cell = map.index_of(clampi(p.x, 0, map.width - 1), clampi(p.y, 0, map.height - 1))
		world.crisis.titan_cell = cell
	for city in world.cities:
		if city.alive and Vector2(map.cell_pos(city.cell)).distance_to(Vector2(map.cell_pos(cell))) <= TITAN_RADIUS:
			world.log_event(&"crisis", "%s растоптал город %s." % [world.crisis.titan_name, city.name],
					PackedInt32Array([city.nation_id]) if city.nation_id >= 0 else PackedInt32Array())
			world.destroy_city(city)
	world.scars.append({"cell": cell, "radius": 4.0, "kind": "fire", "until": world.year + 3})
	# Армия хозяина земли бьётся с титаном.
	var o := world.owner[cell]
	var power: float = world.crisis.titan_power
	if o >= 0:
		var n := world.nations[o]
		var hit := n.army * 0.25 * rng.randf_range(0.6, 1.4)
		n.army = maxf(0.0, n.army - power * 0.05)
		power -= hit * 0.3
	# Герой, решившийся на бой, может сразить титана.
	for h in world.wandering_heroes():
		if h.cell >= 0 and world.region_of[h.cell] == world.region_of[cell] and h.dares(power, rng):
			if h.power() * rng.randf_range(0.6, 1.5) > power * rng.randf_range(0.6, 1.2):
				h.add_xp(world, 10.0)
				h.epithet = "Титаноборец"
				h.add_deed(world, "сразил %s" % world.crisis.titan_name)
				world.log_event(&"great", "Герой %s сразил титана — %s пал, и земля перестала дрожать." % [h.display_name(), world.crisis.titan_name])
				finish(world, def)
				return
			world.log_event(&"crisis", "Герой %s бросил вызов титану и погиб." % h.display_name())
			h.die(world)
			break
	world.crisis.titan_power = power
	if power <= 0.0:
		world.log_event(&"great", "Армии смертных повергли титана — %s рухнул." % world.crisis.titan_name)
		finish(world, def)


## Звезда падает: город рядом гибнет (руины), край — в пепле.
static func _star_strike(world: World) -> void:
	var rng := world.rng
	var map := world.map
	for attempt in 30:
		var cell := rng.randi_range(0, map.cell_count() - 1)
		if not map.is_land(cell):
			continue
		var hit := ""
		for city in world.cities:
			if city.alive and not city.is_capital and Vector2(map.cell_pos(city.cell)).distance_to(Vector2(map.cell_pos(cell))) <= 2.5:
				hit = city.name
				world.destroy_city(city)
				break
		world.scars.append({"cell": cell, "radius": 5.0, "kind": "ash", "until": world.year + 8})
		var o := world.owner[cell]
		if o >= 0:
			world.nations[o].stock[Goods.METAL] += 80.0  # небесное железо
		world.log_event(&"crisis", "Звезда упала в регионе %s%s." % [world.region_label(cell, "в диких землях"),
			(" — город %s стёрт с лица земли" % hit) if not hit.is_empty() else ""], PackedInt32Array([o]) if o >= 0 else PackedInt32Array())
		return


## Место высадки у края мира: прибрежная клетка суши у границы карты, по возможности ничья.
static func _edge_landing(world: World) -> int:
	var rng := world.rng
	var map := world.map
	var best := -1
	var best_score := -INF
	for attempt in 300:
		var cell := rng.randi_range(0, map.cell_count() - 1)
		if not map.is_land(cell):
			continue
		var p := map.cell_pos(cell)
		var edge := mini(mini(p.x, map.width - 1 - p.x), mini(p.y, map.height - 1 - p.y))
		var score := -edge + (25.0 if world.owner[cell] < 0 else 0.0) + rng.randf() * 5.0
		if score > best_score:
			best_score = score
			best = cell
	return best


## Множитель шанса события в текущей стадии кризиса.
static func event_mult(world: World, event_id: StringName) -> float:
	return float(world.crisis_events.get(str(event_id), 1.0)) if not world.crisis_events.is_empty() else 1.0
