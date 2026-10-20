class_name SpySystem
extends RefCounted
## Разведка и тайные операции (data/spy_ops).
##
## Очки разведки государства растут от доходов казны, тайных канцелярий в
## городах и шпионов-героев на службе (× эффект «разведка» от технологий).
## Раз в год (в день государства) правитель может затеять операцию против
## врага или недруга — чаще тираны, безумцы и алчные, реже миролюбивые.
## Успех зависит от соотношения разведок и шпионов-героев; раскрытый шпион
## портит отношения, а раскрытое покушение может стать поводом для войны.

const INTEL_BASE := 0.6
## Доля положительного дохода золотом, идущая в разведку.
const INTEL_PER_GOLD := 0.01
const OFFICE_INTEL := 2.0
const SPY_HERO_INTEL := 1.5
const MAX_INTEL := 60.0
## Базовый шанс в год затеять операцию.
const OP_CHANCE := 0.15
const TEMPERAMENT := {&"tyrant": 2.0, &"mad": 2.2, &"greedy": 1.5, &"warlike": 1.3, &"peaceful": 0.4, &"pious": 0.7,
	&"wise": 0.9, &"charismatic": 0.8}


## Раз в сколько лет пересчитывать разведку государства (со сдвигом по id).
const PERIOD := 2


func tick(world: World, nation: Nation) -> void:
	if (world.year + nation.id) % PERIOD != 0:
		return
	var rng := world.rng
	var offices := 0
	for id in nation.city_ids:
		if world.cities[id].buildings.has(&"spy_office"):
			offices += 1
	var spies := spies_of(world, nation)
	nation.intel = minf(MAX_INTEL, nation.intel + (INTEL_BASE + maxf(0.0, nation.income[Goods.GOLD]) * INTEL_PER_GOLD
			+ offices * OFFICE_INTEL + spies.size() * SPY_HERO_INTEL) * nation.effect(&"spy_mult") * PERIOD)
	if nation.race.has_trait(&"demonic"):
		return
	var temper: float = TEMPERAMENT.get(nation.ruler_trait.id if nation.ruler_trait != null else &"", 1.0)
	var at_war := not world.diplomacy.wars_of(nation.id).is_empty()
	if rng.randf() > OP_CHANCE * PERIOD * temper * (1.5 if at_war else 1.0):
		return
	var target := _pick_target(world, nation)
	if target == null:
		return
	var op := _pick_op(world, nation, target)
	if op != null:
		run(world, nation, target, op)


## Враг на войне или недруг по соседству.
func _pick_target(world: World, nation: Nation) -> Nation:
	var d := world.diplomacy
	var options: Array[int] = []
	for war in d.wars_of(nation.id):
		for m in war.members(-war.side_of(nation.id)):
			options.append(m)
	for other in nation.borders:
		if d.opinion(world, nation.id, other) < -0.1:
			options.append(other)
	if options.is_empty():
		return null
	var t := world.nations[options[world.rng.randi_range(0, options.size() - 1)]]
	return t if t.alive and t.id != nation.id else null


func _pick_op(world: World, nation: Nation, target: Nation) -> SpyOpDef:
	var options: Array[SpyOpDef] = []
	var total := 0.0
	for res in OrgDB.ops():
		var op := res as SpyOpDef
		if op.cost > nation.intel or not _feasible(world, nation, target, op):
			continue
		options.append(op)
		total += op.weight
	if options.is_empty():
		return null
	var roll := world.rng.randf() * total
	for op in options:
		roll -= op.weight
		if roll <= 0.0:
			return op
	return options[options.size() - 1]


func _feasible(world: World, nation: Nation, target: Nation, op: SpyOpDef) -> bool:
	match op.kind:
		"steal_tech":
			for t in target.techs:
				var def := TechDB.find(t)
				if def != null and TechSystem.is_available(nation, def):
					return true
			return false
		"bribe_vassal":
			return not world.diplomacy.vassals_of(world, target.id).is_empty() and nation.stock[Goods.GOLD] >= 100.0
		"disinformation":
			return target.borders.size() >= 2
		"incite", "sabotage":
			return not target.city_ids.is_empty()
	return true


