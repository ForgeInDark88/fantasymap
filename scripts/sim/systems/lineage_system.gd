class_name LineageSystem
extends RefCounted
## Родословные героев. У супругов-героев рождаются дети; ребёнок растёт
## (World.hero_births) и, повзрослев, становится героем: наследует класс
## (чаще всего), карму и ум родителей (с разбросом), а порой и прозвище
## («… Младший»). Первые дети основывают род (World.lineages), к которому
## принадлежат все потомки; наследство (артефакт) переходит детям.

## Шанс в год у супружеской пары, предел детей у пары.
const BIRTH_CHANCE := 0.1
const MAX_CHILDREN := 3
## Доля жизни расы до взросления (у бессмертных — CHILD_YEARS_IMMORTAL).
const CHILD_SHARE := 0.18
const CHILD_YEARS_IMMORTAL := 40
## Шанс унаследовать класс и прозвище родителя.
const CLASS_INHERIT := 0.6
const EPITHET_INHERIT := 0.35
## Взрослые дети ждут, если героев слишком много (сверх лимита HeroSystem).
const EXTRA_HEROES := 6


## Годовые дела героя: у пары может родиться ребёнок (проверяет младший id пары).
static func hero_yearly(world: World, hero: Hero) -> void:
	if hero.spouse < 0 or hero.spouse < hero.id:
		return
	var other := world.heroes[hero.spouse]
	if not other.alive or other.spouse != hero.id or hero.age > hero.max_age * 0.75 or other.age > other.max_age * 0.75:
		return
	var rng := world.rng
	if _children_of(world, hero) >= MAX_CHILDREN or rng.randf() > BIRTH_CHANCE:
		return
	birth(world, hero, other)


## Рождение ребёнка у пары героев (также инструмент панели Бога).
static func birth(world: World, a: Hero, b: Hero) -> Dictionary:
	var rng := world.rng
	var lineage := a.lineage if a.lineage >= 0 else b.lineage
	if lineage < 0:
		lineage = world.lineages.size()
		world.lineages.append({"name": "Род %s" % Fate._genitive(a.name), "founder": a.id, "year": world.year, "heroes": 2})
		world.log_event(&"lineage", "Герои %s и %s положили начало роду — %s." % [a.display_name(), b.display_name(),
			world.lineages[lineage].name], _ids(a, b))
	a.lineage = lineage
	b.lineage = lineage
	var cls_parent := a if rng.randf() < 0.5 else b
	var cls := cls_parent.hero_class.id if rng.randf() < CLASS_INHERIT else PoliticsDB.random_hero_class(a.race, rng).id
	var years := CHILD_YEARS_IMMORTAL if a.race.lifespan <= 0 else maxi(14, int(a.race.lifespan * CHILD_SHARE))
	var epithet := ""
	for p in [a, b]:
		if not (p as Hero).epithet.is_empty() and epithet.is_empty() and rng.randf() < EPITHET_INHERIT:
			epithet = (p as Hero).epithet.trim_suffix(" Младший") + " Младший"
	var child := {"parents": [a.id, b.id], "race": a.race_id, "class": cls,
		"name": NameGenerator.unique(world.used_names, NameGenerator.person_name.bind(a.race, rng)),
		"karma": clampf((a.karma + b.karma) * 0.5 + rng.randf_range(-0.35, 0.35), -1.0, 1.0),
		"intellect": clampf((a.intellect + b.intellect) * 0.5 + rng.randf_range(-0.2, 0.2), 0.0, 1.0),
		"adult": world.year + years, "lineage": lineage, "cell": a.cell, "born": world.year, "epithet": epithet}
	world.hero_births.append(child)
	a.add_deed(world, "у героя родился ребёнок — %s" % child.name)
	b.add_deed(world, "у героя родился ребёнок — %s" % child.name)
	if rng.randf() < 0.25:
		world.log_event(&"lineage", "У героев %s и %s родился ребёнок — %s (%s)." % [a.display_name(), b.display_name(),
			child.name, world.lineages[lineage].name], _ids(a, b))
	return child


static func _children_of(world: World, hero: Hero) -> int:
	var k := hero.children.size()
	for c in world.hero_births:
		if (c.parents as Array).has(hero.id):
			k += 1
	return k


## Дети, ещё не ставшие героями (для окна героя).
static func unborn_children(world: World, hero: Hero) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	for c in world.hero_births:
		if (c.parents as Array).has(hero.id):
			res.append(c)
	return res


static func _ids(a: Hero, b: Hero) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for h in [a, b]:
		if (h as Hero).nation_id >= 0 and not ids.has((h as Hero).nation_id):
			ids.append((h as Hero).nation_id)
	return ids


## Раз в год: повзрослевшие дети становятся героями.
func tick_year(world: World) -> void:
	if world.hero_births.is_empty():
		return
	var crowd := world.wandering_heroes().size()
	var i := 0
	while i < world.hero_births.size():
		var c: Dictionary = world.hero_births[i]
		if int(c.adult) > world.year:
			i += 1
			continue
		if crowd >= HeroSystem.MAX_HEROES + EXTRA_HEROES:
			c.adult = world.year + 1
			i += 1
			continue
		world.hero_births.remove_at(i)
		if mature(world, c) != null:
			crowd += 1


## Ребёнок становится героем.
static func mature(world: World, c: Dictionary) -> Hero:
	var race := RaceDB.get_race(StringName(c.race))
	var cls: HeroClassDef = PoliticsDB.get_hero_class(StringName(c["class"]))
	if race == null or cls == null:
		return null
	var cell := int(c.cell)
	for p in c.parents:
		var ph := world.heroes[int(p)]
		if ph.alive and ph.cell >= 0:
			cell = ph.cell
			break
	if cell < 0 or not world.map.is_land(cell):
		return null
	var hero := HeroSystem.make_hero(world, race, cls, cell, String(c.name))
	hero.karma = float(c.karma)
	hero.intellect = float(c.intellect)
	hero.epithet = String(c.epithet)
	hero.lineage = int(c.lineage)
	hero.age = world.year - int(c.born)
	hero.born_year = int(c.born)
	for p in c.parents:
		var ph := world.heroes[int(p)]
		hero.parents.append(ph.id)
		ph.children.append(hero.id)
		hero.add_bond(ph, 0.8)
		ph.add_bond(hero, 0.8)
	var lin: Dictionary = world.lineages[hero.lineage]
	lin.heroes = int(lin.heroes) + 1
	var p0 := world.heroes[hero.parents[0]]
	var p1 := world.heroes[hero.parents[1]]
	hero.add_deed(world, "вырос и отправился странствовать — дитя героев %s и %s" % [p0.name, p1.name])
	var owner := world.owner[cell]
	world.log_event(&"lineage", "%s, дитя героев %s и %s (%s), вырос и стал героем — %s." % [hero.display_name(), p0.name, p1.name,
		lin.name, hero.hero_class.display_name.to_lower()], PackedInt32Array([owner]) if owner >= 0 else PackedInt32Array())
	return hero
