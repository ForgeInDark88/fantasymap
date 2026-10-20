class_name Diplomacy
extends RefCounted
## Дипломатическое состояние мира: войны, перемирия, обиды (память о войнах).
## Союзы, торговые договоры и вассалитет хранятся в самих Nation
## (allies, trade_partners, overlord), а меняются только через этот класс.

const CAUSE_NAMES := {
	&"territory": "за земли", &"resources": "за богатства", &"racial": "расовая",
	&"holy": "священная", &"crusade": "крестовый поход", &"schism": "раскол", &"religious": "за веру",
	&"espionage": "возмездия", &"reunification": "за воссоединение",
	&"revenge": "мести", &"independence": "за независимость", &"civil": "гражданская",
	&"expansion": "завоевательная", &"reconquest": "за возвращение земель", &"coalition": "коалиции",
}

## Идущие войны; завершённые переносятся в past_wars (для летописи и истории).
var wars: Array[War] = []
var past_wars: Array[War] = []
var _next_war_id := 0
## Самое большое государство, против которого собирают коалиции (-1 — нет).
var hegemon := -1
## Против кого и в каком году последний раз собиралась коалиция: id → год.
var coalitions: Dictionary[int, int] = {}
## Пара государств → {truce_until: int, grudge: float}.
var _pairs: Dictionary = {}


static func key(a: int, b: int) -> int:
	return mini(a, b) * 65536 + maxi(a, b)


func pair(a: int, b: int) -> Dictionary:
	var k := key(a, b)
	if not _pairs.has(k):
		_pairs[k] = {"truce_until": -1, "grudge": 0.0, "marriage_until": -1}
	return _pairs[k]


func has_truce(a: int, b: int, year: int) -> bool:
	var k := key(a, b)
	return _pairs.has(k) and _pairs[k].truce_until > year


func married(a: int, b: int, year: int) -> bool:
	var k := key(a, b)
	return _pairs.has(k) and _pairs[k].get("marriage_until", -1) > year


func grudge(a: int, b: int) -> float:
	var k := key(a, b)
	return _pairs[k].grudge if _pairs.has(k) else 0.0


func war_between(a: int, b: int) -> War:
	for war in wars:
		if war.active:
			var sa := war.side_of(a)
			if sa != 0 and war.side_of(b) == -sa:
				return war
	return null


func wars_of(nation_id: int) -> Array[War]:
	var result: Array[War] = []
	for war in wars:
		if war.active and war.side_of(nation_id) != 0:
			result.append(war)
	return result


func active_wars() -> Array[War]:
	return wars.duplicate()


## Мнение a о b (-1..1): расовые отношения, договоры, обиды, трение на границе.
func opinion(world: World, a: int, b: int) -> float:
	var na := world.nations[a]
	var nb := world.nations[b]
	var o := na.race.relation_to(nb.race) * 0.7
	if na.race.has_trait(&"peaceful"):
		o += 0.1
	if nb.race.has_trait(&"feared"):
		o -= 0.25
	if na.allies.has(b):
		o += 0.3
	if na.trade_partners.has(b):
		o += 0.15
	if na.overlord == b or nb.overlord == a:
		o += 0.15
	elif na.overlord >= 0 and na.overlord == nb.overlord:
		o += 0.15
	if na.borders.has(b):
		o -= 0.08 * minf(1.0, na.borders[b] / 30.0)
	if married(a, b, world.year):
		o += 0.2
	# Харизма правителя b располагает к нему соседей.
	if nb.ruler_trait != null:
		o += nb.ruler_trait.charisma
	# Гегемона боятся все.
	if b == hegemon:
		o -= 0.15
	# Соседство под землёй без торговли — трения за пещеры и жилы.
	if na.tunnel_neighbors.has(b) and not na.trade_partners.has(b):
		o -= 0.05
	# Общие организации и общее имперское наследие сближают.
	o += OrgSystem.opinion_bonus(world, a, b)
	if na.legacy >= 0 and na.legacy == nb.legacy:
		o += LegacySystem.OPINION_BONUS
	# Мягкая сила: блестящая культура b располагает к ней.
	if nb.culture_level > na.culture_level:
		o += minf(0.15, (nb.culture_level - na.culture_level) / (na.culture_level + nb.culture_level + 10.0) * 0.3)
	# Единоверцы ближе, иноверцы — тем дальше, чем нетерпимее вера a.
	if na.state_religion >= 0 and nb.state_religion >= 0:
		if na.state_religion == nb.state_religion:
			o += 0.12
		else:
			o -= 0.1 * world.religions[na.state_religion].hostility(world.religions[nb.state_religion])
	# Претензии на земли друг друга.
	if has_claims_against(world, a, b):
		o -= 0.2
	o -= grudge(a, b)
	return clampf(o, -1.0, 1.0)


## Есть ли у a претензии на регионы, которые сейчас контролирует b.
func has_claims_against(world: World, a: int, b: int) -> bool:
	for rid in world.nations[b].region_counts:
		if world.regions[rid].claims.has(a):
			return true
	return false


func add_grudge(a: int, b: int, amount: float) -> void:
	var p := pair(a, b)
	p.grudge = clampf(p.grudge + amount, 0.0, 1.0)


