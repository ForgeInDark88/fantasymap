class_name HeroSystem
extends "res://scripts/sim/systems/hero_great_deeds.gd"
## Герои живут помесячно (каждый в свой день): странствуют по регионам,
## совершают добрые и злые поступки (по своей карме, которая от поступков же
## и меняется), встречают других героев и бьются с ними, присягают
## государствам и воюют за них, уходят со службы, стареют и гибнут — или
## занимают трон. Прославленные герои пытаются совершить великое деяние:
## поднять из пучины остров нагов, открыть источник силы, отворить портал
## в бездну, воздвигнуть чудо света, выковать легендарное оружие. Чаще всего
## это не удаётся. Павшие герои отправляются на суд Судьбы (FateSystem).

## Предел живых героев: BASE + живые государства / PER_NATIONS.
const BASE_LIMIT := 6
const PER_NATIONS := 2
## Потолок живых героев (мир не тонет в героях, когда держав становится много).
const MAX_HEROES := 32
## Великие деяния: шанс в год попытаться (для героя от MIN_GREAT_LEVEL уровня).
const GREAT_DEED_CHANCE := 0.012
const MIN_GREAT_LEVEL := 7
## Сколько встреч с другими героями в месяц успевает герой.
const MAX_MEETINGS := 1


## Появление героя в регионе государства. Возвращает героя или null (лимит;
## force — игнорировать лимит, для панели Бога).
static func spawn(world: World, nation: Nation, region: Region, force: bool = false) -> Hero:
	var alive := world.wandering_heroes().size()
	var nations := 0
	for n in world.nations:
		if n.alive:
			nations += 1
	if not force and alive >= mini(MAX_HEROES, BASE_LIMIT + nations / PER_NATIONS):
		return null
	var rng := world.rng
	var people := world.region_majority_race(region, nation.id)
	var race := RaceDB.by_index(people) if people != World.NO_RACE else nation.race
	var cls := PoliticsDB.random_hero_class(race, rng)
	var hero := make_hero(world, race, cls, region.cells[rng.randi_range(0, region.cells.size() - 1)])
	world.ensure_region_name(region)
	hero.add_deed(world, "объявился в регионе %s" % region.name)
	world.log_event(&"hero", "В регионе %s (%s) объявился герой: %s — %s, %s, %s." % [
		region.name, nation.short_name, hero.name, race.display_name.to_lower(),
		hero.hero_class.display_name.to_lower(), hero.alignment_name()], PackedInt32Array([nation.id]))
	return hero


## Новый герой в клетке (имя — сгенерированное или name): возраст, карма, ум
## по расе и классу; добавляется в мир странником.
static func make_hero(world: World, race: RaceDef, cls: HeroClassDef, cell: int, name: String = "") -> Hero:
	var rng := world.rng
	var hero := Hero.new()
	hero.id = world.heroes.size()
	hero.race = race
	hero.race_id = race.id
	hero.hero_class = cls
	hero.name = name if not name.is_empty() else NameGenerator.unique(world.used_names, NameGenerator.person_name.bind(race, rng))
	hero.born_year = world.year
	hero.karma = clampf(cls.karma + rng.randf_range(-0.45, 0.45) - (0.5 if race.has_trait(&"demonic") else 0.0), -1.0, 1.0)
	if race.lifespan <= 0:
		hero.age = rng.randi_range(30, 300)
		hero.max_age = hero.age + rng.randi_range(200, 600)
	else:
		hero.age = int(race.lifespan * rng.randf_range(0.22, 0.4))
		hero.max_age = int(race.lifespan * rng.randf_range(0.8, 1.1))
	hero.level = rng.randi_range(1, 3)
	hero.intellect = clampf(cls.intellect + rng.randf_range(-0.25, 0.25), 0.0, 1.0)
	hero.cell = cell
	hero.move_in = rng.randi_range(1, 4)
	world.heroes.append(hero)
	world.add_wandering(hero)
	return hero


