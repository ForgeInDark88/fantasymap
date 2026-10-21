class_name DealSystem
extends RefCounted
## Дипломатия и ИИ государств (этап 11.E): характеры, сделки, журнал, перенос
## столицы. Раз в год в «свой» день государства (после прежней дипломатии):
##   • характер (data/personalities) — по народу и форме правления; новый
##     правитель может его сменить; воинственность — эффект &"aggression_mult";
##   • сделка с соседом, торговым партнёром или врагом: продажа края за
##     золото, обмен товарами (рынок 11.D), обмен знаниями, выкуп мира,
##     пакт о ненападении, субсидия за вступление в войну. Вид — по вкусу
##     характера и тому, что вообще возможно; партнёр решает по мнению,
##     выгоде и своему характеру; отказ копит обиду;
##   • журнал дипломатии (World.diplo_journal): все предложения — принятые и
##     отвергнутые;
##   • перенос столицы — к крупному городу у сердца земель или прочь от фронта.

const DEAL_CHANCE := 0.25
const JOURNAL_LIMIT := 600
## Пакт о ненападении: лет.
const PACT_YEARS := 10
## Шанс в год перенести столицу (× характер); под угрозой — выше.
const RELOCATE_CHANCE := 0.02
const RELOCATE_THREAT := 0.25
const KINDS := {&"region": "продажа края", &"goods": "обмен товарами", &"tech": "обмен знаниями", &"peace": "выкуп мира",
	&"pact": "пакт о ненападении", &"subsidy": "субсидия за войну"}


## Характер государства (выбирается при первой нужде и при смене правителя).
static func ensure_personality(world: World, n: Nation) -> PersonalityDef:
	if n.personality != null and n.personality_ruler == n.ruler_name:
		return n.personality
	var rng := world.rng
	if n.personality != null and rng.randf() > 0.25:
		n.personality_ruler = n.ruler_name
		return n.personality
	var gov := n.government.id if n.government != null else &""
	var total := 0.0
	var weights: Array[float] = []
	var defs := PersonalityDB.all()
	for d in defs:
		var p: PersonalityDef = d
		var w := p.weight * float(p.races.get(n.race.id, 1.0)) * float(p.governments.get(gov, 1.0))
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	var pick: PersonalityDef = defs[defs.size() - 1]
	for i in defs.size():
		roll -= weights[i]
		if roll <= 0.0:
			pick = defs[i]
			break
	var changed := n.personality != null and n.personality != pick
	n.personality = pick
	n.personality_ruler = n.ruler_name
	n.set_effects(&"personality", {"aggression_mult": pick.aggression})
	if changed:
		world.log_event(&"deal", "При правителе %s %s меняет нрав: теперь это %s." % [n.ruler_display(), n.short_name, pick.display_name.to_lower()],
			PackedInt32Array([n.id]))
	return pick


static func journal(world: World, kind: StringName, a: int, b: int, ok: bool, text: String) -> void:
	world.diplo_journal.append({"year": world.year, "month": world.month, "kind": kind, "a": a, "b": b, "ok": ok, "text": text})
	if world.diplo_journal.size() > JOURNAL_LIMIT:
		world.diplo_journal = world.diplo_journal.slice(world.diplo_journal.size() - JOURNAL_LIMIT)


func tick(world: World, nation: Nation) -> void:
	var p := ensure_personality(world, nation)
	var rng := world.rng
	_relocate(world, nation, p)
	if nation.race.has_trait(&"demonic") or rng.randf() > DEAL_CHANCE * p.deal_rate:
		return
	var partners := PackedInt32Array()
	for o in nation.borders:
		partners.append(o)
	for o in nation.trade_partners:
		if not partners.has(o):
			partners.append(o)
	for w in world.diplomacy.wars_of(nation.id):
		for e in w.members(-w.side_of(nation.id)):
			if not partners.has(e):
				partners.append(e)
	if partners.is_empty():
		return
	var other := world.nations[partners[rng.randi_range(0, partners.size() - 1)]]
	if not other.alive or other.id == nation.id or other.race.has_trait(&"demonic"):
		return
	ensure_personality(world, other)
	# Виды сделок, что возможны сейчас, — по вкусу характера.
	var options: Array = []
	var total := 0.0
	for kind in KINDS:
		var offer := _offer(world, kind, nation, other)
		if offer.is_empty():
			continue
		var w := float(p.deal_taste.get(kind, 1.0))
		options.append([w, offer])
		total += w
	if options.is_empty():
		return
	var roll := rng.randf() * total
	var chosen: Dictionary = options[options.size() - 1][1]
	for o in options:
		roll -= float(o[0])
		if roll <= 0.0:
			chosen = o[1]
			break
	propose(world, chosen)


