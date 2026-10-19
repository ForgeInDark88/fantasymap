class_name HeroSystem
extends RefCounted
## Герои живут помесячно: странствуют по регионам, выполняют подвиги
## (чудовища, сокровища, помощь селениям), встречают других героев и бьются
## с ними, присягают государствам и воюют за них (их сила добавляется
## к военной мощи), уходят со службы, стареют, гибнут — или занимают трон.
## Новые герои приходят событием «Прибытие героя» (data/events).

## Предел живых героев: BASE + живые государства / PER_NATIONS.
const BASE_LIMIT := 4
const PER_NATIONS := 3


## Появление героя в регионе государства. Возвращает героя или null (лимит;
## force — игнорировать лимит, для панели Бога).
static func spawn(world: World, nation: Nation, region: Region, force: bool = false) -> Hero:
	var alive := 0
	var nations := 0
	for h in world.heroes:
		if h.alive and not h.is_ruler:
			alive += 1
	for n in world.nations:
		if n.alive:
			nations += 1
	if not force and alive >= BASE_LIMIT + nations / PER_NATIONS:
		return null
	var rng := world.rng
	var people := world.region_majority_race(region, nation.id)
	var race := RaceDB.by_index(people) if people != World.NO_RACE else nation.race
	var hero := Hero.new()
	hero.id = world.heroes.size()
	hero.race = race
	hero.race_id = race.id
	hero.hero_class = PoliticsDB.random_hero_class(race, rng)
	hero.name = NameGenerator.unique(world.used_names, NameGenerator.person_name.bind(race, rng))
	hero.born_year = world.year
	if race.lifespan <= 0:
		hero.age = rng.randi_range(30, 300)
		hero.max_age = hero.age + rng.randi_range(200, 600)
	else:
		hero.age = int(race.lifespan * rng.randf_range(0.22, 0.4))
		hero.max_age = int(race.lifespan * rng.randf_range(0.8, 1.1))
	hero.level = rng.randi_range(1, 3)
	hero.cell = region.cells[rng.randi_range(0, region.cells.size() - 1)]
	hero.move_in = rng.randi_range(1, 4)
	world.heroes.append(hero)
	hero.add_deed(world, "объявился в регионе %s" % region.name)
	world.log_event(&"hero", "В регионе %s (%s) объявился герой: %s — %s, %s." % [
		region.name, nation.short_name, hero.name, race.display_name.to_lower(), hero.hero_class.display_name.to_lower()],
			PackedInt32Array([nation.id]))
	return hero


func tick_month(world: World) -> void:
	var by_region := {}
	for hero in world.heroes:
		if not hero.alive or hero.is_ruler:
			continue
		if hero.id % Simulation.MONTHS == world.month:
			_yearly(world, hero)
			if not hero.alive:
				continue
		hero.move_in -= 1
		if hero.move_in <= 0:
			_move(world, hero)
		var rid := world.region_of[hero.cell] if hero.cell >= 0 else -1
		if rid >= 0:
			if not by_region.has(rid):
				by_region[rid] = []
			by_region[rid].append(hero)
	# Встречи в одном регионе.
	for rid in by_region:
		var here: Array = by_region[rid]
		if here.size() < 2:
			continue
		for i in here.size():
			for j in range(i + 1, here.size()):
				var a: Hero = here[i]
				var b: Hero = here[j]
				if a.alive and b.alive and world.rng.randf() < _duel_chance(world, a, b):
					duel(world, a, b, world.regions[rid].name)
	_update_power(world)


## Годовые дела героя: возраст, подвиги, служба.
func _yearly(world: World, hero: Hero) -> void:
	var rng := world.rng
	hero.age += 1
	if hero.age > hero.max_age:
		hero.die(world)
		world.log_event(&"hero", "Умер от старости герой %s (%s), прославленный %d подвигами." % [
			hero.display_name(), hero.hero_class.display_name.to_lower(), hero.deeds.size()], PackedInt32Array())
		return
	var owner := world.owner[hero.cell]
	if hero.nation_id >= 0:
		var n := world.nations[hero.nation_id]
		# Слабому или проигрывающему государству служить невыгодно.
		var leave := 0.02 + (0.12 if n.stability < 0.3 else 0.0)
		if not n.alive or rng.randf() < leave:
			var old_name := n.short_name
			hero.leave_service(world)
			hero.add_deed(world, "покинул службу государству %s" % old_name)
			world.log_event(&"hero", "Герой %s покинул службу государству %s." % [hero.display_name(), old_name],
					PackedInt32Array([n.id]))
		return
	# Сам по себе: подвиги и, может быть, присяга.
	if rng.randf() < 0.6:
		_quest(world, hero)
	if hero.alive and owner >= 0:
		var n := world.nations[owner]
		var welcome := 1.5 if n.race == hero.race else maxf(0.0, n.race.relation_to(hero.race) + 0.3)
		if rng.randf() < hero.hero_class.loyalty * 0.25 * welcome:
			hero.nation_id = owner
			n.hero_ids.append(hero.id)
			hero.add_deed(world, "присягнул государству %s" % n.name)
			world.log_event(&"hero", "Герой %s (%s, %s) присягнул государству %s." % [
				hero.display_name(), hero.race.display_name.to_lower(), hero.hero_class.display_name.to_lower(), n.name],
					PackedInt32Array([owner]))


