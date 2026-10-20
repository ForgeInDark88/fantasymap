class_name RuinSystem
extends RefCounted
## Руины и археология.
##
## Руины остаются от разрушенных городов (столица — богаче), от павших
## государств (храм забытых богов их веры) и от павших прославленных героев
## (гробница). Герои-странники исследуют руины в своём краю: находят золото,
## оружие (в гробнице — оружие покойного), знания для своего государства,
## натыкаются на стражей-чудовищ и проклятия. Государства раскапывают руины
## на своей земле (нужна письменность). На руинах может возродиться город, а в
## храме забытых богов — культ. Проклятые Судьбой герои получают пустой трон
## в руинах, если такие есть в глуши.

## Предел руин в мире (старейшие исчерпанные забываются).
const MAX_RUINS := 120
## Богатство и опасность по виду руин (× случайный множитель).
const WEALTH := {&"city": 150.0, &"capital": 450.0, &"tomb": 250.0, &"temple": 300.0}
const DANGER := {&"city": 800.0, &"capital": 2000.0, &"tomb": 2500.0, &"temple": 3000.0}
## Шанс героя заняться руинами в год (если они в его краю).
const HERO_EXPLORE := 0.12
## Раз в сколько лет государство раскапывает руины на своей земле и с каким шансом.
const DIG_PERIOD := 5
const DIG_CHANCE := 0.3
## Шанс возрождения города на руинах при основании города, культа — в храме.
const REVIVE_CHANCE := 0.5
const CULT_CHANCE := 0.15


## Новые руины. Вызывается при разрушении города, гибели государства и героя.
static func add(world: World, kind: StringName, cell: int, name: String, origin: String, hero_id: int = -1) -> Ruin:
	if cell < 0 or not world.map.is_land(cell):
		return null
	_trim(world)
	var rng := world.rng
	var r := Ruin.new()
	r.id = world.ruins.size()
	r.kind = kind
	r.cell = cell
	r.name = name
	r.origin = origin
	r.created_year = world.year
	r.hero_id = hero_id
	r.wealth = WEALTH.get(kind, 150.0) * rng.randf_range(0.6, 1.5)
	r.danger = DANGER.get(kind, 1000.0) * rng.randf_range(0.5, 1.6)
	r.cursed = rng.randf() < (0.4 if kind == &"temple" or kind == &"tomb" else 0.1)
	world.ruins.append(r)
	world.count(&"ruins")
	return r


## Исчерпанные старые руины забываются, если их слишком много.
static func _trim(world: World) -> void:
	if world.ruins.size() < MAX_RUINS:
		return
	for r in world.ruins:
		if r.cell >= 0 and (r.depleted() or r.revived):
			r.cell = -1  # стёрлись с лица земли (запись остаётся для летописи)
			return


static func on_city_destroyed(world: World, city: City) -> void:
	if city.tier() < 1 and world.rng.randf() > 0.3:
		return
	var who := world.nations[city.nation_id].name if city.nation_id >= 0 else "забытого народа"
	var kind := &"capital" if city.is_capital else &"city"
	add(world, kind, city.cell, "Руины %s" % city.name, "%s %s, разрушенный в %d г." % [
		"столица государства" if city.is_capital else "город государства", who, world.year])


static func on_nation_fell(world: World, nation: Nation, cell: int) -> void:
	if world.rng.randf() > 0.5:
		return
	var faith := world.religions[nation.state_religion].name if nation.state_religion >= 0 and nation.state_religion < world.religions.size() else "забытых богов"
	add(world, &"temple", cell, "Храм %s" % faith, "святилище павшего государства %s (%d г.)" % [nation.name, world.year])


static func on_hero_died(world: World, hero: Hero) -> void:
	if hero.level < 8 or world.rng.randf() > 0.4 or hero.cell < 0:
		return
	add(world, &"tomb", hero.cell, "Гробница %s" % Fate._genitive(hero.name), "место упокоения героя %s (%d г.)" % [
		hero.display_name(), world.year], hero.id)


## Ближайшие к клетке живые (не исчерпанные) руины в её регионе или соседних.
static func near(world: World, cell: int) -> Ruin:
	var rid := world.region_of[cell] if cell >= 0 else -1
	if rid < 0:
		return null
	var region := world.regions[rid]
	for r in world.ruins:
		if r.cell < 0 or r.depleted():
			continue
		var rr := world.region_of[r.cell]
		if rr == rid or region.neighbors.has(rr):
			return r
	return null


