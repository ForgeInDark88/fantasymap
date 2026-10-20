class_name OrgSystem
extends RefCounted
## Международные организации (data/orgs; раз в год для всего мира).
##
## Каждые несколько лет проверяется, не пора ли собраться новой организации:
## торговой лиге — у купеческих держав с договорами, ордену магов — у
## знающих тайное знание, военному пакту — у соседей гегемона, священному
## союзу — у единоверцев, совету рас — пока в мире есть демоны. Подходящие
## государства вступают, нарушители (воюющие с другими членами, сменившие веру,
## разочарованные) выходят или исключаются; малочисленная организация распадается.
## Члены платят взносы, получают бонусы, не воюют друг с другом, а при общей
## обороне вступают в войну за напавшего на них. Механику коалиций против
## гегемона это расширяет, а не заменяет.

## Раз в сколько лет искать возможность новой организации.
const FORM_PERIOD := 5
## Причины войн, в которые общая оборона не втягивает (внутренние смуты).
const INTERNAL_CAUSES: Array[StringName] = [&"civil", &"independence", &"schism", &"religious"]
## Сколько лет вышедшему нельзя вернуться.
const REJOIN_YEARS := 20
## Раз в сколько лет принимать новых членов (со сдвигом по id организации).
const JOIN_PERIOD := 4


func tick_year(world: World) -> void:
	for org in world.orgs:
		if org.alive:
			_update(world, org)
	if world.year % FORM_PERIOD == 0:
		for res in OrgDB.orgs():
			var def := res as OrgDef
			if _count(world, def) < def.max_count:
				try_form(world, def)
	_apply_membership(world)


## Пытается собрать организацию (панель Бога — с основателем founder).
static func try_form(world: World, def: OrgDef, founder: Nation = null) -> Organization:
	var faith := -1
	if founder == null:
		var candidates := _candidates(world, def, -1, null)
		if def.basis == "faith":
			# Вера с наибольшим числом держав и без своего союза.
			var counts := {}
			for n in candidates:
				if not _faith_has_union(world, n.state_religion):
					counts[n.state_religion] = counts.get(n.state_religion, 0) + 1
			for r in counts:
				if counts[r] >= def.min_members and (faith < 0 or counts[r] > counts[faith]):
					faith = r
			if faith < 0:
				return null
		for n in candidates:
			if (faith < 0 or n.state_religion == faith) and (founder == null or n.power() > founder.power()):
				founder = n
		if founder == null:
			return null
	else:
		faith = founder.state_religion if def.basis == "faith" else -1
	var members := _gather(world, def, founder, faith)
	if members.size() < def.min_members and founder != null and members.size() < 2:
		return null
	if members.size() < def.min_members:
		return null
	var org := Organization.new()
	org.id = world.orgs.size()
	org.def = def
	org.founder = founder.id
	org.founded_year = world.year
	org.faith = faith
	org.members = members
	org.name = def.name_template.format({"name": founder.short_name,
		"faith": world.religions[faith].name if faith >= 0 else ""})
	world.orgs.append(org)
	world.log_event(&"org", "Основана организация «%s»: %s." % [org.name,
		", ".join(Array(members).map(func(id: int) -> String: return world.nations[id].short_name))], members)
	_apply_membership(world)
	return org


func _update(world: World, org: Organization) -> void:
	var def := org.def
	var d := world.diplomacy
	var keep := PackedInt32Array()
	for m in org.members:
		var n := world.nations[m]
		if not n.alive:
			continue
		var reason := ""
		if not _qualifies(world, def, n, org.faith, true):
			reason = "больше не отвечает уставу"
		elif def.no_war:
			for other in org.members:
				if other != m and keep.has(other) and d.war_between(m, other) != null:
					reason = "исключено за войну с %s" % world.nations[other].short_name
					break
		if reason.is_empty() and org.founder != m and org.founder >= 0 and world.rng.randf() < 0.3 \
				and world.nations[org.founder].alive and d.opinion(world, m, org.founder) < -0.35:
			reason = "покинуло её, рассорившись с основателем"
		if reason.is_empty():
			keep.append(m)
		else:
			org.banned[m] = world.year + REJOIN_YEARS
			if reason.begins_with("исключено") or world.rng.randf() < 0.3:
				world.log_event(&"org", "%s выходит из организации «%s»: %s." % [n.name, org.name, reason], PackedInt32Array([m]))
	org.members = keep
	# Приём новых: подходящие и связанные с членами (раз в несколько лет).
	var joining: Array[Nation] = []
	if (world.year + org.id) % JOIN_PERIOD == 0:
		joining = _candidates(world, def, org.faith, org)
	for n in joining:
		if keep.has(n.id) or world.rng.randf() > 0.3 or org.banned.get(n.id, -1) > world.year:
			continue
		if _connected(world, def, n, org.members):
			org.members.append(n.id)
			if world.rng.randf() < 0.25:
				world.log_event(&"org", "%s вступает в организацию «%s»." % [n.name, org.name], PackedInt32Array([n.id]))
	if org.founder >= 0 and not org.members.has(org.founder) and not org.members.is_empty():
		org.founder = org.members[0]
	if org.members.size() < 2 or (def.basis == "abyss" and not _demons_exist(world)) or (def.basis == "crisis" and world.crisis.is_empty()) \
			or (def.basis == "hegemon" and d.hegemon < 0 and world.year - org.founded_year > 20):
		org.alive = false
		var why := "Врата бездны больше не грозят миру" if def.basis == "abyss" else ("угроза миновала" if def.basis == "hegemon" or def.basis == "crisis" else "в ней не осталось членов")
		world.log_event(&"org", "Организация «%s» распущена: %s." % [org.name, why], org.members)
		return
	# Взносы.
	for m in org.members:
		var n := world.nations[m]
		n.stock[Goods.GOLD] -= maxf(0.0, n.income[Goods.GOLD]) * def.dues


