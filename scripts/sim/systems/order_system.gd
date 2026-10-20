class_name OrderSystem
extends RefCounted
## Ордена и гильдии героев. Прославленный герой основывает орден своего рода
## (по классу); странники близкой натуры вступают, встретив его членов. Члены
## не поднимают оружия друг на друга, учатся быстрее, а державе, где стоит
## обитель, орден приносит пользу (эффекты Nation.effects, источник &"orders").
## Ордена противоположной натуры враждуют: их члены чаще сходятся в поединках.

## Уровень героя-основателя, шанс в год основать, предел живых орденов.
const FOUND_LEVEL := 9
const FOUND_CHANCE := 0.015
const MAX_ORDERS := 8
## Шанс в год вступить в орден, член которого рядом; допуск по натуре.
const JOIN_CHANCE := 0.5
const KARMA_GAP := 0.6
## Род ордена по классу основателя.
const KIND_BY_CLASS := {&"warrior": &"knights", &"paladin": &"knights", &"berserker": &"knights", &"runesmith": &"knights",
	&"mage": &"mages", &"necromancer": &"mages", &"shaman": &"mages",
	&"rogue": &"shadows", &"spy": &"shadows", &"ranger": &"hunters", &"druid": &"hunters", &"cleric": &"priests"}
const KIND_ACC := {&"knights": "рыцарский орден", &"mages": "гильдию магов", &"shadows": "братство теней",
	&"hunters": "гильдию охотников", &"priests": "священный круг"}
const KIND_NAMES := {&"knights": "рыцарский орден", &"mages": "гильдия магов", &"shadows": "братство теней",
	&"hunters": "гильдия охотников", &"priests": "священный круг"}
const NAME_PATTERNS := {&"knights": "Орден %s", &"mages": "Гильдия магов «%s»", &"shadows": "Братство «%s»",
	&"hunters": "Гильдия охотников «%s»", &"priests": "Круг %s"}
## Польза обители державе.
const HALL_EFFECTS := {&"knights": {&"army_mult": 1.04}, &"mages": {&"science_mult": 1.06},
	&"shadows": {&"spy_mult": 1.15}, &"hunters": {&"food": 0.03}, &"priests": {&"stability": 0.03}}


## Годовые дела героя: вступление в орден или основание своего.
static func hero_yearly(world: World, hero: Hero) -> void:
	var rng := world.rng
	if hero.order >= 0:
		if not world.orders[hero.order].alive:
			hero.order = -1
		else:
			hero.add_xp(world, 0.5)  # наставники ордена
			return
	if hero.level >= FOUND_LEVEL and rng.randf() < FOUND_CHANCE and alive_count(world) < MAX_ORDERS:
		found(world, hero)
		return
	if hero.cell < 0 or rng.randf() > JOIN_CHANCE:
		return
	var kind: StringName = KIND_BY_CLASS.get(hero.hero_class.id, &"knights")
	# Узнаёт об ордене от его членов рядом (свой или соседний край), от соратников
	# по службе — или приходит в обитель.
	var rid := world.region_of[hero.cell]
	var near := world.regions[rid].neighbors if rid >= 0 else PackedInt32Array()
	for o in world.orders:
		if not o.alive or o.kind != kind or absf(o.karma - hero.karma) > KARMA_GAP:
			continue
		if o.hall_cell >= 0 and world.region_of[o.hall_cell] == rid:
			join(world, o, hero)
			return
		for m in o.members:
			var mh := world.heroes[m]
			if not mh.alive or mh.cell < 0:
				continue
			var mr := world.region_of[mh.cell]
			if mr == rid or near.has(mr) or (hero.nation_id >= 0 and mh.nation_id == hero.nation_id):
				join(world, o, hero)
				return


static func alive_count(world: World) -> int:
	var k := 0
	for o in world.orders:
		if o.alive:
			k += 1
	return k


## Герой основывает орден (вызывает и панель Бога).
static func found(world: World, hero: Hero) -> HeroOrder:
	if hero.order >= 0 and world.orders[hero.order].alive:
		return null
	var o := HeroOrder.new()
	o.id = world.orders.size()
	o.kind = KIND_BY_CLASS.get(hero.hero_class.id, &"knights")
	var word := NameGenerator.place_name(hero.race, world.rng)
	o.name = NAME_PATTERNS[o.kind] % word
	o.founder = hero.id
	o.leader = hero.id
	o.founded_year = world.year
	o.karma = hero.karma
	o.hall_cell = hero.cell
	if hero.nation_id >= 0 and world.nations[hero.nation_id].capital_city >= 0:
		o.hall_cell = world.cities[world.nations[hero.nation_id].capital_city].cell
	world.orders.append(o)
	join(world, o, hero, false)
	hero.add_deed(world, "основал %s — %s" % [KIND_ACC[o.kind], o.name])
	var owner := world.owner[o.hall_cell] if o.hall_cell >= 0 else -1
	world.log_event(&"order", "Герой %s основал %s — %s; обитель в краю %s." % [hero.display_name(), KIND_ACC[o.kind], o.name,
		world.region_label(o.hall_cell, "диких земель")], PackedInt32Array([owner]) if owner >= 0 else PackedInt32Array())
	world.count(&"orders")
	return o


static func join(world: World, o: HeroOrder, hero: Hero, deed: bool = true) -> void:
	hero.order = o.id
	o.members.append(hero.id)
	o.total += 1
	if deed:
		hero.add_deed(world, "вступил в %s" % o.name)
	for m in o.members:
		if m != hero.id:
			hero.add_bond(world.heroes[m], 0.3)
			world.heroes[m].add_bond(hero, 0.3)


## Сила вражды двух героев по их орденам: −1 — братья (не бьются), 0.2 — враждующие ордена.
static func duel_modifier(world: World, a: Hero, b: Hero) -> float:
	if a.order < 0 or b.order < 0:
		return 0.0
	if a.order == b.order:
		return -1.0
	if absf(world.orders[a.order].karma - world.orders[b.order].karma) > 1.0:
		return 0.2
	return 0.0


## Раз в год: члены и глава, угасание орденов, польза обителей державам.
func tick_year(world: World) -> void:
	if world.orders.is_empty():
		return
	var effects := {}
	for o in world.orders:
		if not o.alive:
			continue
		var living := PackedInt32Array()
		for m in o.members:
			var h := world.heroes[m]
			if h.alive and h.order == o.id:
				living.append(m)
		o.members = living
		if living.is_empty():
			o.alive = false
			o.ended_year = world.year
			world.log_event(&"order", "Пришёл конец: %s (%d—%d гг.) — в нём не осталось ни одного героя." % [o.name, o.founded_year, world.year])
			continue
		if not world.heroes[o.leader].alive or world.heroes[o.leader].order != o.id:
			var best := living[0]
			for m in living:
				if world.heroes[m].level > world.heroes[best].level:
					best = m
			o.leader = best
			world.heroes[best].add_deed(world, "возглавил %s" % o.name)
		var owner := world.owner[o.hall_cell] if o.hall_cell >= 0 else -1
		if owner >= 0:
			var d: Dictionary = effects.get(owner, {})
			for k in HALL_EFFECTS[o.kind]:
				if String(k).ends_with("_mult"):
					d[k] = d.get(k, 1.0) * HALL_EFFECTS[o.kind][k]
				else:
					d[k] = d.get(k, 0.0) + HALL_EFFECTS[o.kind][k]
			effects[owner] = d
	for n in world.nations:
		if n.alive and (effects.has(n.id) or n.effect_sources.has(&"orders_hall")):
			n.set_effects(&"orders_hall", effects.get(n.id, {}))
