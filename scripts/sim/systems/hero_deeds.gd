class_name HeroDeeds
extends RefCounted
## Поступки героев (часть HeroSystem): добрые и злые дела по карме героя.
## Поступок сдвигает карму; натура понемногу тянет её к склонности класса.


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
	# Логово чудовищ рядом (этап 11.C) — герой идёт на него.
	if roll < 0.35 and region != null:
		var lair := LairSystem.lair_near(world, region.id)
		if lair != null and hero.dares(lair.strength * 0.4, rng):
			LairSystem.hero_fight(world, hero, lair)
			return
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
		# Разбой на дорогах: торговые пути у городов региона становятся опасны.
		for id in nation.city_ids:
			if world.region_of[world.cities[id].cell] == world.region_of[hero.cell]:
				RoadSystem.rob_roads(world, id, 0.3)
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
