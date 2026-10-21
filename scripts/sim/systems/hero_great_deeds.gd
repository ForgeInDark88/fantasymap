class_name HeroGreatDeeds
extends "res://scripts/sim/systems/hero_deeds.gd"
## Великие деяния героев (часть HeroSystem): остров нагов, источник силы,
## Врата бездны, чудо света, легендарное оружие и их провалы; бой у пустого трона.

const FAILURES := {
	&"naga_island": "попытался поднять из пучины остров, но волны поглотили его",
	&"source": "искал источник силы, но тот вырвался из-под земли и испепелил его",
	&"portal": "пытался отворить врата бездны, но демоны утащили его за грань",
	&"wonder": "задумал воздвигнуть чудо света, но стройка рухнула",
	&"artifact": "ковал легендарное оружие, но горн взорвался",
}


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
			ArtifactSystem.create(world, &"legendary_weapon", hero, "", "выкован героем %s" % hero.name)
			hero.add_deed(world, "выковал легендарное оружие: " + hero.artifact)
			world.log_event(&"great", "Великое деяние: %s выковал легендарное оружие — %s." % [hero.display_name(), hero.artifact],
					PackedInt32Array([hero.nation_id]) if hero.nation_id >= 0 else PackedInt32Array())


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
		var m := world.gdi(12)
		if p.x < m or p.y < m or p.x > map.width - m or p.y > map.height - m:
			continue
		var clear := true
		var r := world.gdi(9)
		var st := world.gdi(3)
		for dy in range(-r, r + 1, st):
			for dx in range(-r, r + 1, st):
				if map.is_land(map.index_of(p.x + dx, p.y + dy)):
					clear = false
		if clear:
			center = c
			break
	if center < 0:
		return false
	for k in 8:
		GodTools.reshape(world, center, world.gdi(6), 0.12)
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
	# Бездна сразу нападает на всех, с кем соприкоснулась.
	for other in nation.borders.keys():
		if world.nations[other].alive and world.diplomacy.war_between(nation.id, other) == null:
			world.diplomacy.declare_war(world, nation.id, other, &"demonic")
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
	ArtifactSystem.create(world, &"cursed_weapon", hero, throne.artifact, "добыт у стража трона «%s»" % throne.name)
	hero.karma = maxf(-1.0, hero.karma - 0.4)
	hero.epithet = "Проклятый"
	hero.add_xp(world, 5.0)
	hero.add_deed(world, "сразил стража трона «%s» и завладел оружием: %s" % [throne.name, throne.artifact])
	world.log_event(&"great", "%s сразил стража у пустого трона «%s» и завладел проклятым оружием — %s." % [
		hero.display_name(), throne.name, throne.artifact],
		PackedInt32Array([hero.nation_id]) if hero.nation_id >= 0 else PackedInt32Array())
