class_name HeroSystem
extends RefCounted
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
## Великие деяния: шанс в год попытаться (для героя от MIN_GREAT_LEVEL уровня).
const GREAT_DEED_CHANCE := 0.012
const MIN_GREAT_LEVEL := 7


## Появление героя в регионе государства. Возвращает героя или null (лимит;
## force — игнорировать лимит, для панели Бога).
static func spawn(world: World, nation: Nation, region: Region, force: bool = false) -> Hero:
	var alive := world.wandering_heroes().size()
	var nations := 0
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
	hero.karma = clampf(hero.hero_class.karma + rng.randf_range(-0.45, 0.45) - (0.5 if race.has_trait(&"demonic") else 0.0), -1.0, 1.0)
	if race.lifespan <= 0:
		hero.age = rng.randi_range(30, 300)
		hero.max_age = hero.age + rng.randi_range(200, 600)
	else:
		hero.age = int(race.lifespan * rng.randf_range(0.22, 0.4))
		hero.max_age = int(race.lifespan * rng.randf_range(0.8, 1.1))
	hero.level = rng.randi_range(1, 3)
	hero.intellect = clampf(hero.hero_class.intellect + rng.randf_range(-0.25, 0.25), 0.0, 1.0)
	hero.cell = region.cells[rng.randi_range(0, region.cells.size() - 1)]
	hero.move_in = rng.randi_range(1, 4)
	world.heroes.append(hero)
	world.add_wandering(hero)
	world.ensure_region_name(region)
	hero.add_deed(world, "объявился в регионе %s" % region.name)
	world.log_event(&"hero", "В регионе %s (%s) объявился герой: %s — %s, %s, %s." % [
		region.name, nation.short_name, hero.name, race.display_name.to_lower(),
		hero.hero_class.display_name.to_lower(), hero.alignment_name()], PackedInt32Array([nation.id]))
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
		if hero.id % Simulation.MONTHS == world.month:
			_yearly(world, hero)
		if not hero.alive:
			continue
		# Дорога учит: немного опыта каждый месяц.
		hero.add_xp(world, 0.1)
		hero.move_in -= 1
		if hero.move_in <= 0:
			_move(world, hero)
		# Дошёл до цели (пустого трона) — бой со стражем сразу.
		if hero.goal_cell >= 0 and world.region_of[hero.cell] == world.region_of[hero.goal_cell]:
			_throne_attempt(world, hero)
	# Встречи: действующий герой встречает любого героя в своём регионе.
	var wandering := world.wandering_heroes()
	var region_of := world.region_of
	for hero: Hero in acting:
		if not hero.alive or hero.is_ruler or hero.cell < 0:
			continue
		var rid := region_of[hero.cell]
		for other in wandering:
			if other.cell < 0 or region_of[other.cell] != rid or other == hero or not other.alive or other.is_ruler:
				continue
			if other.id % Simulation.DAYS == world.day and other.id < hero.id:
				continue  # пара уже рассмотрена
			var where := world.region_label(hero.cell, "диких землях")
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
# Поступки
# ---------------------------------------------------------------------------

## Добрый или злой поступок — по карме героя. Поступок сдвигает карму.
func _deed(world: World, hero: Hero) -> void:
	var rng := world.rng
	# Натура тянет назад: карма понемногу возвращается к склонности класса.
	hero.karma = lerpf(hero.karma, hero.hero_class.karma, 0.08)
	var evil := rng.randf() < clampf(0.5 - hero.karma * 0.45, 0.05, 0.95)
	if evil:
		_evil_deed(world, hero)
	else:
		_good_deed(world, hero)
	if hero.epithet.is_empty():
		if hero.karma >= 0.85:
			hero.epithet = "Светлый"
		elif hero.karma <= -0.85:
			hero.epithet = "Кровавый"