## Каждый герой действует раз в месяц — в «свой» день.
func tick_day(world: World) -> void:
	# Сила героев в армиях — раз в месяц (уровни растут медленно).
	if world.day == 0:
		_update_power(world)
	var acting := world.heroes_acting_on(world.day)
	if acting.is_empty():
		return
	for hero: Hero in acting:
		if not hero.alive or hero.is_ruler:
			continue
		if hero.id == world.player:
			PlayerSystem.tick_month(world, hero)
			continue
		if hero.id % Simulation.MONTHS == world.month:
			_yearly(world, hero)
		if not hero.alive:
			continue
		# Дорога учит: немного опыта каждый месяц.
		hero.add_xp(world, 0.1)
		hero.move_in -= 1
		if hero.move_in <= 0:
			_move(world, hero)
		# Дошёл до цели: потерянный предмет — подобрать, пустой трон — бой со стражем сразу.
		if hero.goal_cell >= 0 and world.region_of[hero.cell] == world.region_of[hero.goal_cell]:
			if hero.artifact_id >= 0 or not ArtifactSystem.try_pick_up(world, hero):
				_throne_attempt(world, hero)
	# Встречи: действующий герой встречает любого героя в своём регионе.
	var wandering := world.wandering_heroes()
	var region_of := world.region_of
	var met: Array[Hero] = []
	for hero: Hero in acting:
		# Встречи — раз в два месяца (каждый герой в свои месяцы).
		if not hero.alive or hero.is_ruler or hero.cell < 0 or (world.month + hero.id) % 2 != 0:
			continue
		var rid := region_of[hero.cell]
		met.clear()
		for other in wandering:
			if other.cell < 0 or region_of[other.cell] != rid or other == hero or not other.alive or other.is_ruler:
				continue
			if other.id % Simulation.DAYS == world.day and other.id < hero.id:
				continue  # пара уже рассмотрена
			# Супруги и спутники по отряду и так вместе — просто крепнет связь.
			if hero.spouse == other.id or hero.party_leader == other.id or other.party_leader == hero.id:
				hero.add_bond(other, 0.02)
				continue
			met.append(other)
		# В людном краю за месяц успеваешь толком поговорить лишь с немногими.
		# Кровника из виду не упускают.
		while met.size() > MAX_MEETINGS:
			var i := world.rng.randi_range(0, met.size() - 1)
			if met[i].id == hero.vendetta or met[i].vendetta == hero.id:
				i = (i + 1) % met.size()
			met.remove_at(i)
		for other in met:
			if not hero.alive or not other.alive:
				continue
			var where := world.region_label(hero.cell, "диких землях")
			# Герой игрока сам решает, как быть со встречным.
			if world.player >= 0 and (hero.id == world.player or other.id == world.player):
				var me := hero if hero.id == world.player else other
				PlayerSystem.encounter(world, me, other if me == hero else hero, world.rng.randf() < _duel_chance(world, hero, other))
				continue
			if world.rng.randf() < _duel_chance(world, hero, other):
				duel(world, hero, other, where)
				if not hero.alive:
					break
			elif world.rng.randf() < 0.5:
				HeroRelations.meet(world, hero, other, where)