func set_alliance(world: World, a: int, b: int, on: bool) -> void:
	if on:
		world.nations[a].allies[b] = true
		world.nations[b].allies[a] = true
	else:
		world.nations[a].allies.erase(b)
		world.nations[b].allies.erase(a)


func set_trade(world: World, a: int, b: int, on: bool) -> void:
	if on:
		world.nations[a].trade_partners[b] = true
		world.nations[b].trade_partners[a] = true
	else:
		world.nations[a].trade_partners.erase(b)
		world.nations[b].trade_partners.erase(a)


func set_overlord(world: World, vassal: int, overlord_id: int) -> void:
	world.nations[vassal].overlord = overlord_id
	world.nations[vassal].vassal_since = world.year
	# Цвет вассала смешивается с цветом сюзерена — рендер обновит палитру.
	world.ownership_version += 1


func vassals_of(world: World, nation_id: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for n in world.nations:
		if n.alive and n.overlord == nation_id:
			result.append(n.id)
	return result


## Объявление войны: в неё вступают союзники, сюзерены и вассалы сторон.
func declare_war(world: World, attacker: int, defender: int, cause: StringName) -> War:
	var war := War.new()
	war.id = _next_war_id
	_next_war_id += 1
	war.cause = cause
	war.start_year = world.year
	war.month = world.month
	war.day = world.day
	war.attackers.append(attacker)
	war.defenders.append(defender)
	var na := world.nations[attacker]
	var nd := world.nations[defender]
	# Защитника поддерживают союзники, сюзерен и вассалы (если не связаны с нападающим).
	var helpers := PackedInt32Array(nd.allies.keys())
	helpers.append_array(vassals_of(world, defender))
	# Общая оборона организаций (пакты, священные союзы, совет рас).
	helpers.append_array(OrgSystem.defenders_for(world, defender, attacker, cause))
	if nd.overlord >= 0 and cause != &"independence":
		helpers.append(nd.overlord)
	for h in helpers:
		if h != attacker and world.nations[h].alive and war.side_of(h) == 0 \
				and not world.nations[h].allies.has(attacker) and world.nations[h].overlord != attacker:
			war.defenders.append(h)
	# За нападающего — его вассалы и союзники, которые не любят жертву.
	for h in vassals_of(world, attacker):
		if war.side_of(h) == 0:
			war.attackers.append(h)
	for h in na.allies.keys():
		if war.side_of(h) == 0 and world.nations[h].alive and opinion(world, h, defender) < -0.1 and world.rng.randf() < 0.6:
			war.attackers.append(h)
	# Война рвёт договоры между сторонами.
	for a in war.attackers:
		for d in war.defenders:
			set_alliance(world, a, d, false)
			set_trade(world, a, d, false)
	war.name = "%s %s против %s" % [_cause_title(cause), na.short_name, nd.short_name]
	wars.append(war)
	return war


static func _cause_title(cause: StringName) -> String:
	match cause:
		&"racial":
			return "Расовая война:"
		&"holy":
			return "Священная война:"
		&"crusade":
			return "Крестовый поход:"
		&"schism":
			return "Война раскола:"
		&"religious":
			return "Восстание за веру:"
		&"espionage":
			return "Война возмездия:"
		&"reunification":
			return "Война за воссоединение:"
		&"independence":
			return "Освободительная война:"
		&"civil":
			return "Гражданская война:"
		&"divine":
			return "Война по воле богов:"
		&"demonic":
			return "Нашествие бездны:"
	var c: String = CAUSE_NAMES.get(cause, "")
	return "Война %s:" % c if not c.is_empty() else "Война:"


## Мир: перемирие между всеми участниками, обида проигравших.
func end_war(world: World, war: War, winner_side: int) -> void:
	war.active = false
	war.end_year = world.year
	wars.erase(war)
	past_wars.append(war)
	for a in war.attackers:
		for d in war.defenders:
			pair(a, d).truce_until = world.year + world.rng.randi_range(15, 30)
			if winner_side > 0:
				add_grudge(d, a, 0.3)
			elif winner_side < 0:
				add_grudge(a, d, 0.3)
			else:
				add_grudge(a, d, 0.1)


## Обиды со временем забываются (долгоживущие помнят дольше).
func decay(world: World) -> void:
	for k in _pairs:
		var p: Dictionary = _pairs[k]
		if p.grudge > 0.0:
			var a := int(k) / 65536
			var slow := world.nations[a].race.has_trait(&"long_lived") if a < world.nations.size() else false
			p.grudge = maxf(0.0, p.grudge - (0.004 if slow else 0.01))


## Государство исчезло: выходит из войн, договоров и вассалитета.
func forget_nation(world: World, nation_id: int) -> void:
	var nation := world.nations[nation_id]
	for other in nation.allies.keys():
		world.nations[other].allies.erase(nation_id)
	for other in nation.trade_partners.keys():
		world.nations[other].trade_partners.erase(nation_id)
	nation.allies.clear()
	nation.trade_partners.clear()
	for n in world.nations:
		if n.overlord == nation_id:
			n.overlord = -1
	for war in wars:
		if war.active and war.side_of(nation_id) != 0:
			war.remove_member(nation_id)
