class_name ArtifactSystem
extends RefCounted
## Артефакты как предметы (data/artifacts): кольца, короны, книги, оружие,
## реликвии. Создаются великими деяниями, Судьбой (проклятое оружие), в руинах
## и дарами богов; переходят из рук в руки: трофей в поединке, наследство
## супругу или детям, сокровищница государства (герой на службе или на троне),
## кража (плуты и шпионы), потеря на месте гибели. Потерянные предметы ищут
## герои; знаменитые реликвии в чужой сокровищнице — повод для войны.
## Предмет у героя даёт силу, ум и тянет карму; в сокровищнице — эффекты державе.

## Шанс в год плуту или шпиону украсть предмет у героя в том же краю.
const THEFT_CHANCE := 0.12
## Шанс в год герою отправиться за потерянным предметом.
const QUEST_CHANCE := 0.1


## Новый предмет вида def (имя — по шаблону или name, если задано).
static func create(world: World, def_id: StringName, owner: Hero = null, name: String = "", origin: String = "") -> Artifact:
	var def := LoreDB.artifact(def_id)
	if def == null:
		return null
	var a := Artifact.new()
	a.id = world.artifacts.size()
	a.def = def
	a.created_year = world.year
	a.name = name if not name.is_empty() else _make_name(world, def, owner)
	world.artifacts.append(a)
	if not origin.is_empty():
		a.history.append("%d г.: %s" % [world.year, origin])
	if owner != null:
		give(world, a, owner, "")
	return a


static func _make_name(world: World, def: ArtifactDef, owner: Hero) -> String:
	var rng := world.rng
	var pattern := def.name_patterns[rng.randi_range(0, def.name_patterns.size() - 1)] if not def.name_patterns.is_empty() else def.display_name
	var race: RaceDef = owner.race if owner != null else RaceDB.all()[rng.randi_range(0, RaceDB.count() - 1)]
	return pattern.format({"weapon": owner.hero_class.weapon if owner != null else "Клинок",
		"name": Fate._genitive(owner.name) if owner != null else NameGenerator.person_name(race, rng),
		"place": NameGenerator.place_name(race, rng),
		"god": LoreDB.god(owner.patron_god).name_genitive() if owner != null and owner.patron_god != &"" and LoreDB.god(owner.patron_god) != null else "Неба"})


## Предмет переходит к герою (how — как: «взят в бою», «унаследован»…).
static func give(world: World, a: Artifact, hero: Hero, how: String) -> void:
	if hero.artifact_id >= 0 and hero.artifact_id != a.id:
		drop(world, world.artifacts[hero.artifact_id], hero.cell)
	_release(world, a)
	a.hero = hero.id
	a.cell = -1
	hero.artifact_id = a.id
	hero.artifact = a.name
	hero.artifact_mult = a.power_mult()
	hero._artifact_wits = a.def.wits_bonus if a.def != null else 0.0
	if not how.is_empty():
		a.history.append("%d г.: %s — %s" % [world.year, how, hero.display_name()])


## Предмет уходит в сокровищницу государства.
static func to_treasury(world: World, a: Artifact, nation: Nation, how: String) -> void:
	_release(world, a)
	a.nation = nation.id
	a.cell = -1
	a.history.append("%d г.: %s — %s" % [world.year, how, nation.name])
	apply_nation_effects(world, nation)


## Предмет потерян в клетке (его можно найти).
static func drop(world: World, a: Artifact, cell: int) -> void:
	_release(world, a)
	a.cell = cell
	a.history.append("%d г.: потерян в краю %s" % [world.year, world.region_label(cell, "диких земель")])


static func _release(world: World, a: Artifact) -> void:
	if a.hero >= 0:
		var h := world.heroes[a.hero]
		if h.artifact_id == a.id:
			h.artifact_id = -1
			h.artifact = ""
			h.artifact_mult = 1.0
			h._artifact_wits = 0.0
		a.hero = -1
	if a.nation >= 0:
		var n := world.nations[a.nation]
		a.nation = -1
		apply_nation_effects(world, n)


## Эффекты реликвий сокровищницы — в Nation.effects (источник &"relics").
static func apply_nation_effects(world: World, nation: Nation) -> void:
	var d := {}
	for a in world.artifacts:
		if a.nation != nation.id or a.def == null:
			continue
		for k in a.def.nation_effects:
			if String(k).ends_with("_mult"):
				d[k] = d.get(k, 1.0) * a.def.nation_effects[k]
			else:
				d[k] = d.get(k, 0.0) + a.def.nation_effects[k]
	nation.set_effects(&"relics", d)


