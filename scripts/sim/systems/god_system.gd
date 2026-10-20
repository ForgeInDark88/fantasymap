class_name GodSystem
extends RefCounted
## Боги пантеона (data/gods). Каждая вера молится своим богам (GodDef.religions,
## по стартовой вере-прародительнице); боги без вер — общие для всех.
##   • Держава с единой верой порой получает милость бога — эффекты на годы
##     (Nation.effects, источник &"god").
##   • Герой выбирает бога-покровителя по своей вере и натуре. Бог избирает
##     достойнейшего героя близкой натуры — дарует ему божественный дар
##     (артефакт); отрекается от героя, предавшего его натуру, а порой карает.
##   • Судьба: избранник получает лишний второй шанс, а проклятое оружие
##     заточённой души носит имя оружия его бога (Fate).

## Раз в сколько лет держава может получить милость, шанс (× единство веры) и длительность.
const BOON_PERIOD := 10
const BOON_CHANCE := 0.12
## Шанс, что милость попадёт в летопись (иначе — только в карточку державы).
const BOON_LOG := 0.35
const BOON_YEARS := 10
## Шанс в год герою без покровителя избрать бога.
const PATRON_CHANCE := 0.25
## Избрание: уровень, близость натуры, шанс в год.
const CHOSEN_LEVEL := 8
const CHOSEN_GAP := 0.3
const CHOSEN_CHANCE := 0.015
## Отречение (натура героя и бога противоположны) и кара.
const WRATH_GAP := 1.2
const ABANDON_CHANCE := 0.3
const SMITE_CHANCE := 0.04


## Боги, которым молятся последователи веры (id World.religions; -1 — только общие).
static func gods_of(world: World, religion: int) -> Array[GodDef]:
	var def_id: StringName = &""
	if religion >= 0 and religion < world.religions.size() and world.religions[religion].def != null:
		def_id = world.religions[religion].def.id
	var res: Array[GodDef] = []
	for res_g in LoreDB.gods():
		var g := res_g as GodDef
		if g.religions.is_empty() or (def_id != &"" and g.religions.has(def_id)):
			res.append(g)
	return res


## Годовые дела героя с богами: выбор покровителя, избрание, отречение, кара.
static func hero_yearly(world: World, hero: Hero) -> void:
	var rng := world.rng
	if hero.patron_god == &"":
		if rng.randf() < PATRON_CHANCE:
			choose_patron(world, hero)
		return
	var g := LoreDB.god(hero.patron_god)
	if g == null:
		hero.patron_god = &""
		return
	var gap := absf(g.karma - hero.karma)
	if gap > WRATH_GAP:
		if rng.randf() < SMITE_CHANCE:
			world.log_event(&"gods", "Гнев %s: отступник %s испепелён." % [g.name_genitive(), hero.display_name()],
					PackedInt32Array([hero.nation_id]) if hero.nation_id >= 0 else PackedInt32Array())
			world.count(&"smitten")
			hero.die(world)
			return
		if rng.randf() < ABANDON_CHANCE:
			hero.add_deed(world, "отвергнут богом %s за дела, противные его натуре" % g.display_name)
			hero.thought = "%s отвернулся от меня." % g.display_name
			hero.patron_god = &""
			hero.chosen = false
		return
	if not hero.chosen and hero.level >= CHOSEN_LEVEL and gap < CHOSEN_GAP and rng.randf() < CHOSEN_CHANCE \
			and champion_of(world, g.id) == null:
		make_chosen(world, hero, g)


## Герой выбирает бога: веры края (или державы), ближайшего по натуре.
static func choose_patron(world: World, hero: Hero) -> void:
	var faith := -1
	if hero.nation_id >= 0:
		faith = world.nations[hero.nation_id].state_religion
	elif hero.cell >= 0 and world.region_of[hero.cell] >= 0:
		faith = world.regions[world.region_of[hero.cell]].main_faith()
	var best: GodDef = null
	var best_score := -INF
	for g in gods_of(world, faith):
		var score := 1.0 - absf(g.karma - hero.karma) * 0.5 + world.rng.randf() * 0.3 - (0.3 if g.religions.is_empty() else 0.0)
		if score > best_score:
			best_score = score
			best = g
	if best != null:
		hero.patron_god = best.id
		hero.add_deed(world, "стал почитать бога %s (%s)" % [best.display_name, best.title.to_lower()])


static func champion_of(world: World, god: StringName) -> Hero:
	for h in world.wandering_heroes():
		if h.chosen and h.patron_god == god and h.alive:
			return h
	return null


## Бог избирает героя (также инструмент панели Бога).
static func make_chosen(world: World, hero: Hero, g: GodDef) -> void:
	hero.patron_god = g.id
	hero.chosen = true
	if hero.epithet.is_empty():
		hero.epithet = "Избранник %s" % g.name_genitive()
	hero.add_xp(world, 3.0)
	var gift := ""
	if hero.artifact_id < 0:
		var a := ArtifactSystem.create(world, &"divine_gift", hero, "", "дарован избраннику богом %s" % g.display_name)
		if a != null:
			gift = "; дар бога — %s" % a.name
	hero.add_deed(world, "избран богом %s%s" % [g.display_name, gift])
	world.log_event(&"gods", "%s %s, %s, явил знак: его избранником стал герой %s%s." % [g.symbol, g.display_name, g.title.to_lower(), hero.display_name(), gift],
			PackedInt32Array([hero.nation_id]) if hero.nation_id >= 0 else PackedInt32Array())
	world.count(&"chosen")


## Милость бога державе: раз в BOON_PERIOD лет (в свой год).
func tick(world: World, nation: Nation) -> void:
	if nation.god_boon != &"" and world.year >= nation.god_boon_until:
		nation.god_boon = &""
		nation.set_effects(&"god", {})
	if (world.year + nation.id + 7) % BOON_PERIOD != 0 or nation.god_boon != &"" or nation.state_religion < 0:
		return
	var rng := world.rng
	if rng.randf() > BOON_CHANCE * nation.faith_unity:
		return
	var gods := gods_of(world, nation.state_religion)
	if gods.is_empty():
		return
	# Свои боги веры откликаются чаще общих (войны, обмана).
	var own := gods.filter(func(g: GodDef) -> bool: return not g.religions.is_empty())
	var pool: Array = own if not own.is_empty() and rng.randf() < 0.8 else gods
	grant_boon(world, nation, pool[rng.randi_range(0, pool.size() - 1)], rng.randf() < BOON_LOG)


static func grant_boon(world: World, nation: Nation, g: GodDef, log: bool = true) -> void:
	nation.god_boon = g.id
	nation.god_boon_until = world.year + BOON_YEARS
	nation.set_effects(&"god", g.boon)
	if log:
		world.log_event(&"gods", "%s %s %s: милость бога снизошла на %s." % [g.symbol, g.display_name, g.boon_text, nation.name], PackedInt32Array([nation.id]))