func _good_deed(world: World, hero: Hero) -> void:
	var rng := world.rng
	var region := world.region_at(hero.cell)
	var where := world.region_label(hero.cell, "диких землях")
	var owner := world.owner[hero.cell]
	var nation := world.nations[owner] if owner >= 0 else null
	var ids := PackedInt32Array([owner]) if owner >= 0 else PackedInt32Array()
	hero.karma = minf(1.0, hero.karma + 0.03)
	var roll := rng.randf()
	if roll < 0.35:
		# Чудовище: опасно, но славно (в отряде и с опытом — безопаснее).
		var risk := (0.035 if hero.level < 4 else 0.015) * (0.5 if hero.party_leader >= 0 else 1.0) \
				* (1.3 - hero.wits() * 0.6)  # умный не лезет на рожон
		if rng.randf() < risk:
			world.log_event(&"hero", "Герой %s погиб в схватке с чудовищем в регионе %s." % [hero.display_name(), where], ids)
			hero.die(world)
			return
		hero.monsters_slain += 1
		hero.add_xp(world, 2.0)
		var dragon := rng.randf() < 0.02
		if dragon:
			hero.add_xp(world, 4.0)
			if hero.epithet.is_empty():
				hero.epithet = "Драконоборец"
		elif hero.monsters_slain >= 6 and hero.epithet.is_empty():
			hero.epithet = "Гроза чудовищ"
		hero.add_deed(world, ("сразил дракона" if dragon else "сразил чудовище") + " в регионе " + where)
		if dragon or rng.randf() < 0.12:
			world.log_event(&"hero", "Герой %s %s в регионе %s." % [hero.display_name(),
				"сразил дракона" if dragon else "избавил от чудовища селения", where], ids)
	elif roll < 0.55 and region != null:
		region.unrest = maxf(0.0, region.unrest - 0.3)
		hero.add_xp(world, 1.0)
		hero.add_deed(world, "защитил селения региона " + where)
	elif roll < 0.7 and nation != null:
		# Исцеление: эпидемия в государстве отступает.
		var healed := false
		for i in range(nation.modifiers.size() - 1, -1, -1):
			if nation.modifiers[i].id == &"plague":
				nation.modifiers.remove_at(i)
				healed = true
		hero.add_xp(world, 1.0)
		hero.add_deed(world, ("остановил чуму" if healed else "исцелял больных") + " в регионе " + where)
		if healed:
			world.log_event(&"hero", "Герой %s остановил чуму в государстве %s." % [hero.display_name(), nation.short_name], ids)
	elif roll < 0.85 and nation != null:
		nation.stock[Goods.FOOD] += nation.population / 1000.0 * 0.3
		nation.stability = minf(1.0, nation.stability + 0.01)
		hero.add_xp(world, 1.0)
		hero.add_deed(world, "накормил голодных в регионе " + where)
	elif nation != null and not nation.city_ids.is_empty():
		var city := world.cities[nation.city_ids[rng.randi_range(0, nation.city_ids.size() - 1)]]
		if not city.buildings.has(&"temple"):
			city.buildings.append(&"temple")
			CitySystem.recompute_building_effects(world, nation)
			hero.add_deed(world, "возвёл храм в городе " + city.name)
			world.log_event(&"hero", "Герой %s возвёл храм в городе %s (%s)." % [hero.display_name(), city.name, nation.short_name], ids)
		else:
			hero.add_deed(world, "нашёл древний клад в регионе " + where)
		hero.add_xp(world, 1.0)
	else:
		hero.add_xp(world, 1.0)
		hero.add_deed(world, "нашёл древний клад в регионе " + where)