## Проводит операцию (панель Бога вызывает напрямую). Возвращает true при успехе.
static func run(world: World, nation: Nation, target: Nation, op: SpyOpDef) -> bool:
	var rng := world.rng
	nation.intel = maxf(0.0, nation.intel - op.cost)
	var spies := spies_of(world, nation)
	var ours := nation.intel + op.cost
	var share := ours / (ours + target.intel + 1.0)
	var success := rng.randf() < clampf(op.success * (0.6 + 0.8 * share) + 0.08 * spies.size(), 0.02, 0.95)
	var exposed := rng.randf() < op.exposure * (1.0 if success else 2.0) * (0.5 + (1.0 - share))
	var ids := PackedInt32Array([nation.id, target.id])
	var agent: Hero = spies[rng.randi_range(0, spies.size() - 1)] if not spies.is_empty() else null
	if success:
		var what := _apply(world, nation, target, op)
		if agent != null:
			agent.add_xp(world, 2.0)
			agent.add_deed(world, "%s против %s: %s" % [op.display_name.to_lower(), target.short_name, what])
		if op.kind == "assassinate" or op.kind == "bribe_vassal" or rng.randf() < 0.08:
			var who := ("шпион %s" % agent.display_name()) if agent != null else "агенты государства %s" % nation.short_name
			world.log_event(&"intrigue", "%s: %s — %s." % [op.display_name, who if exposed else "неизвестные", what],
					ids if exposed else PackedInt32Array([target.id]))
	if exposed:
		world.diplomacy.add_grudge(target.id, nation.id, op.scandal_grudge)
		var caught := agent != null and not success
		if caught or op.scandal_grudge >= 0.2 or rng.randf() < 0.3:
			world.log_event(&"intrigue", "Скандал: %s раскрывает %s — «%s» государства %s%s." % [target.name,
			"заговор" if success else "провалившийся заговор", op.display_name.to_lower(), nation.short_name,
				(", шпион %s схвачен" % agent.display_name()) if caught else ""], ids)
		if agent != null and not success and rng.randf() < 0.5:
			agent.die(world)
		var d := world.diplomacy
		if rng.randf() < op.scandal_war and d.war_between(target.id, nation.id) == null and not d.has_truce(target.id, nation.id, world.year):
			var war := d.declare_war(world, target.id, nation.id, &"espionage")
			world.log_event(&"war", "%s объявляет войну государству %s. %s." % [target.name, nation.name, war.name], ids)
	return success


## Последствия успешной операции; возвращает описание для летописи.
static func _apply(world: World, nation: Nation, target: Nation, op: SpyOpDef) -> String:
	var rng := world.rng
	match op.kind:
		"sabotage":
			var city := world.cities[target.city_ids[rng.randi_range(0, target.city_ids.size() - 1)]]
			var victims := Array(city.buildings).filter(func(b: StringName) -> bool: return b != &"wonder")
			if not victims.is_empty() and rng.randf() < 0.5:
				var b: StringName = victims[rng.randi_range(0, victims.size() - 1)]
				city.buildings.erase(b)
				CitySystem.recompute_building_effects(world, target)
				var def := EconomyDB.get_building(b)
				return "в городе %s сгорело: %s" % [city.name, def.display_name.to_lower() if def != null else str(b)]
			var g: int = [Goods.WOOD, Goods.STONE, Goods.METAL, Goods.GOLD][rng.randi_range(0, 3)]
			target.stock[g] = maxf(0.0, target.stock[g]) * 0.7
			return "в городе %s сгорели склады (%s)" % [city.name, Goods.NAMES[g].to_lower()]
		"incite":
			var regions := target.region_counts.keys()
			var region := world.regions[regions[rng.randi_range(0, regions.size() - 1)]]
			region.unrest += 0.6
			return "в регионе %s зреет мятеж" % region.name
		"steal_tech":
			var t := TechSystem._copyable(nation, target, rng)
			if t == null:
				for id in target.techs:
					var def := TechDB.find(id)
					if def != null and TechSystem.is_available(nation, def):
						t = def
						break
			if t != null:
				TechSystem.unlock(world, nation, t, "у шпионов в государстве %s" % target.short_name)
				return "похищено знание: %s" % t.display_name.to_lower()
			return "чертежи оказались пустышкой"
		"assassinate":
			var victim := target.ruler_display()
			target.reign_left = 0
			target.stability = maxf(0.0, target.stability - 0.1)
			return "убит %s" % victim
		"bribe_vassal":
			var vassals := world.diplomacy.vassals_of(world, target.id)
			var v := world.nations[vassals[rng.randi_range(0, vassals.size() - 1)]]
			nation.stock[Goods.GOLD] -= 100.0
			world.diplomacy.set_overlord(world, v.id, -1)
			if world.diplomacy.war_between(v.id, target.id) == null:
				world.diplomacy.declare_war(world, v.id, target.id, &"independence")
			return "подкупленный вассал %s отложился" % v.short_name
		"disinformation":
			var keys := target.borders.keys()
			var other: int = keys[rng.randi_range(0, keys.size() - 1)]
			if other == nation.id:
				other = keys[(keys.find(other) + 1) % keys.size()]
			world.diplomacy.add_grudge(target.id, other, 0.15)
			world.diplomacy.add_grudge(other, target.id, 0.1)
			return "%s и %s рассорены подмётными письмами" % [target.short_name, world.nations[other].short_name]
	return ""


static func spies_of(world: World, nation: Nation) -> Array[Hero]:
	var result: Array[Hero] = []
	for hid in nation.hero_ids:
		var h := world.heroes[hid]
		if h.alive and h.hero_class.id == &"spy":
			result.append(h)
	return result
