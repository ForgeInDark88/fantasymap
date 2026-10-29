class_name BattleLog
## Журнал столкновений (этап 12.E): записи битв, поединков и встреч для значков
## на карте и просмотра (ui/battle_viewer.gd). Только запись — без ГСЧ мира:
## журнал не меняет историю. Хранятся последние записи — у каждого вида свой
## предел (встречи не вытесняют битвы), всего не больше LIMIT (и в сохранении).

const LIMIT := 400
const KIND_LIMIT := {&"battle": 200, &"duel": 100, &"meeting": 100}


static func _base(world: World, kind: StringName, cell: int) -> BattleRecord:
	var r := BattleRecord.new()
	world.battle_serial += 1
	r.id = world.battle_serial
	r.kind = kind
	r.year = world.year
	r.month = world.month
	r.day = world.day
	r.cell = cell
	r.region = world.region_of[cell] if cell >= 0 else -1
	if cell >= 0:
		r.terrain = BiomeDB.get_def(world.map.biome[cell]).id
		r.river = world.map.river[cell] > 0
	# Зерно пересказа — из seed мира и номера записи (не из ГСЧ мира).
	r.replay_seed = hash("%d:%d" % [world.settings.world_seed if world.settings != null else 0, r.id]) & 0x7fffffff
	return r


static func _push(world: World, r: BattleRecord) -> void:
	world.battle_log.append(r)
	var same := 0
	for x in world.battle_log:
		if x.kind == r.kind:
			same += 1
	if same > int(KIND_LIMIT.get(r.kind, 100)):
		for i in world.battle_log.size():
			if world.battle_log[i].kind == r.kind:
				world.battle_log.remove_at(i)
				break


static func _army_side(world: World, armies: Array[Army], power: float, losses: float) -> Dictionary:
	var a := armies[0]
	var gen := ""
	for x in armies:
		if x.general >= 0 and x.general < world.generals.size():
			gen = str(world.generals[x.general].name)
			break
	return {"nation": a.nation, "name": world.nations[a.nation].short_name, "power": power, "losses": losses,
		"general": gen, "hero": -1}


## Битва армий (ArmySystem.battle): силы сторон, потери, победитель.
static func battle(world: World, side_a: Array[Army], side_b: Array[Army], pa: float, pb: float, la: float, lb: float,
		a_wins: bool, cell: int) -> void:
	var r := _base(world, &"battle", cell)
	r.sides.append(_army_side(world, side_a, pa, la))
	r.sides.append(_army_side(world, side_b, pb, lb))
	r.winner = 0 if a_wins else 1
	r.fallen = la + lb
	_push(world, r)


static func _hero_side(h: Hero) -> Dictionary:
	return {"nation": h.nation_id, "name": h.display_name(), "power": h.power(), "losses": 0.0,
		"general": h.hero_class.display_name, "hero": h.id}


## Поединок героев (HeroSystem.duel).
static func duel(world: World, winner: Hero, loser: Hero, killed: bool) -> void:
	var r := _base(world, &"duel", winner.cell)
	r.sides.append(_hero_side(winner))
	r.sides.append(_hero_side(loser))
	r.winner = 0
	r.killed = killed
	_push(world, r)


## Встреча героев без поединка (HeroRelations.meet): чем кончилась — по связи.
## Номер записи (battle_serial) растёт только для записанных — ГСЧ мира не нужен.
static func meeting(world: World, a: Hero, b: Hero) -> void:
	# В журнал — только встречи, что что-то изменили (дружба или вражда), иначе
	# разговоры у костра вытеснят битвы.
	var bond := a.bond(b.id)
	if absf(bond) <= 0.25:
		return
	var r := _base(world, &"meeting", a.cell)
	r.sides.append(_hero_side(a))
	r.sides.append(_hero_side(b))
	r.outcome = &"friend" if bond > 0.25 else &"rival"
	_push(world, r)


## Записи рядом с клеткой не старше years лет (для значков и клика).
static func recent(world: World, years: int) -> Array[BattleRecord]:
	var res: Array[BattleRecord] = []
	for r in world.battle_log:
		if world.year - r.year <= years:
			res.append(r)
	return res