func _evil_deed(world: World, hero: Hero) -> void:
	var rng := world.rng
	var region := world.region_at(hero.cell)
	var where := world.region_label(hero.cell, "диких землях")
	var owner := world.owner[hero.cell]
	hero.karma = maxf(-1.0, hero.karma - 0.03)
	if owner < 0:
		hero.add_xp(world, 0.5)
		hero.add_deed(world, "разорил гробницы в регионе " + where)
		return
	var nation := world.nations[owner]
	var ids := PackedInt32Array([owner])
	var roll := rng.randf()
	if roll < 0.35:
		var loot := maxf(0.0, nation.stock[Goods.GOLD]) * 0.05
		nation.stock[Goods.GOLD] -= loot
		hero.add_xp(world, 1.0)
		hero.add_deed(world, "ограбил караван в регионе %s (%d золота)" % [where, roundi(loot)])
		if rng.randf() < 0.15:
			world.log_event(&"hero", "Герой %s ограбил караваны государства %s." % [hero.display_name(), nation.short_name], ids)
	elif roll < 0.6 and region != null:
		region.unrest += 0.5
		hero.add_xp(world, 1.0)
		hero.add_deed(world, "посеял смуту в регионе " + where)
	elif roll < 0.8:
		# Сжечь деревню — только малые поселения.
		var victim: City = null
		for c in region.cells if region != null else PackedInt32Array():
			var city := world.city_at(c)
			if city != null and not city.is_capital and city.tier() == 0:
				victim = city
				break
		if victim != null:
			world.log_event(&"hero", "Герой %s сжёг деревню %s (%s)." % [hero.display_name(), victim.name, nation.short_name], ids)
			hero.add_deed(world, "сжёг деревню " + victim.name)
			world.destroy_city(victim)
		else:
			nation.army *= 0.98
			hero.add_deed(world, "собрал разбойничью шайку в регионе " + where)
		hero.add_xp(world, 1.0)
	elif hero.nation_id != owner and rng.randf() < 0.4:
		# Убийство правителя — власть сменится в ближайший год.
		var victim := nation.ruler_display()
		nation.reign_left = 0
		nation.stability = maxf(0.0, nation.stability - 0.08)
		hero.add_xp(world, 2.0)
		hero.add_deed(world, "убил правителя: %s" % victim)
		world.log_event(&"hero", "Злодей %s убил правителя государства %s — %s." % [hero.display_name(), nation.short_name, victim], ids)
	else:
		hero.add_xp(world, 0.5)
		hero.add_deed(world, "запугивал селян региона " + where)


# ---------------------------------------------------------------------------
# Великие деяния
# ---------------------------------------------------------------------------

func _great_deed(world: World, hero: Hero) -> void:
	var rng := world.rng
	var options: Array[StringName] = [&"artifact", &"wonder", &"naga_island"]
	if world.active_landmarks(&"source").size() < Landmark.MAX_SOURCES and hero.karma > -0.3:
		options.append(&"source")
	if hero.karma < -0.3 and world.active_landmarks(&"portal").is_empty() and rng.randf() < 0.35:
		options.append(&"portal")
	var deed: StringName = options[rng.randi_range(0, options.size() - 1)]
	# Успех — редкость: опыт помогает, но пучина, бездна и судьба своенравны.
	var success := rng.randf() < 0.18 + hero.level * 0.015
	if not success:
		_great_failure(world, hero, deed)
		return
	match deed:
		&"naga_island":
			if not naga_island(world, hero):
				_great_failure(world, hero, deed)
		&"source":
			power_source(world, hero, hero.cell)
		&"portal":
			open_portal(world, hero.cell, hero)
		&"wonder":
			_wonder(world, hero)
		_:
			hero.artifact = "%s «%s»" % [hero.hero_class.weapon, NameGenerator.place_name(hero.race, rng)]
			hero.artifact_mult = 1.8
			hero.add_deed(world, "выковал легендарное оружие: " + hero.artifact)
			world.log_event(&"great", "Великое деяние: %s выковал легендарное оружие — %s." % [hero.display_name(), hero.artifact],
					PackedInt32Array([hero.nation_id]) if hero.nation_id >= 0 else PackedInt32Array())


const FAILURES := {
	&"naga_island": "попытался поднять из пучины остров, но волны поглотили его",
	&"source": "искал источник силы, но тот вырвался из-под земли и испепелил его",
	&"portal": "пытался отворить врата бездны, но демоны утащили его за грань",
	&"wonder": "задумал воздвигнуть чудо света, но стройка рухнула",
	&"artifact": "ковал легендарное оружие, но горн взорвался",
}