## Герой исследует руины рядом (вызывается из HeroSystem раз в год).
static func hero_explore(world: World, hero: Hero) -> void:
	var rng := world.rng
	if rng.randf() > HERO_EXPLORE:
		return
	var r := near(world, hero.cell)
	if r == null:
		return
	# Умный не полезет к стражу не по силам.
	if not hero.dares(r.danger, rng):
		hero.thought = "Руины «%s» манят, но страж там мне не по зубам." % r.name
		return
	var ours := hero.power() * rng.randf_range(0.6, 1.4)
	if ours < r.danger * rng.randf_range(0.6, 1.2):
		world.log_event(&"ruins", "Герой %s сгинул в «%s» — стражи древних мест не дремлют." % [hero.display_name(), r.name])
		hero.die(world)
		return
	hero.add_xp(world, 3.0)
	var roll := rng.randf()
	var take := r.wealth * rng.randf_range(0.15, 0.35)
	r.wealth -= take
	r.danger *= 0.7
	var what := ""
	if r.cursed and roll < 0.25:
		hero.karma = maxf(-1.0, hero.karma - 0.4)
		r.cursed = false
		what = "навлёк на себя древнее проклятие"
	elif hero.artifact_id < 0 and _lost_here(world, r) != null and roll < 0.7:
		var found := _lost_here(world, r)
		ArtifactSystem.give(world, found, hero, "найден в «%s»" % r.name)
		what = "нашёл там %s" % found.name
	elif hero.artifact_id < 0 and roll < 0.4:
		var kind := _find_kind(world)
		var a := ArtifactSystem.create(world, kind, hero, "", "найден в «%s»" % r.name)
		what = "нашёл древний предмет — %s" % a.name
	elif hero.nation_id >= 0 and roll < 0.7:
		var n := world.nations[hero.nation_id]
		var t: TechDef = null
		for res in TechDB.all():
			if TechSystem.is_available(n, res as TechDef):
				t = res
				break
		if t != null:
			TechSystem.unlock(world, n, t, "из древних свитков, найденных героем %s" % hero.name)
			what = "принёс государству %s древнее знание: %s" % [n.short_name, t.display_name.to_lower()]
		else:
			n.stock[Goods.GOLD] += take
			what = "принёс в казну %s %d золота" % [n.short_name, roundi(take)]
	else:
		if hero.nation_id >= 0:
			world.nations[hero.nation_id].stock[Goods.GOLD] += take
		what = "нашёл клад (%d золота)" % roundi(take)
	hero.add_deed(world, "проник в «%s» и %s" % [r.name, what])
	if not what.begins_with("нашёл клад") or rng.randf() < 0.15:
		world.log_event(&"ruins", "Герой %s проник в «%s» и %s." % [hero.display_name(), r.name, what],
				PackedInt32Array([hero.nation_id]) if hero.nation_id >= 0 else PackedInt32Array())


## Потерянный предмет, лежащий в этих руинах (у гробницы — оружие покойного).
static func _lost_here(world: World, r: Ruin) -> Artifact:
	for a in world.artifacts:
		if a.is_lost() and a.cell >= 0 and world.region_of[a.cell] == world.region_of[r.cell]:
			return a
	return null


## Вид находки по весам data/artifacts.
static func _find_kind(world: World) -> StringName:
	var total := 0.0
	for res in LoreDB.artifacts():
		total += (res as ArtifactDef).weight
	var roll := world.rng.randf() * total
	for res in LoreDB.artifacts():
		roll -= (res as ArtifactDef).weight
		if roll <= 0.0:
			return res.id
	return &"ancient_weapon"


## Раскопки государством руин на своей земле.
func tick(world: World, nation: Nation) -> void:
	if (world.year + nation.id + 3) % DIG_PERIOD != 0 or not nation.techs.has(&"writing"):
		return
	var rng := world.rng
	for r in world.ruins:
		if r.cell < 0 or r.depleted() or world.owner[r.cell] != nation.id or rng.randf() > DIG_CHANCE:
			continue
		var take := r.wealth * rng.randf_range(0.2, 0.5)
		r.wealth -= take
		nation.stock[Goods.GOLD] += take
		if r.cursed and rng.randf() < 0.3:
			for k in nation.pop.size():
				nation.pop[k] *= 0.97
			r.cursed = false
			world.log_event(&"ruins", "Раскопки в «%s» (%s) пробудили древнее проклятие: в округе мор." % [r.name, nation.short_name],
					PackedInt32Array([nation.id]))
		elif rng.randf() < 0.25:
			var t: TechDef = null
			for res in TechDB.all():
				if TechSystem.is_available(nation, res as TechDef) and rng.randf() < 0.4:
					t = res
					break
			if t != null:
				TechSystem.unlock(world, nation, t, "на раскопках «%s»" % r.name)
		return


## Город на руинах: при основании города государство предпочитает руины на своей земле.
static func revive_site(world: World, nation: Nation) -> Ruin:
	if world.rng.randf() > REVIVE_CHANCE:
		return null
	for r in world.ruins:
		if r.cell >= 0 and not r.revived and (r.kind == &"city" or r.kind == &"capital") and world.owner[r.cell] == nation.id \
				and world.can_place_city(r.cell):
			return r
	return null


## Храм забытых богов на земле государства — для культа (SocietySystem).
static func temple_for_cult(world: World) -> Ruin:
	if world.rng.randf() > CULT_CHANCE:
		return null
	for r in world.ruins:
		if r.cell >= 0 and r.kind == &"temple" and not r.revived and world.owner[r.cell] >= 0 and world.region_of[r.cell] >= 0:
			return r
	return null


## Глухие руины для пустого трона (Судьба).
static func remote_ruin(world: World) -> Ruin:
	for r in world.ruins:
		if r.cell >= 0 and world.owner[r.cell] < 0 and world.city_cell[r.cell] < 0:
			return r
	return null
