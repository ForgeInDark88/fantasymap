class_name MercSystem
extends RefCounted
## Наёмники (этап 11.D): вольные отряды служат тем, кто платит. Раз в год:
## вольный отряд нанимается к богатейшему из воюющих, кому по карману; служба —
## плата из казны и сила в бою (Nation.merc_power); без платы отряд уходит к
## врагу нанимателя, если тот заплатит, — или грабит его край и уходит. Мир у
## нанимателя — контракт окончен. Отряды тают в походах; новые собираются у
## больших городов, когда в мире много войн.

const MAX_FREE := 3
const WAGE := 0.02
const STRENGTH := Vector2(1500.0, 5000.0)
const MIN_STRENGTH := 500.0
const NAMES := ["Чёрные плащи", "Железные псы", "Сыны бури", "Серая сотня", "Багряный стяг", "Волчья стая",
	"Золотые копья", "Кровавые топоры", "Вольные клинки", "Белая рота", "Стальной кулак", "Последний довод"]


static func alive_companies(world: World) -> Array[MercCompany]:
	var res: Array[MercCompany] = []
	for m in world.mercs:
		if m.alive:
			res.append(m)
	return res


## Новый вольный отряд у города city (Бог или случай).
static func spawn(world: World, city: City) -> MercCompany:
	if city == null or not city.alive:
		return null
	var rng := world.rng
	var m := MercCompany.new()
	m.id = world.mercs.size()
	m.name = "%s %s" % [["Рота", "Дружина", "Отряд", "Братство"][rng.randi_range(0, 3)], "«%s»" % NAMES[rng.randi_range(0, NAMES.size() - 1)]]
	m.race = world.nations[city.nation_id].race if city.nation_id >= 0 else RaceDB.all()[0]
	m.strength = rng.randf_range(STRENGTH.x, STRENGTH.y)
	m.wage = m.strength * WAGE
	m.cell = city.cell
	m.born = world.year
	world.mercs.append(m)
	world.count(&"mercs")
	return m


func tick_year(world: World) -> void:
	var rng := world.rng
	var d := world.diplomacy
	var free := 0
	for m in world.mercs:
		if m.alive and m.employer < 0:
			free += 1
	if free < MAX_FREE and d.wars.size() >= 2 and rng.randf() < 0.3 and not world.cities.is_empty():
		var best: City = null
		for k in 6:
			var c := world.cities[rng.randi_range(0, world.cities.size() - 1)]
			if c.alive and (best == null or c.population > best.population):
				best = c
		spawn(world, best)
	for m in world.mercs:
		if not m.alive:
			continue
		if m.employer >= 0:
			_serve(world, m)
		else:
			_seek(world, m)
		if m.alive and m.strength < MIN_STRENGTH:
			m.alive = false
	# Сила в бою — заново у всех.
	for n in world.nations:
		n.merc_power = 0.0
	for m in world.mercs:
		if m.alive and m.employer >= 0:
			world.nations[m.employer].merc_power += m.strength * 0.9
	var keep: Array[MercCompany] = []
	for m in world.mercs:
		if m.alive:
			m.id = keep.size()
			keep.append(m)
	world.mercs = keep


func _seek(world: World, m: MercCompany) -> void:
	var best: Nation = null
	for n in world.nations:
		if not n.alive or world.diplomacy.wars_of(n.id).is_empty() or n.stock[Goods.GOLD] < m.wage * 2.0:
			continue
		if best == null or n.stock[Goods.GOLD] > best.stock[Goods.GOLD]:
			best = n
	if best == null:
		return
	_hire(world, m, best)


static func _hire(world: World, m: MercCompany, n: Nation) -> void:
	m.employer = n.id
	m.unpaid = 0
	if n.capital_city >= 0:
		m.cell = world.cities[n.capital_city].cell
	world.count(&"mercs_hired")
	if m.strength > 4000.0 and world.rng.randf() < 0.3:
		world.log_event(&"mercs", "%s (%s воинов) нанимается на службу государству %s." % [m.name, ArmySystem._num(m.strength), n.short_name],
			PackedInt32Array([n.id]))


func _serve(world: World, m: MercCompany) -> void:
	var rng := world.rng
	var n := world.nations[m.employer]
	if not n.alive or world.diplomacy.wars_of(n.id).is_empty():
		m.employer = -1
		return
	m.strength *= rng.randf_range(0.85, 1.0)
	var wage := m.wage * n.inflation
	if n.stock[Goods.GOLD] >= wage:
		n.stock[Goods.GOLD] -= wage
		m.unpaid = 0
		return
	m.unpaid += 1
	# Без платы — к врагу, если тот заплатит; иначе — грабёж и уход.
	for w in world.diplomacy.wars_of(n.id):
		for e in w.members(-w.side_of(n.id)):
			var enemy := world.nations[e]
			if enemy.alive and enemy.stock[Goods.GOLD] >= m.wage * 2.0:
				world.count(&"mercs_betrayed")
				world.log_event(&"mercs", "%s, не получив платы от государства %s, переходит на сторону врага — %s." % [m.name,
					n.short_name, enemy.short_name], PackedInt32Array([n.id, enemy.id]))
				_hire(world, m, enemy)
				return
	n.stock[Goods.GOLD] -= minf(maxf(0.0, n.stock[Goods.GOLD]), m.wage)
	for r in n.pop.size():
		n.pop[r] *= 0.995
	n.stability = maxf(0.0, n.stability - 0.03)
	m.employer = -1
	world.count(&"mercs_plunder")
	world.log_event(&"mercs", "%s, не дождавшись платы, грабит земли государства %s и уходит." % [m.name, n.short_name],
		PackedInt32Array([n.id]))