func _great_failure(world: World, hero: Hero, deed: StringName) -> void:
	var text: String = FAILURES.get(deed, "задумал великое, но не преуспел")
	var dies := world.rng.randf() < 0.25
	if dies:
		world.log_event(&"great", "Неудача: %s %s." % [hero.display_name(), text], PackedInt32Array())
		hero.die(world)
	else:
		hero.level = maxi(1, hero.level - world.rng.randi_range(1, 3))
		hero.add_deed(world, text + " — но выжил")
		world.log_event(&"great", "Неудача: %s %s — но выжил, растеряв силы." % [hero.display_name(), text], PackedInt32Array())


## Поднять остров в открытом море и призвать на него народ нагов. Герой становится их правителем.
static func naga_island(world: World, hero: Hero) -> bool:
	var nagas := RaceDB.get_race(&"nagas")
	if nagas == null:
		return false
	var map := world.map
	var rng := world.rng
	var center := -1
	for attempt in 400:
		var c := rng.randi_range(0, map.cell_count() - 1)
		if map.biome[c] != Biome.OCEAN:
			continue
		var p := map.cell_pos(c)
		if p.x < 12 or p.y < 12 or p.x > map.width - 12 or p.y > map.height - 12:
			continue
		var clear := true
		for dy in range(-9, 10, 3):
			for dx in range(-9, 10, 3):
				if map.is_land(map.index_of(p.x + dx, p.y + dy)):
					clear = false
		if clear:
			center = c
			break
	if center < 0:
		return false
	for k in 8:
		GodTools.reshape(world, center, 6, 0.12)
	if not map.is_land(center):
		return false
	var nation := GodTools.create_nation(world, nagas, center, false)
	if nation == null:
		return false
	world.terrain_version += 1
	var region := world.region_at(center)
	world.log_event(&"great", "Великое деяние: %s поднял из пучины остров %s и призвал народ нагов — возникло %s." % [
		hero.display_name(), region.name, nation.name], PackedInt32Array([nation.id]))
	hero.leave_service(world)
	hero.nation_id = nation.id
	nation.ruler_name = hero.name
	nation.ruler_number = 1
	nation.dynasty = hero.name
	hero.become_ruler(world)
	return true


## Источник силы в регионе клетки (не больше Landmark.MAX_SOURCES в мире).
static func power_source(world: World, hero: Hero, cell: int) -> Landmark:
	if world.active_landmarks(&"source").size() >= Landmark.MAX_SOURCES or not world.map.is_land(cell):
		return null
	var region := world.region_at(cell)
	world.ensure_region_name(region)
	var name := "Источник %s" % NameGenerator.place_name(hero.race if hero != null else RaceDB.all()[0], world.rng)
	var lm := world.add_landmark(&"source", name, cell, hero.id if hero != null else -1)
	var owner := world.owner[cell]
	var ids := PackedInt32Array([owner]) if owner >= 0 else PackedInt32Array()
	if hero != null:
		hero.add_deed(world, "открыл %s в регионе %s" % [name, region.name])
		hero.add_xp(world, 4.0)
		world.log_event(&"great", "Великое деяние: %s открыл %s в регионе %s. Кто владеет им — тот силён." % [
			hero.display_name(), name, region.name], ids)
	else:
		world.log_event(&"great", "Там, где упала звезда, забил %s (регион %s). Кто владеет им — тот силён." % [name, region.name], ids)
	return lm


