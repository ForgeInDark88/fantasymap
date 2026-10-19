class_name DiplomacySystem
extends RefCounted
## Дипломатия: торговые договоры, союзы, династические браки, вассалитет,
## коалиции против гегемона и решения о войне.
##
## Раз в год (в свой месяц) государство с некоторым шансом «смотрит» на одного
## случайного соседа. Желание воевать складывается из причин — земельный
## голод, богатства соседа, расовая вражда, месть, претензии на утраченные
## регионы — и умножается на агрессивность расы, формы правления и характера
## правителя, а также на соотношение сил. Миролюбивые расы (эльфы,
## полурослики) почти не нападают первыми, «незаметных» полуросликов реже
## выбирают целью.

## Базовый шанс в год, что желание воевать превратится в объявление войны.
const WAR_CHANCE := 0.3
## Доля занятой суши, после которой государство считается гегемоном.
const HEGEMON_SHARE := 0.22


## Раз в год для всего мира: обиды забываются, против гегемона собираются коалиции.
func tick_year(world: World) -> void:
	world.diplomacy.decay(world)
	_expire_claims(world)
	_coalitions(world)


## Годовые дипломатические решения одного государства (в его месяц).
func tick_nation(world: World, nation: Nation) -> void:
	var d := world.diplomacy
	var rng := world.rng
	if rng.randf() > 0.4:
		return
	_vassal_politics(world, nation)
	if nation.borders.is_empty():
		return
	var keys := nation.borders.keys()
	var other_id: int = keys[rng.randi_range(0, keys.size() - 1)]
	var other := world.nations[other_id]
	if other_id == nation.id or not other.alive or d.war_between(nation.id, other_id) != null:
		return
	var op := d.opinion(world, nation.id, other_id)
	var names := PackedInt32Array([nation.id, other_id])
	# Союзы распадаются, когда отношения портятся.
	if nation.allies.has(other_id) and op < 0.0:
		d.set_alliance(world, nation.id, other_id, false)
		world.log_event(&"treaty", "Распался союз %s и %s." % [nation.short_name, other.short_name], names)
		return
	if not nation.trade_partners.has(other_id) and op > 0.0 and rng.randf() < 0.15:
		d.set_trade(world, nation.id, other_id, true)
		world.log_event(&"treaty", "%s и %s заключили торговый договор." % [nation.short_name, other.short_name], names)
		return
	if not nation.allies.has(other_id) and op > 0.4 and rng.randf() < 0.08:
		d.set_alliance(world, nation.id, other_id, true)
		world.log_event(&"treaty", "%s и %s заключили союз." % [nation.short_name, other.short_name], names)
		return
	if _dynastic(nation) and _dynastic(other) and op > 0.15 and not d.married(nation.id, other_id, world.year) \
			and rng.randf() < 0.06:
		d.pair(nation.id, other_id).marriage_until = world.year + 40
		world.log_event(&"treaty", "Династический брак: род %s (%s) и род %s (%s) породнились." % [
			nation.dynasty, nation.short_name, other.dynasty, other.short_name], names)
		return
	_consider_war(world, nation, other, op)


static func _dynastic(nation: Nation) -> bool:
	return nation.government != null and nation.government.dynastic


func _consider_war(world: World, nation: Nation, target: Nation, op: float) -> void:
	var d := world.diplomacy
	if nation.allies.has(target.id) or d.has_truce(nation.id, target.id, world.year):
		return
	if nation.overlord == target.id or target.overlord == nation.id:
		return
	if nation.overlord >= 0 and nation.overlord == target.overlord:
		return
	var race := nation.race
	# Причины войны и их вес.
	var causes := {
		&"territory": 0.35 if nation.stalled_years >= 3 else 0.0,
		&"resources": 0.2 if (target.yields[Goods.GOLD] + target.yields[Goods.METAL]) > (nation.yields[Goods.GOLD] + nation.yields[Goods.METAL]) * 1.5 else 0.0,
		&"racial": maxf(0.0, -race.relation_to(target.race) - 0.3) * 0.6,
		&"revenge": d.grudge(nation.id, target.id) * 0.8,
		&"reconquest": 0.25 if d.has_claims_against(world, nation.id, target.id) else 0.0,
	}
	var desire := 0.3 * (0.5 - op)
	var main_cause: StringName = &"expansion"
	var best := 0.0
	for c in causes:
		desire += causes[c]
		if causes[c] > best:
			best = causes[c]
			main_cause = c
	desire *= race.aggression * nation.policy("aggression_mult")
	if race.has_trait(&"peaceful"):
		desire *= 0.05
	if target.race.has_trait(&"hidden"):
		desire *= 0.5
	desire *= pow(0.3, d.wars_of(nation.id).size())
	# Соотношение сил (с союзниками цели).
	var ours := nation.power()
	var theirs := target.power()
	for ally in target.allies:
		theirs += world.nations[ally].power() * 0.6
	var ratio := ours / maxf(theirs, 1.0)
	# Слабый на сильного почти не нападает; перевес сил разжигает аппетит.
	desire *= clampf(ratio - 0.7, 0.05, 2.0)
	if desire <= 0.0 or world.rng.randf() > desire * WAR_CHANCE:
		return
	var war := d.declare_war(world, nation.id, target.id, main_cause)
	world.log_event(&"war", "%s объявляет войну государству %s. %s." % [nation.name, target.name, war.name],
			PackedInt32Array([nation.id, target.id]))