func _quest(world: World, hero: Hero) -> void:
	var rng := world.rng
	var region := world.region_at(hero.cell)
	var where := region.name if region != null else "диких землях"
	var roll := rng.randf()
	if roll < 0.4:
		# Чудовище: опасно, но славно.
		if rng.randf() < 0.07:
			hero.die(world)
			world.log_event(&"hero", "Герой %s погиб в схватке с чудовищем в регионе %s." % [hero.display_name(), where], PackedInt32Array())
			return
		hero.monsters_slain += 1
		hero.add_xp(world, 2.0)
		var dragon := rng.randf() < 0.02
		if dragon:
			hero.epithet = "Драконоборец" if hero.epithet.is_empty() else hero.epithet
			hero.add_xp(world, 4.0)
		elif hero.monsters_slain >= 6 and hero.epithet.is_empty():
			hero.epithet = "Гроза чудовищ"
		hero.add_deed(world, ("сразил дракона" if dragon else "сразил чудовище") + " в регионе " + where)
		if dragon or rng.randf() < 0.15:
			world.log_event(&"hero", "Герой %s %s в регионе %s." % [hero.display_name(), "сразил дракона" if dragon else "избавил от чудовища селения", where],
					PackedInt32Array())
	elif roll < 0.65:
		hero.add_xp(world, 1.0)
		hero.add_deed(world, "нашёл древний клад в регионе " + where)
	elif region != null:
		# Помощь селениям — регион успокаивается.
		region.unrest = maxf(0.0, region.unrest - 0.3)
		hero.add_xp(world, 1.0)
		hero.add_deed(world, "защитил селения региона " + where)


## Перемещение: странники бродят по соседним регионам, слуги государства
## идут к осаждённым регионам или держатся своих земель.
func _move(world: World, hero: Hero) -> void:
	var rng := world.rng
	hero.move_in = rng.randi_range(2, 6)
	var target_region := -1
	if hero.nation_id >= 0:
		for war in world.diplomacy.wars_of(hero.nation_id):
			if war.siege_region >= 0:
				target_region = war.siege_region
				break
		if target_region < 0:
			var n := world.nations[hero.nation_id]
			if n.cells.is_empty():
				return
			hero.cell = n.cells[rng.randi_range(0, n.cells.size() - 1)]
			return
	else:
		var region := world.region_at(hero.cell)
		if region == null or region.neighbors.is_empty():
			return
		target_region = region.neighbors[rng.randi_range(0, region.neighbors.size() - 1)]
	var cells := world.regions[target_region].cells
	hero.cell = cells[rng.randi_range(0, cells.size() - 1)]


func _duel_chance(world: World, a: Hero, b: Hero) -> float:
	if a.nation_id >= 0 and b.nation_id >= 0:
		if a.nation_id == b.nation_id:
			return 0.0
		if world.diplomacy.war_between(a.nation_id, b.nation_id) != null:
			return 0.3
	var hostility := maxf(0.0, -a.race.relation_to(b.race) - 0.3)
	return 0.01 + hostility * 0.08 * (a.hero_class.aggression + b.hero_class.aggression)


## Поединок: побеждает сильнейший (с удачей); проигравший гибнет или бежит.
static func duel(world: World, a: Hero, b: Hero, where: String) -> void:
	var rng := world.rng
	var pa := a.power() * rng.randf_range(0.6, 1.4)
	var pb := b.power() * rng.randf_range(0.6, 1.4)
	var winner := a if pa >= pb else b
	var loser := b if winner == a else a
	winner.kills += 1
	winner.add_xp(world, 1.0 + loser.level * 0.5)
	if winner.kills >= 3 and (winner.epithet.is_empty() or winner.epithet == "Гроза чудовищ"):
		winner.epithet = "Непобедимый"
	var ids := PackedInt32Array()
	for n in [winner.nation_id, loser.nation_id]:
		if n >= 0:
			ids.append(n)
	if rng.randf() < 0.75:
		loser.die(world)
		winner.add_deed(world, "сразил в поединке героя %s" % loser.name)
		world.log_event(&"hero", "Поединок в регионе %s: %s (%s) сразил героя %s (%s)." % [
			where, winner.display_name(), winner.hero_class.display_name.to_lower(),
			loser.display_name(), loser.hero_class.display_name.to_lower()], ids)
	else:
		loser.level = maxi(1, loser.level - 1)
		loser.move_in = 0
		winner.add_deed(world, "одолел героя %s, но тот бежал" % loser.name)
		world.log_event(&"hero", "Поединок в регионе %s: %s одолел героя %s, но тот бежал." % [
			where, winner.display_name(), loser.display_name()], ids)


## Сражение войны: герои сторон набираются опыта, гибнут и вызывают друг друга.
static func on_battle(world: World, war: War, winner: int) -> void:
	var rng := world.rng
	var sides := {1: [], -1: []}
	for side in [1, -1]:
		for m in war.members(side):
			for hid in world.nations[m].hero_ids:
				var h := world.heroes[hid]
				if h.alive:
					sides[side].append(h)
	for h in sides[winner]:
		h.add_xp(world, 1.0)
	for h in sides[-winner]:
		if rng.randf() < 0.04:
			var nation := world.nations[h.nation_id].short_name
			h.die(world)
			world.log_event(&"hero", "Герой %s пал в битве за %s." % [h.display_name(), nation], PackedInt32Array([war.leader(-winner)]))
	if not sides[1].is_empty() and not sides[-1].is_empty() and rng.randf() < 0.4:
		var a: Hero = sides[1][rng.randi_range(0, sides[1].size() - 1)]
		var b: Hero = sides[-1][rng.randi_range(0, sides[-1].size() - 1)]
		if a.alive and b.alive:
			var region := world.region_at(a.cell)
			duel(world, a, b, region.name if region != null else "поле боя")


func _update_power(world: World) -> void:
	for n in world.nations:
		n.hero_power = 0.0
	for h in world.heroes:
		if h.alive and h.nation_id >= 0 and not h.is_ruler:
			world.nations[h.nation_id].hero_power += h.power()