## Предложение: что, кто, кому, цена. Пусто — такой сделки сейчас не выйдет.
func _offer(world: World, kind: StringName, a: Nation, b: Nation) -> Dictionary:
	var d := world.diplomacy
	var war := d.war_between(a.id, b.id)
	match kind:
		&"region":
			if war != null:
				return {}
			# Продаёт тот, у кого есть дальний неверный край у границы покупателя.
			for pair in [[b, a], [a, b]]:
				var seller: Nation = pair[0]
				var buyer: Nation = pair[1]
				var rid := _sale_region(world, seller, buyer)
				if rid >= 0:
					var price := float(seller.region_counts[rid]) * 3.0 * buyer.inflation + 20.0
					if buyer.stock[Goods.GOLD] >= price * 1.2:
						return {"kind": kind, "from": a.id, "to": b.id, "seller": seller.id, "buyer": buyer.id, "region": rid, "price": price}
		&"goods":
			if war != null or a.market_price.size() != MarketDB.size() or b.market_price.size() != MarketDB.size():
				return {}
			var give := -1
			var take := -1
			var best_give := 0.0
			var best_take := 0.0
			for i in MarketDB.size():
				var a_spare := a.market_stock[i] - a.market_demand[i] * 0.5
				var b_need := b.market_demand[i] - b.market_used[i]
				if a_spare > 1.0 and b_need > 0.5 and a_spare * b.market_price[i] > best_give:
					best_give = a_spare * b.market_price[i]
					give = i
				var b_spare := b.market_stock[i] - b.market_demand[i] * 0.5
				var a_need := a.market_demand[i] - a.market_used[i]
				if b_spare > 1.0 and a_need > 0.5 and b_spare * a.market_price[i] > best_take:
					best_take = b_spare * a.market_price[i]
					take = i
			if give < 0 or take < 0 or give == take:
				return {}
			# Обмен по стоимости: на сколько хватит меньшей стороны.
			var value := minf(best_give, best_take) * 0.5
			return {"kind": kind, "from": a.id, "to": b.id, "give": give, "take": take,
				"give_amount": value / maxf(0.01, b.market_price[give]), "take_amount": value / maxf(0.01, a.market_price[take])}
		&"tech":
			if war != null:
				return {}
			var t1 := TechSystem._copyable(a, b, world.rng)
			var t2 := TechSystem._copyable(b, a, world.rng)
			if t1 == null or t2 == null:
				return {}
			return {"kind": kind, "from": a.id, "to": b.id, "a_gets": str(t1.id), "b_gets": str(t2.id)}
		&"peace":
			if war == null or world.year - war.start_year < 4:
				return {}
			if war.leader(1) != a.id and war.leader(-1) != a.id:
				return {}
			if war.leader(1) != b.id and war.leader(-1) != b.id:
				return {}
			# Платит тот, кто проигрывает (по счёту войны).
			var a_side := war.side_of(a.id)
			var payer := a if war.score * a_side < 0.0 else b
			var payee := b if payer == a else a
			var price := absf(war.score) * 4.0 + 30.0
			if payer.stock[Goods.GOLD] < price:
				return {}
			return {"kind": kind, "from": a.id, "to": b.id, "war": war.id, "payer": payer.id, "payee": payee.id, "price": price}
		&"pact":
			if war != null or d.has_truce(a.id, b.id, world.year) or a.allies.has(b.id) or not a.borders.has(b.id):
				return {}
			return {"kind": kind, "from": a.id, "to": b.id}
		&"subsidy":
			# a воюет; b не воюет и не дружит с врагом a — за золото вступает в войну на стороне a.
			if war != null or not d.wars_of(b.id).is_empty():
				return {}
			for w in d.wars_of(a.id):
				var side := w.side_of(a.id)
				if w.leader(side) != a.id:
					continue
				var enemy := w.leader(-side)
				if enemy < 0 or b.allies.has(enemy) or b.overlord >= 0 or not b.borders.has(enemy):
					continue
				var price := b.army * 0.01 + 60.0
				if a.stock[Goods.GOLD] < price * 1.5:
					continue
				return {"kind": kind, "from": a.id, "to": b.id, "war": w.id, "enemy": enemy, "price": price}
	return {}