## Годовые дела героя: возраст, служба, поступки, великие деяния, трон.
func _yearly(world: World, hero: Hero) -> void:
	var rng := world.rng
	hero.age += 1
	if hero.age > hero.max_age:
		world.log_event(&"hero", "Умер от старости герой %s (%s), прославленный %d деяниями." % [
			hero.display_name(), hero.hero_class.display_name.to_lower(), hero.deeds.size()], PackedInt32Array())
		hero.die(world)
		return
	HeroRelations.yearly(world, hero)
	if hero.nation_id >= 0:
		var n := world.nations[hero.nation_id]
		# Слабому или проигрывающему государству служить невыгодно; злодеи предают чаще.
		var leave := 0.02 + (0.12 if n.stability < 0.3 else 0.0) + maxf(0.0, -hero.karma) * 0.05
		if not n.alive or rng.randf() < leave:
			var old_name := n.short_name
			hero.leave_service(world)
			hero.add_deed(world, "покинул службу государству %s" % old_name)
			world.log_event(&"hero", "Герой %s покинул службу государству %s." % [hero.display_name(), old_name],
					PackedInt32Array([n.id]))
			return
	if rng.randf() < 0.6:
		_deed(world, hero)
	if not hero.alive:
		return
	RuinSystem.hero_explore(world, hero)
	if not hero.alive:
		return
	ArtifactSystem.hero_yearly(world, hero)
	LineageSystem.hero_yearly(world, hero)
	OrderSystem.hero_yearly(world, hero)
	GodSystem.hero_yearly(world, hero)
	if not hero.alive:
		return
	if hero.level >= MIN_GREAT_LEVEL and rng.randf() < GREAT_DEED_CHANCE * (2.0 if hero.level >= 12 else 1.0):
		_great_deed(world, hero)
		return
	# Слухи о проклятом троне манят честолюбцев (и злодеев — сильнее). Но идёт
	# лишь тот, кто считает, что одолеет стража: умный оценивает трезво и ждёт,
	# пока окрепнет, глупец недооценивает чудовище и идёт на смерть.
	if hero.goal_cell < 0 and hero.level >= 4 and hero.artifact.is_empty():
		var thrones := world.active_landmarks(&"throne")
		if not thrones.is_empty() and rng.randf() < 0.15 + maxf(0.0, -hero.karma) * 0.2:
			var throne := thrones[rng.randi_range(0, thrones.size() - 1)]
			if hero.dares(throne.guardian, rng):
				hero.goal_cell = throne.cell
				hero.thought = "Иду к трону «%s»: страж мне по силам." % throne.name
				hero.add_deed(world, "отправился к пустому трону «%s»" % throne.name)
			else:
				hero.thought = "Трон «%s» манит, но страж пока сильнее меня. Надо окрепнуть." % throne.name
	var owner := world.owner[hero.cell]
	if hero.nation_id < 0 and hero.alive and owner >= 0:
		var n := world.nations[owner]
		var welcome := 1.5 if n.race == hero.race else maxf(0.0, n.race.relation_to(hero.race) + 0.3)
		if n.race.has_trait(&"demonic") != hero.race.has_trait(&"demonic"):
			welcome = 0.0
		if rng.randf() < hero.hero_class.loyalty * 0.25 * welcome:
			hero.nation_id = owner
			n.hero_ids.append(hero.id)
			hero.add_deed(world, "присягнул государству %s" % n.name)
			world.log_event(&"hero", "Герой %s (%s, %s) присягнул государству %s." % [
				hero.display_name(), hero.race.display_name.to_lower(), hero.hero_class.display_name.to_lower(), n.name],
					PackedInt32Array([owner]))


# ---------------------------------------------------------------------------
# Перемещение и поединки
# ---------------------------------------------------------------------------


## Странники бродят по соседним регионам (или идут к цели), слуги государства
## идут к осаждённым регионам или держатся своих земель.
func _move(world: World, hero: Hero) -> void:
	var rng := world.rng
	# К цели идут без остановок, остальные — не спеша.
	hero.move_in = 1 if hero.goal_cell >= 0 else rng.randi_range(2, 6)
	var target_region := -1
	# Отряд и супруги держатся вместе; мститель идёт за врагом.
	if hero.party_leader >= 0 and world.heroes[hero.party_leader].alive:
		hero.cell = world.heroes[hero.party_leader].cell
		return
	if hero.spouse >= 0 and world.heroes[hero.spouse].alive and rng.randf() < 0.7:
		hero.cell = world.heroes[hero.spouse].cell
		return
	if hero.vendetta >= 0 and world.heroes[hero.vendetta].alive and hero.goal_cell < 0:
		hero.cell = world.heroes[hero.vendetta].cell if rng.randf() < 0.3 else hero.cell
	if hero.ally_nation >= 0:
		for war in world.diplomacy.wars_of(hero.ally_nation):
			if war.siege_region >= 0:
				var cells := world.regions[war.siege_region].cells
				hero.cell = cells[rng.randi_range(0, cells.size() - 1)]
				return
	if hero.goal_cell >= 0:
		# Путь к цели — прямо через регионы, по шагу за раз.
		var region := world.region_at(hero.cell)
		var goal := Vector2(world.map.cell_pos(hero.goal_cell))
		if region == null or region.neighbors.is_empty() or world.region_of[hero.goal_cell] == region.id:
			hero.cell = hero.goal_cell
			return
		var best := region.neighbors[0]
		for nb in region.neighbors:
			if Vector2(world.map.cell_pos(world.regions[nb].center)).distance_squared_to(goal) \
					< Vector2(world.map.cell_pos(world.regions[best].center)).distance_squared_to(goal):
				best = nb
		target_region = best
		if Vector2(world.map.cell_pos(world.regions[best].center)).distance_to(goal) \
				>= Vector2(world.map.cell_pos(region.center)).distance_to(goal):
			hero.cell = hero.goal_cell  # дальше по суше не пройти — плывёт
			return
	elif hero.nation_id >= 0:
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
	if not cells.is_empty():
		hero.cell = cells[rng.randi_range(0, cells.size() - 1)]


