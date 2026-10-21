class_name CreditSystem
extends RefCounted
## Займы и дефолты (этап 11.D). Казна в долгах просит взаймы: у богатого
## государства с банком (или народа торговцев) под 8% — или у Гильдии
## ростовщиков под 15%. Раз в год должник платит проценты и часть долга;
## дважды не заплатил — дефолт: заём сгорает, кредитор в обиде, порядок
## шатается, и Гильдия долго не даст денег. Займ: {id, lender (-1 — Гильдия),
## debtor, amount, left, rate, year, missed}.

const NATION_RATE := 0.08
const GUILD_RATE := 0.15
## Долг гасится за столько лет (равными частями).
const TERM := 8
const GUILD_BAN_YEARS := 30


static func debts_of(world: World, nation_id: int) -> float:
	var sum := 0.0
	for l in world.loans:
		if int(l.debtor) == nation_id:
			sum += float(l.left)
	return sum


static func lender_name(world: World, lender: int) -> String:
	return "Гильдия ростовщиков" if lender < 0 else world.nations[lender].short_name


func tick_year(world: World) -> void:
	_payments(world)
	_new_loans(world)


func _payments(world: World) -> void:
	var keep: Array[Dictionary] = []
	for l in world.loans:
		var debtor := world.nations[int(l.debtor)]
		var lender: Nation = world.nations[int(l.lender)] if int(l.lender) >= 0 else null
		if not debtor.alive:
			continue  # долг пропал вместе с должником
		var part := float(l.amount) / TERM
		var pay := float(l.left) * float(l.rate) + part
		if debtor.stock[Goods.GOLD] >= pay:
			debtor.stock[Goods.GOLD] -= pay
			if lender != null and lender.alive:
				lender.stock[Goods.GOLD] += pay
			l.left = float(l.left) - part
			l.missed = 0
			if float(l.left) > 0.5:
				keep.append(l)
			continue
		l.missed = int(l.missed) + 1
		if int(l.missed) < 2:
			keep.append(l)
			continue
		# Дефолт.
		debtor.stability = maxf(0.0, debtor.stability - 0.1)
		world.defaults[str(debtor.id)] = world.year
		world.count(&"defaults")
		if lender != null and lender.alive:
			world.diplomacy.add_grudge(lender.id, debtor.id, 0.3)
		world.log_event(&"debt", "Государство %s объявляет дефолт: долг перед «%s» (%d золота) не будет возвращён." % [debtor.short_name,
			lender_name(world, int(l.lender)), roundi(float(l.left))], PackedInt32Array([debtor.id]))
	world.loans = keep


func _new_loans(world: World) -> void:
	var d := world.diplomacy
	var indebted := {}
	for l in world.loans:
		indebted[int(l.debtor)] = true
	for n in world.nations:
		if not n.alive or n.stock[Goods.GOLD] >= -10.0 or indebted.has(n.id):
			continue
		var need := -n.stock[Goods.GOLD] + 40.0
		var lender: Nation = null
		for o in world.nations:
			if not o.alive or o.id == n.id or o.stock[Goods.GOLD] < need * 3.0 or d.war_between(o.id, n.id) != null:
				continue
			if not (o.race.has_trait(&"traders") or _has_bank(world, o)):
				continue
			if lender == null or o.stock[Goods.GOLD] > lender.stock[Goods.GOLD]:
				lender = o
		var rate := NATION_RATE
		if lender == null:
			if world.year - int(world.defaults.get(str(n.id), -1000)) < GUILD_BAN_YEARS:
				continue
			rate = GUILD_RATE
		else:
			lender.stock[Goods.GOLD] -= need
		n.stock[Goods.GOLD] += need
		world.loans.append({"id": world.loan_serial, "lender": lender.id if lender != null else -1, "debtor": n.id,
			"amount": need, "left": need, "rate": rate, "year": world.year, "missed": 0})
		world.loan_serial += 1
		world.count(&"loans")
		if need > 150.0 or world.rng.randf() < 0.15:
			world.log_event(&"debt", "Государство %s берёт взаймы %d золота у «%s» (под %d%%)." % [n.short_name, roundi(need),
				lender_name(world, lender.id if lender != null else -1), roundi(rate * 100.0)],
				PackedInt32Array([n.id, lender.id]) if lender != null else PackedInt32Array([n.id]))


static func _has_bank(world: World, n: Nation) -> bool:
	for id in n.city_ids:
		if world.cities[id].buildings.has(&"bank"):
			return true
	return false