## Эффекты членства — в Nation.effects (источник &"orgs"), кэш Nation.org_ids.
static func _apply_membership(world: World) -> void:
	var per := {}
	var ids := {}
	for org in world.orgs:
		if not org.alive:
			continue
		for m in org.members:
			var list: PackedInt32Array = ids.get(m, PackedInt32Array())
			list.append(org.id)
			ids[m] = list
			var d: Dictionary = per.get(m, {})
			for k in org.def.effects:
				if String(k).ends_with("_mult"):
					d[k] = d.get(k, 1.0) * org.def.effects[k]
				else:
					d[k] = d.get(k, 0.0) + org.def.effects[k]
			per[m] = d
	for n in world.nations:
		if not n.alive:
			continue
		var new_ids: PackedInt32Array = ids.get(n.id, PackedInt32Array())
		if new_ids != n.org_ids:
			n.org_ids = new_ids
			n.set_effects(&"orgs", per.get(n.id, {}))


static func _count(world: World, def: OrgDef) -> int:
	var c := 0
	for org in world.orgs:
		if org.alive and org.def == def:
			c += 1
	return c


## Государства, подходящие под устав и не состоящие в другой организации того же вида.
static func _candidates(world: World, def: OrgDef, faith: int, org: Organization) -> Array[Nation]:
	var taken := {}
	for o in world.orgs:
		if o.alive and o.def == def and o != org:
			for m in o.members:
				taken[m] = true
	var result: Array[Nation] = []
	for n in world.nations:
		if n.alive and not taken.has(n.id) and _qualifies(world, def, n, faith):
			result.append(n)
	return result


## member — уже состоит (условия мягче: торговой лиге хватит одного договора).
static func _qualifies(world: World, def: OrgDef, n: Nation, faith: int, member: bool = false) -> bool:
	for t in def.excluded_traits:
		if n.race.has_trait(t):
			return false
	if n.capital_city < 0:
		return false
	match def.basis:
		"trade":
			return n.trade_partners.size() >= (1 if member else def.min_trade_partners)
		"tech":
			return n.techs.has(def.requires_tech)
		"faith":
			return n.state_religion >= 0 and (faith < 0 or n.state_religion == faith)
		"hegemon":
			var h := world.diplomacy.hegemon
			return h >= 0 and h != n.id and n.overlord != h and (member or (n.borders.has(h)
					and world.diplomacy.opinion(world, n.id, h) < 0.2))
		"abyss":
			return _demons_exist(world) and n.army > 2000.0
		"crisis":
			return not world.crisis.is_empty() and n.army > 2000.0 and n.id != int(world.crisis.get("invader", -1))
	return false


## Связан ли кандидат с организацией (торговля — договором с членом, пакт — общий враг…).
static func _connected(world: World, def: OrgDef, n: Nation, members: PackedInt32Array) -> bool:
	if def.basis != "trade":
		return true
	for m in members:
		if n.trade_partners.has(m):
			return true
	return false


static func _gather(world: World, def: OrgDef, founder: Nation, faith: int) -> PackedInt32Array:
	var members := PackedInt32Array([founder.id])
	var candidates := _candidates(world, def, faith, null)
	var grew := true
	while grew:
		grew = false
		for n in candidates:
			if not members.has(n.id) and _connected(world, def, n, members):
				members.append(n.id)
				grew = true
	return members


static func _faith_has_union(world: World, faith: int) -> bool:
	for o in world.orgs:
		if o.alive and o.def.basis == "faith" and o.faith == faith:
			return true
	return false


static func _demons_exist(world: World) -> bool:
	for n in world.nations:
		if n.alive and n.race.has_trait(&"demonic"):
			return true
	return false


# ---------------------------------------------------------------------------
# Правила (вызываются дипломатией)
# ---------------------------------------------------------------------------

## Организации государства.
static func orgs_of(world: World, nation_id: int) -> Array[Organization]:
	var result: Array[Organization] = []
	for id in world.nations[nation_id].org_ids:
		var org := world.orgs[id]
		if org.alive and org.members.has(nation_id):
			result.append(org)
	return result


## Запрещена ли война между a и b уставом общей организации.
static func war_forbidden(world: World, a: int, b: int) -> bool:
	for id in world.nations[a].org_ids:
		var org := world.orgs[id]
		if org.alive and org.def.no_war and org.members.has(b):
			return true
	return false


## Насколько общие организации сближают a и b.
static func opinion_bonus(world: World, a: int, b: int) -> float:
	var bonus := 0.0
	for id in world.nations[a].org_ids:
		var org := world.orgs[id]
		if org.alive and org.members.has(b):
			bonus += org.def.opinion_bonus
	return bonus


## Союзники по общей обороне защитника (кроме внутренних смут).
static func defenders_for(world: World, defender: int, attacker: int, cause: StringName) -> PackedInt32Array:
	var result := PackedInt32Array()
	if INTERNAL_CAUSES.has(cause):
		return result
	for id in world.nations[defender].org_ids:
		var org := world.orgs[id]
		if not org.alive or not org.def.mutual_defense or not org.members.has(defender) or org.members.has(attacker):
			continue
		for m in org.members:
			if m != defender and not result.has(m):
				result.append(m)
	return result
