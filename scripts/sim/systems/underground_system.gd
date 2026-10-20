class_name UndergroundSystem
extends RefCounted
## Подземный мир: граф пещер (World.caves) под картой.
##
## Генерация детерминирована seed мира (свой ГСЧ, не трогает ГСЧ мира): входы —
## в горах и холмах, глубже — пещеры, мифриловые и самоцветные жилы, логова
## чудовищ, древние руины; рёбра соединяют ближайшие узлы соседних глубин.
## Подземные народы (дворфы, гоблины, орки, нежить) занимают входы на своей
## земле, пробиваются глубже, сражаясь с чудовищами, строят подземные города
## (пропитание и престиж), добывают жилы, исследуют руины (знания и золото).
## Воюющие соседи бьются за пещеры; подземный ход под осаждённый регион
## ускоряет осаду (подкоп); соседство под землёй рождает трения, а у торговых
## партнёров — подземную торговлю. Изредка из глубин вырывается нашествие.

## Подземные народы.
const UNDER_RACES: Array[StringName] = [&"dwarves", &"goblins", &"orcs", &"undead"]
## Раз в сколько лет действует государство под землёй (со сдвигом по id).
const PERIOD := 3
## Доля армии, уходящая в подземные походы.
const ARMY_SHARE := 0.1
## Число входов: один на столько клеток суши; узлов глубже — в столько раз больше.
const LAND_PER_ENTRANCE := 4000
const DEEP_PER_ENTRANCE := 3
## Доходы в год: мифрил — металл и золото, самоцветы — золото; подземный город — пропитание.
const MITHRIL_METAL := 6.0
const MITHRIL_GOLD := 2.0
const GEMS_GOLD := 8.0
const CITY_FOOD := 0.02
## Подземная торговля по ребру между партнёрами (золото в год каждому).
const TUNNEL_TRADE := 3.0
## Шанс в год нашествия из глубин и подкопа под осаждённый регион.
const INVASION_CHANCE := 0.005
const SAP_SIEGE := 1.3
## Предел силы логова на глубину (чудовища плодятся, но не бесконечно).
const MAX_LAIR := 12000.0


## Строит граф пещер по карте и seed мира.
static func generate(world: World) -> void:
	world.caves.clear()
	var map := world.map
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(world.settings.world_seed) + ":underdark")
	var highlands := PackedInt32Array()
	var land := PackedInt32Array()
	for i in map.cell_count():
		if map.is_land(i):
			land.append(i)
			if map.biome[i] == Biome.MOUNTAINS or map.biome[i] == Biome.HILLS:
				highlands.append(i)
	if land.is_empty():
		return
	var entrances := maxi(4, land.size() / LAND_PER_ENTRANCE)
	_scatter(world, rng, highlands if highlands.size() > entrances * 4 else land, entrances, 1, 15.0)
	var deep := entrances * DEEP_PER_ENTRANCE
	var half := deep / 2
	_scatter(world, rng, land, half, 2, 10.0)
	_scatter(world, rng, land, deep - half, 3, 10.0)
	for c in world.caves:
		c.entrance = c.depth == 1
		_assign_kind(c, rng)
		c.name = _cave_name(world, c, rng)
	_connect(world)


static func _scatter(world: World, rng: RandomNumberGenerator, cells: PackedInt32Array, count: int, depth: int, spacing: float) -> void:
	var map := world.map
	var made := 0
	for attempt in count * 30:
		if made >= count:
			break
		var cell := cells[rng.randi_range(0, cells.size() - 1)]
		var p := Vector2(map.cell_pos(cell))
		var ok := true
		for c in world.caves:
			if c.depth == depth and Vector2(map.cell_pos(c.cell)).distance_to(p) < spacing:
				ok = false
				break
		if not ok:
			continue
		var cave := Cave.new()
		cave.id = world.caves.size()
		cave.cell = cell
		cave.depth = depth
		world.caves.append(cave)
		made += 1


static func _assign_kind(c: Cave, rng: RandomNumberGenerator) -> void:
	var roll := rng.randf()
	match c.depth:
		1:
			c.kind = &"cavern" if roll < 0.8 else &"gems"
		2:
			c.kind = &"mithril" if roll < 0.18 else (&"gems" if roll < 0.4 else (&"lair" if roll < 0.6 else &"cavern"))
		_:
			c.kind = &"lair" if roll < 0.45 else (&"ruins" if roll < 0.7 else (&"mithril" if roll < 0.85 else &"cavern"))
	c.monsters = (8000.0 if c.kind == &"lair" else 1500.0) * c.depth * rng.randf_range(0.6, 1.4)


static func _cave_name(world: World, c: Cave, rng: RandomNumberGenerator) -> String:
	var races := RaceDB.all()
	var race: RaceDef = races[rng.randi_range(0, races.size() - 1)]
	var root := NameGenerator.place_name(race, rng)
	match c.kind:
		&"mithril":
			return "Мифриловая жила %s" % root
		&"gems":
			return "Самоцветные залы %s" % root
		&"lair":
			return "Логово %s" % root
		&"ruins":
			return "Руины %s" % root
	return ("Врата %s" if c.entrance else "Пещеры %s") % root


