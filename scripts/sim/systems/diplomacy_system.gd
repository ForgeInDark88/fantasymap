class_name DiplomacySystem
extends RefCounted
## Дипломатия: торговые договоры, союзы, вассалитет и решения о войне.
##
## Каждый год государство с некоторым шансом «смотрит» на одного случайного
## соседа. Желание воевать складывается из причин (земельный голод, богатства
## соседа, расовая вражда, месть) и умножается на агрессивность расы и
## соотношение сил; миролюбивые расы (эльфы, полурослики) почти никогда не
## нападают первыми, «незаметных» полуросликов реже выбирают целью.

## Базовый шанс в год, что желание воевать превратится в объявление войны.
const WAR_CHANCE := 0.3


func tick(world: World) -> void:
	var d := world.diplomacy
	d.decay(world)
	for nation in world.nations:
		if not nation.alive or world.rng.randf() > 0.4:
			continue
		_vassal_politics(world, nation)
		if nation.borders.is_empty():
			continue
		var keys := nation.borders.keys()
		var other: int = keys[world.rng.randi_range(0, keys.size() - 1)]
		if other == nation.id or not world.nations[other].alive or d.war_between(nation.id, other) != null:
			continue
		var op := d.opinion(world, nation.id, other)
		var rng := world.rng
		# Союзы распадаются, когда отношения портятся.
		if nation.allies.has(other) and op < 0.0:
			d.set_alliance(world, nation.id, other, false)
			world.log_event(&"treaty", "Распался союз %s и %s." % [nation.short_name, world.nations[other].short_name],
					PackedInt32Array([nation.id, other]))
			continue
		if not nation.trade_partners.has(other) and op > 0.0 and rng.randf() < 0.15:
			d.set_trade(world, nation.id, other, true)
			world.log_event(&"treaty", "%s и %s заключили торговый договор." % [nation.short_name, world.nations[other].short_name],
					PackedInt32Array([nation.id, other]))
			continue
		if not nation.allies.has(other) and op > 0.4 and rng.randf() < 0.08:
			d.set_alliance(world, nation.id, other, true)
			world.log_event(&"treaty", "%s и %s заключили союз." % [nation.short_name, world.nations[other].short_name],
					PackedInt32Array([nation.id, other]))
			continue
		_consider_war(world, nation, world.nations[other], op)


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
	}
	var desire := 0.3 * (0.5 - op)
	var main_cause: StringName = &"expansion"
	var best := 0.0
	for c in causes:
		desire += causes[c]
		if causes[c] > best:
			best = causes[c]
			main_cause = c
	desire *= race.aggression
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