## Край, который seller готов продать buyer: не столица, у границы покупателя,
## малый, неверный (лояльность низкая или чужая культура).
static func _sale_region(world: World, seller: Nation, buyer: Nation) -> int:
	var cap_region := world.region_of[world.cities[seller.capital_city].cell] if seller.capital_city >= 0 else -1
	for rid in seller.region_counts:
		var region := world.regions[rid]
		if rid == cap_region or region.controller() != seller.id or seller.region_counts[rid] > seller.cell_count / 4:
			continue
		# Продают «чужой» край тому, чей народ или культура в нём живёт: продавцу он неверен, покупателю — родной.
		if region.loyalty > 0.6 and region.culture == seller.culture:
			continue
		if region.culture != buyer.culture and world.region_majority_race(region, seller.id) != buyer.race.index:
			continue
		var touches := region.owner_counts.has(buyer.id)
		if not touches:
			for nb in region.neighbors:
				if world.regions[nb].owner_counts.has(buyer.id):
					touches = true
					break
		if touches:
			return rid
	return -1


## Партнёр решает. Принято — сделка исполняется; запись в журнал в любом случае.
static func propose(world: World, offer: Dictionary) -> bool:
	var rng := world.rng
	var d := world.diplomacy
	var a := world.nations[int(offer.from)]
	var b := world.nations[int(offer.to)]
	var pa := ensure_personality(world, a)
	var pb := ensure_personality(world, b)
	var kind: StringName = offer.kind
	var accept := d.opinion(world, b.id, a.id) * 0.5 + 0.35 + (pb.deal_rate - 1.0) * 0.15 + (pb.generosity - 0.5) * 0.2
	match kind:
		&"region":
			# Продавцу нужны деньги или край ему чужд; покупателю — земля.
			var seller := world.nations[int(offer.seller)]
			if seller.stock[Goods.GOLD] < 0.0:
				accept += 0.25
			if world.regions[int(offer.region)].loyalty < 0.4:
				accept += 0.15
			if seller.personality != null and seller.personality.id == &"conqueror":
				accept -= 0.4
		&"goods":
			accept += 0.25
		&"tech":
			accept += 0.15
		&"peace":
			var payee := world.nations[int(offer.payee)]
			accept += 0.1 + (0.2 if payee.personality.aggression < 1.0 else -0.25)
		&"pact":
			accept += (0.2 if pb.aggression < 1.0 else -0.2)
		&"subsidy":
			accept += -0.1 - d.opinion(world, b.id, int(offer.enemy)) * 0.4 + (pb.aggression - 1.0) * 0.3
	var ok := rng.randf() < clampf(accept, 0.02, 0.95)
	var text := _describe(world, offer, ok)
	journal(world, kind, a.id, b.id, ok, text)
	world.count(&"deals_proposed")
	if not ok:
		d.add_grudge(a.id, b.id, 0.02 * pa.grudge)
		return false
	world.count(&"deals")
	_execute(world, offer)
	d.add_grudge(a.id, b.id, -0.03)
	d.add_grudge(b.id, a.id, -0.03)
	if kind in [&"region", &"peace", &"subsidy"] or rng.randf() < 0.2:
		world.log_event(&"deal", text, PackedInt32Array([a.id, b.id]))
	return true


static func _execute(world: World, offer: Dictionary) -> void:
	var d := world.diplomacy
	var a := world.nations[int(offer.from)]
	var b := world.nations[int(offer.to)]
	match StringName(offer.kind):
		&"region":
			var seller := world.nations[int(offer.seller)]
			var buyer := world.nations[int(offer.buyer)]
			var price := float(offer.price)
			buyer.stock[Goods.GOLD] -= price
			seller.stock[Goods.GOLD] += price
			for c in world.regions[int(offer.region)].cells:
				if world.owner[c] == seller.id:
					world.set_owner(c, buyer.id)
			world.count(&"regions_sold")
		&"goods":
			var gi := int(offer.give)
			var ti := int(offer.take)
			var ga := minf(float(offer.give_amount), a.market_stock[gi])
			var ta := minf(float(offer.take_amount), b.market_stock[ti])
			a.market_stock[gi] -= ga
			b.market_stock[gi] += ga
			b.market_stock[ti] -= ta
			a.market_stock[ti] += ta
		&"tech":
			TechSystem.unlock(world, a, TechDB.find(StringName(offer.a_gets)), "по договору")
			TechSystem.unlock(world, b, TechDB.find(StringName(offer.b_gets)), "по договору")
		&"peace":
			for w in d.wars:
				if w.id == int(offer.war):
					var payer := world.nations[int(offer.payer)]
					var payee := world.nations[int(offer.payee)]
					payer.stock[Goods.GOLD] -= float(offer.price)
					payee.stock[Goods.GOLD] += float(offer.price)
					d.end_war(world, w, 0)
					world.count(&"peace_bought")
					break
		&"pact":
			d.pair(a.id, b.id).truce_until = world.year + PACT_YEARS
		&"subsidy":
			for w in d.wars:
				if w.id == int(offer.war) and w.side_of(b.id) == 0:
					a.stock[Goods.GOLD] -= float(offer.price)
					b.stock[Goods.GOLD] += float(offer.price)
					if w.side_of(a.id) > 0:
						w.attackers.append(b.id)
					else:
						w.defenders.append(b.id)
					d.set_alliance(world, a.id, b.id, true)
					break