## Рёбра: каждый узел — к 2 ближайшим соседней или той же глубины (до 45 клеток),
## плюс связность (каждый узел — к ближайшему уже связанному).
static func _connect(world: World) -> void:
	var map := world.map
	var caves := world.caves
	for c in caves:
		var p := Vector2(map.cell_pos(c.cell))
		var near: Array = []
		for o in caves:
			if o == c or absi(o.depth - c.depth) > 1:
				continue
			var d := p.distance_to(Vector2(map.cell_pos(o.cell)))
			if d <= 45.0:
				near.append([d, o.id])
		near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for k in mini(2, near.size()):
			_link(world, c.id, near[k][1])
	# Связность: обход в ширину, недостижимые — к ближайшему достижимому.
	var seen := {0: true} if not caves.is_empty() else {}
	var queue: Array = [0] if not caves.is_empty() else []
	while true:
		while not queue.is_empty():
			var id: int = queue.pop_back()
			for nb in caves[id].neighbors:
				if not seen.has(nb):
					seen[nb] = true
					queue.append(nb)
		if seen.size() >= caves.size():
			break
		var best := Vector3(INF, -1, -1)
		for c in caves:
			if seen.has(c.id):
				continue
			for s in seen:
				var d := Vector2(map.cell_pos(c.cell)).distance_to(Vector2(map.cell_pos(caves[s].cell)))
				if d < best.x:
					best = Vector3(d, c.id, s)
		_link(world, int(best.y), int(best.z))
		seen[int(best.y)] = true
		queue.append(int(best.y))


static func _link(world: World, a: int, b: int) -> void:
	if a == b or world.caves[a].neighbors.has(b):
		return
	world.caves[a].neighbors.append(b)
	world.caves[b].neighbors.append(a)


# ---------------------------------------------------------------------------
# Жизнь под землёй
# ---------------------------------------------------------------------------

func tick(world: World, nation: Nation) -> void:
	if world.caves.is_empty() or (world.year + nation.id + 1) % PERIOD != 0:
		return
	var owned := owned_by(world, nation.id)
	nation.tunnel_neighbors = tunnel_neighbors(world, nation.id)
	_income(world, nation, owned)
	if not UNDER_RACES.has(nation.race_id) or nation.army < 500.0:
		return
	var rng := world.rng
	# Занять вход на своей земле или пробиться глубже из своих пещер.
	var targets: Array[Cave] = []
	for c in world.caves:
		if c.owner < 0 and c.entrance and world.owner[c.cell] == nation.id:
			targets.append(c)
	for c in owned:
		for nb in c.neighbors:
			var o := world.caves[nb]
			if o.owner != nation.id and not targets.has(o) and (o.owner < 0 or world.diplomacy.war_between(nation.id, o.owner) != null):
				targets.append(o)
	if not targets.is_empty():
		_expedition(world, nation, targets[rng.randi_range(0, targets.size() - 1)])
	# Подземный город в своей пещере.
	for c in owned:
		if not c.city and c.kind == &"cavern" and nation.stock[Goods.STONE] >= 60.0 and rng.randf() < 0.25:
			c.city = true
			nation.stock[Goods.STONE] -= 60.0
			world.log_event(&"underground", "%s возводит подземный город в глубинах — %s." % [nation.name, c.name], PackedInt32Array([nation.id]))
			break
	_apply_effects(world, nation)


## Поход в пещеру: с чудовищами — бой с ними, с врагом — подземное сражение.
func _expedition(world: World, nation: Nation, c: Cave) -> void:
	var rng := world.rng
	var force := nation.army * ARMY_SHARE * rng.randf_range(0.7, 1.3)
	var ids := PackedInt32Array([nation.id])
	if c.owner >= 0:
		var enemy := world.nations[c.owner]
		ids.append(enemy.id)
		var defense := enemy.army * ARMY_SHARE * rng.randf_range(0.7, 1.3) * (1.3 if c.city else 1.0)
		if force > defense:
			enemy.army -= defense * 0.3
			nation.army -= force * 0.15
			world.log_event(&"underground", "Подземная битва: %s отбивает у государства %s %s." % [nation.short_name, enemy.short_name, c.name], ids)
			c.owner = nation.id
			c.city = c.city and world.rng.randf() < 0.5  # город могут разрушить в бою
		else:
			nation.army -= force * 0.3
		return
	if force > c.monsters:
		nation.army -= c.monsters * 0.1
		c.owner = nation.id
		c.monsters = 0.0
		if c.kind != &"cavern" or c.entrance or rng.randf() < 0.3:
			world.log_event(&"underground", "%s очищает %s от чудовищ и занимает %s." % [nation.name, c.name, c.kind_name()], ids)
		if c.kind == &"ruins" and not c.explored:
			_explore_ruins(world, nation, c)
	else:
		nation.army -= force * 0.4
		c.monsters *= 0.85