## Портал в бездну: в регионе возникает государство демонов, воюющее со всеми.
static func open_portal(world: World, cell: int, hero: Hero) -> Nation:
	var demons := RaceDB.get_race(&"demons")
	var region := world.region_at(cell)
	if demons == null or region == null:
		return null
	var nation := GodTools.create_nation(world, demons, cell, false)
	if nation == null:
		return null
	# Бездна выплёскивает легионы и захватывает соседние ничьи регионы.
	nation.army = 45000.0 + (hero.level * 3000.0 if hero != null else 20000.0)
	nation.stock[Goods.GOLD] = 800.0
	nation.stock[Goods.METAL] = 500.0
	for nb in region.neighbors:
		for c in world.regions[nb].cells:
			if world.owner[c] == -1:
				world.set_owner(c, nation.id)
	nation.pop[demons.index] = maxf(nation.pop[demons.index], nation.capacity[demons.index] * 0.6)
	var lm := world.add_landmark(&"portal", "Врата бездны", cell, hero.id if hero != null else -1)
	lm.hero_id = nation.id  # для портала храним государство демонов
	var who := ("Злодей %s отворил" % hero.display_name()) if hero != null else "Неведомая сила отворила"
	world.log_event(&"great", "%s Врата бездны в регионе %s! Из портала хлынули демоны — %s объявляет войну всему живому." % [
		who, region.name, nation.name], PackedInt32Array([nation.id]))
	if hero != null:
		hero.add_deed(world, "отворил Врата бездны в регионе " + region.name)
		hero.karma = -1.0
	return nation


func _wonder(world: World, hero: Hero) -> void:
	var owner := hero.nation_id if hero.nation_id >= 0 else world.owner[hero.cell]
	if owner < 0 or world.nations[owner].capital_city < 0:
		_great_failure(world, hero, &"wonder")
		return
	var nation := world.nations[owner]
	var city := world.cities[nation.capital_city]
	if city.buildings.has(&"wonder"):
		_great_failure(world, hero, &"wonder")
		return
	city.buildings.append(&"wonder")
	city.luck *= 2.0
	CitySystem.recompute_building_effects(world, nation)
	world.add_landmark(&"wonder", "Чудо %s" % Fate._genitive(hero.name), city.cell, hero.id)
	hero.add_deed(world, "воздвиг чудо света в городе " + city.name)
	hero.add_xp(world, 4.0)
	world.log_event(&"great", "Великое деяние: %s воздвиг в городе %s чудо света, о котором заговорил весь мир." % [
		hero.display_name(), city.name], PackedInt32Array([owner]))


## Герой у пустого трона: бой со стражем ради проклятого оружия.
func _throne_attempt(world: World, hero: Hero) -> void:
	var throne: Landmark = null
	for lm in world.active_landmarks(&"throne"):
		if lm.cell == hero.goal_cell:
			throne = lm
	hero.goal_cell = -1
	if throne == null:
		return
	var rng := world.rng
	# Вблизи страж виден лучше: рассудительный ещё может повернуть назад.
	if not hero.dares(throne.guardian, rng, 2.0):
		hero.thought = "Увидел стража трона «%s» вблизи — не время умирать." % throne.name
		hero.add_deed(world, "дошёл до трона «%s», увидел стража и отступил" % throne.name)
		if rng.randf() < 0.3:
			world.log_event(&"hero", "Герой %s дошёл до пустого трона «%s», но, увидев стража, благоразумно отступил." % [
				hero.display_name(), throne.name], PackedInt32Array())
		return
	var ours := hero.power() * rng.randf_range(0.6, 1.5)
	var theirs := throne.guardian * rng.randf_range(0.6, 1.3)
	if ours < theirs:
		world.log_event(&"great", "Герой %s пал от стража у пустого трона «%s»." % [hero.display_name(), throne.name], PackedInt32Array())
		hero.die(world)
		return
	throne.active = false
	hero.artifact = throne.artifact
	hero.artifact_mult = 1.6
	hero.karma = maxf(-1.0, hero.karma - 0.4)
	hero.epithet = "Проклятый"
	hero.add_xp(world, 5.0)
	hero.add_deed(world, "сразил стража трона «%s» и завладел оружием: %s" % [throne.name, throne.artifact])
	world.log_event(&"great", "%s сразил стража у пустого трона «%s» и завладел проклятым оружием — %s." % [
		hero.display_name(), throne.name, throne.artifact],
		PackedInt32Array([hero.nation_id]) if hero.nation_id >= 0 else PackedInt32Array())


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
	if mod < 0.0:
		return 0.0
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
		for side in [1, -1]:
			for m in war.members(side):
				if h.fights_for(m) and not sides[side].has(h):
					sides[side].append(h)
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