static func _describe(world: World, offer: Dictionary, ok: bool) -> String:
	var a := world.nations[int(offer.from)].short_name
	var b := world.nations[int(offer.to)].short_name
	var verdict := "согласилось" if ok else "отказало"
	match StringName(offer.kind):
		&"region":
			var r := world.regions[int(offer.region)]
			return "%s предлагает: край %s — государству %s за %d золота. %s %s." % [a, r.name, world.nations[int(offer.buyer)].short_name,
				roundi(float(offer.price)), b, verdict]
		&"goods":
			var g1: GoodDef = MarketDB.all()[int(offer.give)]
			var g2: GoodDef = MarketDB.all()[int(offer.take)]
			return "%s предлагает государству %s обмен: %s на %s. %s %s." % [a, b, g1.display_name.to_lower(), g2.display_name.to_lower(), b, verdict]
		&"tech":
			return "%s и %s: обмен знаниями (%s ↔ %s). %s %s." % [a, b, TechDB.find(StringName(offer.a_gets)).display_name,
				TechDB.find(StringName(offer.b_gets)).display_name, b, verdict]
		&"peace":
			return "%s предлагает %s выкуп мира: %s платит %d золота. %s %s." % [a, b, world.nations[int(offer.payer)].short_name,
				roundi(float(offer.price)), b, verdict]
		&"pact":
			return "%s предлагает государству %s пакт о ненападении на %d лет. %s %s." % [a, b, PACT_YEARS, b, verdict]
		&"subsidy":
			return "%s предлагает государству %s %d золота за войну против %s. %s %s." % [a, b, roundi(float(offer.price)),
				world.nations[int(offer.enemy)].short_name, b, verdict]
	return ""


## Перенос столицы: к большому городу у сердца земель — или прочь от фронта.
func _relocate(world: World, n: Nation, p: PersonalityDef) -> void:
	if n.capital_city < 0 or n.city_ids.size() < 2:
		return
	var rng := world.rng
	var cap := world.cities[n.capital_city]
	var center := n.centroid()
	var cap_region := world.regions[world.region_of[cap.cell]]
	var threatened := false
	for w in world.diplomacy.wars_of(n.id):
		for e in w.members(-w.side_of(n.id)):
			if cap_region.owner_counts.has(e) or w.siege_region == cap_region.id:
				threatened = true
	var chance := (RELOCATE_THREAT if threatened else RELOCATE_CHANCE) * p.relocation
	# Недавно переехавшие не спешат снова (под угрозой — через 10 лет, иначе — через 40).
	if world.year - n.capital_year < (10 if threatened else 40) or rng.randf() > chance:
		return
	var best: City = null
	var best_score := -INF
	var far := maxf(10.0 * world.grid_scale, sqrt(float(n.cell_count)))
	for id in n.city_ids:
		var c := world.cities[id]
		if c == cap or world.regions[world.region_of[c.cell]].controller() != n.id:
			continue
		var dist := Vector2(world.map.cell_pos(c.cell)).distance_to(center) / far
		var score := c.population * (1.2 - minf(1.0, dist * 0.5))
		if score > best_score:
			best_score = score
			best = c
	var cap_dist := Vector2(world.map.cell_pos(cap.cell)).distance_to(center) / far
	var cap_score := cap.population * (1.2 - minf(1.0, cap_dist * 0.5))
	if best == null or (not threatened and best_score < cap_score * 1.4):
		return
	cap.is_capital = false
	best.is_capital = true
	n.capital_city = best.id
	n.capital_year = world.year
	world.count(&"capitals_moved")
	world.log_event(&"capital", "%s переносит столицу из города %s в %s%s." % [n.name, cap.name, best.name,
		" — подальше от врага" if threatened else ""], PackedInt32Array([n.id]))