func _explore_ruins(world: World, nation: Nation, c: Cave) -> void:
	c.explored = true
	var gold := world.rng.randf_range(100.0, 400.0)
	nation.stock[Goods.GOLD] += gold
	var t: TechDef = null
	for res in TechDB.all():
		if TechSystem.is_available(nation, res as TechDef) and world.rng.randf() < 0.3:
			t = res
			break
	if t != null:
		TechSystem.unlock(world, nation, t, "в древних подземных руинах")
	world.log_event(&"underground", "%s находит в глубинах (%s) сокровища древних — %d золота%s." % [nation.short_name, c.name, roundi(gold),
		(" и знание: %s" % t.display_name.to_lower()) if t != null else ""], PackedInt32Array([nation.id]))


## Доходы подземных владений и торговля по туннелям.
func _income(world: World, nation: Nation, owned: Array[Cave]) -> void:
	var traded := {}
	for c in owned:
		match c.kind:
			&"mithril":
				nation.stock[Goods.METAL] += MITHRIL_METAL * PERIOD
				nation.stock[Goods.GOLD] += MITHRIL_GOLD * PERIOD
			&"gems":
				nation.stock[Goods.GOLD] += GEMS_GOLD * PERIOD
		for nb in c.neighbors:
			var o := world.caves[nb].owner
			if o >= 0 and o != nation.id and nation.trade_partners.has(o) and not traded.has(o):
				traded[o] = true
				nation.stock[Goods.GOLD] += TUNNEL_TRADE * PERIOD


func _apply_effects(world: World, nation: Nation) -> void:
	var cities := 0
	for c in world.caves:
		if c.owner == nation.id and c.city:
			cities += 1
	nation.set_effects(&"underground", {&"food": CITY_FOOD * cities} if cities > 0 else {})


static func owned_by(world: World, nation_id: int) -> Array[Cave]:
	var result: Array[Cave] = []
	for c in world.caves:
		if c.owner == nation_id:
			result.append(c)
	return result


## Раз в год для мира: павшие владельцы теряют пещеры, чудовища плодятся, нашествия.
func tick_year(world: World) -> void:
	var rng := world.rng
	for c in world.caves:
		if c.owner >= 0 and not world.nations[c.owner].alive:
			c.owner = -1
			c.city = false
		if c.owner < 0 and c.kind == &"lair":
			c.monsters = minf(c.monsters * 1.02 + 50.0, MAX_LAIR * c.depth)
	if rng.randf() < INVASION_CHANCE:
		invasion(world)


## Нашествие из глубин: из логова чудовища выходят к ближайшему входу и бьют по его хозяину.
## near — клетка, рядом с которой искать логово (панель Бога), -1 — любое.
static func invasion(world: World, near: int = -1) -> bool:
	var rng := world.rng
	var lairs: Array[Cave] = []
	for c in world.caves:
		if c.kind == &"lair" and c.owner < 0 and c.depth >= 2:
			lairs.append(c)
	if lairs.is_empty():
		return false
	var lair := lairs[rng.randi_range(0, lairs.size() - 1)]
	if near >= 0:
		for c in lairs:
			if Vector2(world.map.cell_pos(c.cell)).distance_to(Vector2(world.map.cell_pos(near))) < Vector2(world.map.cell_pos(lair.cell)).distance_to(Vector2(world.map.cell_pos(near))):
				lair = c
	var gate: Cave = null
	var best := INF
	for c in world.caves:
		if c.entrance and world.owner[c.cell] >= 0:
			var d := Vector2(world.map.cell_pos(c.cell)).distance_to(Vector2(world.map.cell_pos(lair.cell)))
			if d < best:
				best = d
				gate = c
	if gate == null:
		return false
	var victim := world.nations[world.owner[gate.cell]]
	var horde := lair.monsters * rng.randf_range(1.0, 2.0)
	victim.army = maxf(0.0, victim.army - horde * 0.5)
	for r in victim.pop.size():
		victim.pop[r] *= 0.96
	var region := world.region_at(gate.cell)
	if region != null:
		region.unrest += 0.5
	gate.owner = -1
	gate.city = false
	gate.monsters = horde * 0.3
	world.count(&"invasions")
	world.log_event(&"underground", "Нашествие из глубин! Из %s через %s хлынули полчища чудовищ на земли государства %s." % [
		lair.name, gate.name, victim.name], PackedInt32Array([victim.id]))
	return true


## Подкоп: у наступающих есть пещера под осаждённым регионом.
static func sapping(world: World, attackers: PackedInt32Array, region_id: int) -> bool:
	for c in world.caves:
		if c.owner >= 0 and attackers.has(c.owner) and world.region_of[c.cell] == region_id:
			return true
	return false


## Соседи под землёй: государства, чьи пещеры граничат с пещерами nation.
static func tunnel_neighbors(world: World, nation_id: int) -> Dictionary:
	var result := {}
	for c in world.caves:
		if c.owner != nation_id:
			continue
		for nb in c.neighbors:
			var o := world.caves[nb].owner
			if o >= 0 and o != nation_id:
				result[o] = true
	return result