## Смерть владельца: трофей победителю, наследство родным, сокровищница — или потеря.
static func on_hero_death(world: World, hero: Hero, killer: Hero) -> void:
	if hero.artifact_id < 0:
		return
	var a := world.artifacts[hero.artifact_id]
	if killer != null and killer.alive and killer.artifact_id < 0:
		give(world, a, killer, "взят в бою у героя %s" % hero.name)
		return
	var heirs: Array[int] = []
	if hero.spouse >= 0:
		heirs.append(hero.spouse)
	heirs.append_array(hero.children)
	for h in heirs:
		var heir := world.heroes[h]
		if heir.alive and heir.artifact_id < 0 and not heir.is_ruler:
			give(world, a, heir, "унаследован после гибели героя %s" % hero.name)
			return
	if hero.nation_id >= 0 and world.nations[hero.nation_id].alive:
		to_treasury(world, a, world.nations[hero.nation_id], "передан в сокровищницу после гибели героя %s" % hero.name)
		return
	drop(world, a, hero.cell)


## Герой взошёл на трон: его предмет становится реликвией державы.
static func on_crowned(world: World, hero: Hero, nation: Nation) -> void:
	if hero.artifact_id >= 0:
		to_treasury(world, world.artifacts[hero.artifact_id], nation, "стал реликвией престола")


## Пала столица: реликвии сокровищницы достаются победителю.
static func on_capital_taken(world: World, loser: Nation, winner: Nation) -> void:
	for a in world.artifacts:
		if a.nation == loser.id:
			to_treasury(world, a, winner, "взят в сокровищнице павшей столицы %s" % loser.short_name)
			world.log_event(&"artifact", "%s забирает из сокровищницы %s реликвию — %s." % [winner.name, loser.short_name, a.name],
					PackedInt32Array([winner.id, loser.id]))


## Раз в год для героя: дрейф кармы от предмета, кража, поход за потерянным предметом.
static func hero_yearly(world: World, hero: Hero) -> void:
	var rng := world.rng
	if hero.artifact_id >= 0:
		var a := world.artifacts[hero.artifact_id]
		if a.def != null and a.def.karma_drift != 0.0:
			hero.karma = clampf(hero.karma + a.def.karma_drift, -1.0, 1.0)
	# Кража: плуты и шпионы с тёмной душой.
	if hero.artifact_id < 0 and hero.karma < 0.0 and (hero.hero_class.id == &"rogue" or hero.hero_class.id == &"spy") \
			and rng.randf() < THEFT_CHANCE:
		var rid := world.region_of[hero.cell] if hero.cell >= 0 else -1
		for other in world.wandering_heroes():
			if other != hero and other.artifact_id >= 0 and other.cell >= 0 and world.region_of[other.cell] == rid:
				var a := world.artifacts[other.artifact_id]
				if rng.randf() < 0.5 + hero.wits() - other.wits():
					give(world, a, hero, "украден у героя %s" % other.name)
					hero.add_deed(world, "украл %s у героя %s" % [a.name, other.name])
					other.add_bond(hero, -0.6)
					if a.def != null and a.def.famous:
						world.log_event(&"artifact", "%s украл у героя %s легендарный предмет — %s." % [hero.display_name(), other.display_name(), a.name])
				else:
					other.add_bond(hero, -0.4)
					hero.add_deed(world, "пытался украсть %s, но попался" % a.name)
				break
	# Поход за потерянным предметом.
	if hero.artifact_id < 0 and hero.goal_cell < 0 and hero.level >= 6 and rng.randf() < QUEST_CHANCE:
		var best: Artifact = null
		var best_d := INF
		for a in world.artifacts:
			if a.is_lost() and a.cell >= 0:
				var d := Vector2(world.map.cell_pos(a.cell)).distance_to(Vector2(world.map.cell_pos(hero.cell)))
				if d < best_d:
					best_d = d
					best = a
		if best != null:
			hero.goal_cell = best.cell
			hero.thought = "Ищу %s — говорят, он лежит в краю %s." % [best.name, world.region_label(best.cell, "диких земель")]
			hero.add_deed(world, "отправился на поиски предмета: %s" % best.name)


## Герой пришёл на место потерянного предмета (вызывает HeroSystem при достижении цели).
static func try_pick_up(world: World, hero: Hero) -> bool:
	for a in world.artifacts:
		if a.is_lost() and a.cell >= 0 and world.region_of[a.cell] == world.region_of[hero.cell]:
			give(world, a, hero, "найден героем")
			hero.add_deed(world, "нашёл потерянный предмет — %s" % a.name)
			if a.def != null and a.def.famous:
				world.log_event(&"artifact", "Герой %s нашёл давно потерянный предмет — %s." % [hero.display_name(), a.name],
						PackedInt32Array([hero.nation_id]) if hero.nation_id >= 0 else PackedInt32Array())
			hero.goal_cell = -1
			return true
	return false


## Есть ли у target знаменитая реликвия (повод для войны «за реликвию»).
static func famous_relic_of(world: World, nation_id: int) -> Artifact:
	for a in world.artifacts:
		if a.nation == nation_id and a.def != null and a.def.famous:
			return a
	return null