## Вассалитет: слабые просятся под защиту, сильные вассалы отделяются,
## долгие вассалы своей расы мирно присоединяются к сюзерену.
func _vassal_politics(world: World, nation: Nation) -> void:
	var d := world.diplomacy
	var rng := world.rng
	if nation.overlord >= 0:
		var lord := world.nations[nation.overlord]
		if not lord.alive:
			nation.overlord = -1
			return
		if nation.power() > lord.power() * 0.7 and rng.randf() < 0.05:
			d.set_overlord(world, nation.id, -1)
			var war := d.declare_war(world, nation.id, lord.id, &"independence")
			world.log_event(&"war", "%s отказывается подчиняться %s. %s." % [nation.name, lord.name, war.name],
					PackedInt32Array([nation.id, lord.id]))
		elif lord.race == nation.race and world.year - nation.vassal_since > 60 \
				and nation.cell_count < lord.cell_count * 0.3 and rng.randf() < 0.02:
			for c in nation.cells.duplicate():
				world.set_owner(c, lord.id)
			world.log_event(&"vassal", "%s мирно вошло в состав государства %s." % [nation.name, lord.name],
					PackedInt32Array([nation.id, lord.id]))
		return
	if not d.wars_of(nation.id).is_empty() or d.vassals_of(world, nation.id).size() > 0:
		return
	for other in nation.borders:
		var o := world.nations[other]
		if o.overlord >= 0 or not o.alive:
			continue
		if nation.power() < o.power() * 0.15 and d.opinion(world, nation.id, other) > 0.0 and rng.randf() < 0.03:
			d.set_overlord(world, nation.id, other)
			world.log_event(&"vassal", "%s признаёт власть государства %s и становится его вассалом." % [nation.name, o.name],
					PackedInt32Array([nation.id, other]))
			return


## Гегемон — государство, занявшее слишком большую долю суши. Соседи, которые
## его опасаются, раз в несколько десятилетий объединяются в коалицию (союз).
func _coalitions(world: World) -> void:
	var d := world.diplomacy
	var total := 0
	var biggest: Nation = null
	for n in world.nations:
		if n.alive:
			total += n.cell_count
			if biggest == null or n.cell_count > biggest.cell_count:
				biggest = n
	d.hegemon = -1
	if biggest == null or total == 0 or biggest.cell_count < total * HEGEMON_SHARE:
		return
	d.hegemon = biggest.id
	if world.year - d.coalitions.get(biggest.id, -1000) < 40:
		return
	var members := PackedInt32Array()
	for other in biggest.borders:
		var o := world.nations[other]
		if o.alive and o.overlord != biggest.id and d.opinion(world, other, biggest.id) < 0.2:
			members.append(other)
	if members.size() < 2:
		return
	d.coalitions[biggest.id] = world.year
	for i in members.size():
		for j in range(i + 1, members.size()):
			d.set_alliance(world, members[i], members[j], true)
	var names := Array(members).map(func(id: int) -> String: return world.nations[id].short_name)
	world.log_event(&"treaty", "Против гегемона %s собрана коалиция: %s." % [biggest.name, ", ".join(names)],
			members + PackedInt32Array([biggest.id]))
	# Самый сильный участник может сразу начать войну коалиции.
	var leader := members[0]
	for m in members:
		if world.nations[m].power() > world.nations[leader].power():
			leader = m
	if d.war_between(leader, biggest.id) == null and not d.has_truce(leader, biggest.id, world.year) and world.rng.randf() < 0.5:
		var war := d.declare_war(world, leader, biggest.id, &"coalition")
		for m in members:
			if war.side_of(m) == 0:
				war.attackers.append(m)
		world.log_event(&"war", "Коалиция выступила против %s. %s." % [biggest.name, war.name],
				members + PackedInt32Array([biggest.id]))


func _expire_claims(world: World) -> void:
	if world.year % 10 != 0:
		return
	for region in world.regions:
		for id in region.claims.keys():
			if region.claims[id] < world.year or not world.nations[id].alive or region.controller() == id:
				region.claims.erase(id)
