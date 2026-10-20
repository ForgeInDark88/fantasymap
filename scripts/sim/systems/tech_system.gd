class_name TechSystem
extends RefCounted
## Технологии (data/techs): исследование, выбор направления, распространение.
##
## Прирост «науки» государства (Nation.tech, его считает EconomySystem) — это
## очки исследований; к ним добавляются учёные-герои на службе (маги, рунные
## кузнецы, жрецы). Направление выбирается по характеру правителя, форме
## правления, вере (враждебные магии веры сторонятся магии), выходу к морю и
## склонности расы (мифриловая ковка — у дворфов, некромантия — у нежити,
## лесное зодчество — у эльфов). Технологии перенимаются у торговых партнёров,
## союзников, сюзерена и вассалов, а также при захвате городов.

## Очки исследований в год от одного учёного-героя на службе.
const SCHOLAR_RESEARCH := 0.008
## Шанс в год перенять технологию у одного партнёра (торговля, союз, вассалитет).
const SPREAD_CHANCE := 0.03
## Шанс получить технологию при захвате города.
const CAPTURE_CHANCE := 0.35
const SCHOLARS: Array[StringName] = [&"mage", &"runesmith", &"cleric"]


## Раз в сколько лет пересчитывать исследования (со сдвигом по id): очки копятся
## в Nation.tech и не теряются.
const PERIOD := 2


func tick(world: World, nation: Nation) -> void:
	if (world.year + nation.id + 1) % PERIOD != 0:
		return
	var gain := maxf(0.0, nation.tech - nation.tech_seen)
	nation.tech_seen = nation.tech
	for hid in nation.hero_ids:
		if SCHOLARS.has(world.heroes[hid].hero_class.id):
			gain += SCHOLAR_RESEARCH * PERIOD
	nation.research += gain
	if nation.researching == &"" or nation.techs.has(nation.researching):
		_choose(world, nation)
	var guard := 0
	while nation.researching != &"" and guard < 4:
		var t := TechDB.find(nation.researching)
		if t == null or nation.research < t.cost:
			break
		nation.research -= t.cost
		unlock(world, nation, t, "")
		_choose(world, nation)
		guard += 1
	_diffuse(world, nation)


## Открытие технологии. how — как получена («у партнёра», «в захваченном городе»), "" — своё открытие.
static func unlock(world: World, nation: Nation, t: TechDef, how: String) -> void:
	if nation.techs.has(t.id):
		return
	nation.techs[t.id] = true
	if nation.researching == t.id:
		nation.researching = &""
	apply_effects(nation)
	var ids := PackedInt32Array([nation.id])
	if how.is_empty():
		if t.notable:
			world.log_event(&"tech", "%s открывает: %s — %s" % [nation.name, t.display_name, t.description.to_lower()], ids)
	elif t.notable and world.rng.randf() < 0.5:
		world.log_event(&"tech", "%s перенимает %s: %s." % [nation.name, how, t.display_name.to_lower()], ids)


## Сводит эффекты всех открытых технологий в Nation.effects (источник &"techs").
static func apply_effects(nation: Nation) -> void:
	var d := {}
	for id in nation.techs:
		var t := TechDB.find(id)
		if t == null:
			continue
		for k in t.effects:
			if String(k).ends_with("_mult"):
				d[k] = d.get(k, 1.0) * t.effects[k]
			else:
				d[k] = d.get(k, 0.0) + t.effects[k]
	nation.set_effects(&"techs", d)


static func is_available(nation: Nation, t: TechDef) -> bool:
	if nation.techs.has(t.id) or t.race_weight(nation.race) <= 0.0:
		return false
	for req in t.requires:
		if not nation.techs.has(req):
			return false
	return true


## Выбор следующей технологии: склонность расы × вкус правителя и власти × дешевизна.
func _choose(world: World, nation: Nation) -> void:
	var options: Array[TechDef] = []
	var weights := PackedFloat32Array()
	var total := 0.0
	for res in TechDB.all():
		var t := res as TechDef
		if not is_available(nation, t):
			continue
		var w := t.race_weight(nation.race) * branch_taste(world, nation, t.branch) / t.cost
		options.append(t)
		weights.append(w)
		total += w
	nation.researching = &""
	if options.is_empty():
		return
	var roll := world.rng.randf() * total
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			nation.researching = options[i].id
			return
	nation.researching = options[options.size() - 1].id


## Насколько государству по душе ветка исследований.
static func branch_taste(world: World, nation: Nation, branch: String) -> float:
	var w := 1.0
	var trait_id := nation.ruler_trait.id if nation.ruler_trait != null else &""
	var gov := nation.government.id if nation.government != null else &""
	match branch:
		"military":
			if trait_id == &"warlike" or trait_id == &"tyrant":
				w *= 2.0
			if gov == &"empire" or gov == &"clans" or gov == &"tribal":
				w *= 1.4
			if trait_id == &"peaceful":
				w *= 0.5
		"economy":
			if trait_id == &"greedy" or trait_id == &"builder":
				w *= 1.8
			if gov == &"republic" or gov == &"oligarchy":
				w *= 1.4
		"society":
			if trait_id == &"wise" or trait_id == &"pious":
				w *= 1.8
			if gov == &"theocracy":
				w *= 1.5
		"magic":
			if trait_id == &"wise" or trait_id == &"mad":
				w *= 1.6
			if gov == &"necrocracy":
				w *= 1.6
			if nation.state_religion >= 0 and nation.state_religion < world.religions.size():
				w *= clampf(1.0 + world.religions[nation.state_religion].magic, 0.1, 2.0)
		"navy":
			var coastal := false
			for id in nation.city_ids:
				if world.cities[id].coastal:
					coastal = true
					break
			w *= 1.3 if coastal else 0.15
			if gov == &"republic" or gov == &"oligarchy":
				w *= 1.3
	return w


## Знание расходится по договорам: торговля, союзы, сюзерен и вассалы.
func _diffuse(world: World, nation: Nation) -> void:
	var rng := world.rng
	var partners: Array[int] = []
	partners.append_array(nation.trade_partners.keys())
	partners.append_array(nation.allies.keys())
	if nation.overlord >= 0:
		partners.append(nation.overlord)
	for p in partners:
		if rng.randf() > SPREAD_CHANCE * PERIOD:
			continue
		var other := world.nations[p]
		var t := _copyable(nation, other, rng)
		if t != null:
			var how := "у союзника %s" % other.short_name if nation.allies.has(p) else ("у сюзерена %s" % other.short_name if p == nation.overlord else "у торговых партнёров %s" % other.short_name)
			unlock(world, nation, t, how)


## Случайная технология other, которую nation может перенять (все требования есть).
## Чужое расовое искусство перенимается с трудом: шанс — склонность расы (не больше 1).
static func _copyable(nation: Nation, other: Nation, rng: RandomNumberGenerator) -> TechDef:
	var options: Array[TechDef] = []
	for id in other.techs:
		var t := TechDB.find(id)
		if t != null and is_available(nation, t):
			options.append(t)
	if options.is_empty():
		return null
	var t := options[rng.randi_range(0, options.size() - 1)]
	return t if rng.randf() < minf(1.0, t.race_weight(nation.race)) else null


## Захват города: победитель может унести знания побеждённого.
static func on_city_captured(world: World, winner: Nation, loser: Nation) -> void:
	if winner == null or loser == null or world.rng.randf() > CAPTURE_CHANCE:
		return
	var t := _copyable(winner, loser, world.rng)
	if t != null:
		unlock(world, winner, t, "в захваченных городах %s" % loser.short_name)