func _duel_chance(world: World, a: Hero, b: Hero) -> float:
	var mod := HeroRelations.duel_modifier(a, b)
	var brothers := OrderSystem.duel_modifier(world, a, b)
	if mod < 0.0 or brothers < 0.0 or a.parents.has(b.id) or b.parents.has(a.id):
		return 0.0
	mod += brothers
	if a.nation_id >= 0 and b.nation_id >= 0:
		if a.nation_id == b.nation_id:
			return 0.0
		if world.diplomacy.war_between(a.nation_id, b.nation_id) != null:
			return 0.3 + mod
	var hostility := maxf(0.0, -a.race.relation_to(b.race) - 0.3)
	# Добро и зло не уживаются в одном краю.
	var moral := maxf(0.0, absf(a.karma - b.karma) - 0.8) * 0.15
	var chance := 0.01 + hostility * 0.08 * (a.hero_class.aggression + b.hero_class.aggression) + moral + mod
	# Умный слабак уклоняется от явно сильнейшего противника.
	for pair in [[a, b], [b, a]]:
		var me: Hero = pair[0]
		if me.wits() > 0.5 and not me.dares(pair[1].power() * 0.7, world.rng):
			chance *= 0.4
	return chance


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
	# Убить злодея — доброе дело, убить праведника — злое.
	winner.karma = clampf(winner.karma - loser.karma * 0.1, -1.0, 1.0)
	var ids := PackedInt32Array()
	for n in [winner.nation_id, loser.nation_id]:
		if n >= 0:
			ids.append(n)
	if winner.vendetta == loser.id:
		winner.vendetta = -1
		winner.thought = "Я отомстил %s. Теперь можно жить дальше." % loser.name
		winner.add_deed(world, "отомстил герою %s" % loser.name)
	# Добрые герои чаще щадят побеждённых.
	if rng.randf() < 0.4 - winner.karma * 0.15:
		winner.add_deed(world, "сразил в поединке героя %s" % loser.name)
		world.log_event(&"hero", "Поединок в регионе %s: %s (%s) сразил героя %s (%s)." % [
			where, winner.display_name(), winner.hero_class.display_name.to_lower(),
			loser.display_name(), loser.hero_class.display_name.to_lower()], ids)
		loser.die(world, winner)
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
	for h in world.wandering_heroes():
		var s1 := war.side_of(h.nation_id) if h.nation_id >= 0 else 0
		var s2 := war.side_of(h.ally_nation) if h.ally_nation >= 0 else 0
		if s1 == 1 or s2 == 1:
			sides[1].append(h)
		if s1 == -1 or s2 == -1:
			sides[-1].append(h)
	for h in sides[winner]:
		h.add_xp(world, 1.0)
	for h in sides[-winner]:
		if rng.randf() < 0.015:
			var nation := world.nations[war.leader(-winner)].short_name
			world.log_event(&"hero", "Герой %s пал в битве за %s." % [h.display_name(), nation], PackedInt32Array([war.leader(-winner)]))
			h.die(world)
	if not sides[1].is_empty() and not sides[-1].is_empty() and rng.randf() < 0.4:
		var a: Hero = sides[1][rng.randi_range(0, sides[1].size() - 1)]
		var b: Hero = sides[-1][rng.randi_range(0, sides[-1].size() - 1)]
		if a.alive and b.alive:
			duel(world, a, b, world.region_label(a.cell, "поле боя"))


func _update_power(world: World) -> void:
	for n in world.nations:
		n.hero_power = 0.0
	for h in world.wandering_heroes():
		if h.alive and not h.is_ruler:
			if h.nation_id >= 0:
				world.nations[h.nation_id].hero_power += h.power()
			if h.ally_nation >= 0 and h.ally_nation != h.nation_id:
				world.nations[h.ally_nation].hero_power += h.power()
