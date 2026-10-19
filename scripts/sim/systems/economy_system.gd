class_name EconomySystem
extends RefCounted
## Годовая экономика государства: добыча ресурсов, налоги и торговля,
## урожай и голод, содержание армии, наука и стабильность.

## Золото с 1000 жителей в год (× торговля расы × стабильность).
const TAX_PER_1000 := 0.3
## Содержание одного воина в год.
const ARMY_UPKEEP := 0.004
## Доля населения под ружьём (× военная сила расы).
const ARMY_SHARE := 0.025
## Содержание построек и городов (золото в год за постройку).
const BUILDING_UPKEEP := 0.4
## Ежегодная порча запасов дерева, камня и металла.
const STOCK_DECAY := 0.03


func tick(world: World, nation: Nation) -> void:
	var race := nation.race
	var rng := world.rng
	var pop_k := nation.population / 1000.0
	var tech_mult := 1.0 + nation.tech * 0.05

	# Добыча: клетки территории + постройки.
	for g in [Goods.WOOD, Goods.STONE, Goods.METAL, Goods.GOLD]:
		var amount: float = nation.yields[g] * tech_mult + nation.building_production[g]
		if race.has_trait(&"miners") and (g == Goods.STONE or g == Goods.METAL):
			amount *= 1.5
		nation.income[g] = amount

	# Налоги и торговля минус содержание армии.
	var taxes := pop_k * TAX_PER_1000 * race.trade * (0.5 + nation.stability * 0.5) * tech_mult
	if race.has_trait(&"traders"):
		taxes *= 1.15
	if race.has_trait(&"raiders"):
		taxes += nation.army * 0.0015  # грабежи соседей
	# Мёртвым воинам не нужны ни жалованье, ни паёк.
	var upkeep := ARMY_UPKEEP * (0.25 if race.food_need <= 0.0 else 1.0)
	var buildings := 0
	for id in nation.city_ids:
		buildings += world.cities[id].buildings.size() + 1
	nation.income[Goods.GOLD] += taxes - nation.army * upkeep - buildings * BUILDING_UPKEEP
	# Торговые договоры: доход растёт с размером обоих рынков.
	for partner in nation.trade_partners:
		var other := world.nations[partner]
		nation.income[Goods.GOLD] += 0.05 * sqrt(pop_k * other.population / 1000.0) * race.trade
	# Вассал платит сюзерену дань с прибыли.
	if nation.overlord >= 0 and nation.income[Goods.GOLD] > 0.0:
		var tribute := nation.income[Goods.GOLD] * 0.15
		nation.income[Goods.GOLD] -= tribute
		world.nations[nation.overlord].stock[Goods.GOLD] += tribute

	# Еда: урожай (с погодой) против потребления.
	var consumption := pop_k * race.food_need
	if race.food_need > 0.0:
		var harvest := rng.randf_range(0.82, 1.15)
		var production := nation.total_capacity() / 1000.0 * race.food_need * harvest
		nation.income[Goods.FOOD] = production - consumption
	else:
		nation.income[Goods.FOOD] = 0.0

	for g in [Goods.WOOD, Goods.STONE, Goods.METAL]:
		nation.income[g] -= nation.stock[g] * STOCK_DECAY
	for g in Goods.COUNT:
		nation.stock[g] += nation.income[g]
	# Амбары не бездонны.
	nation.stock[Goods.FOOD] = minf(nation.stock[Goods.FOOD], consumption * 1.5 + 5.0)

	var was_starving := nation.famine_years > 0
	if nation.stock[Goods.FOOD] < 0.0:
		nation.stock[Goods.FOOD] = 0.0
		nation.famine_years += 1
		if not was_starving:
			world.log_event(&"famine", "В государстве %s начался голод." % nation.name, PackedInt32Array([nation.id]))
	else:
		if was_starving and nation.famine_years >= 2:
			world.log_event(&"famine", "Голод в государстве %s отступил." % nation.name, PackedInt32Array([nation.id]))
		nation.famine_years = 0

	# Наука: растёт с логарифмом населения и замедляется с уровнем (≈10 за 400 лет).
	nation.tech += 0.02 * race.science * (1.0 + nation.science_bonus) * nation.modifier("science_mult") \
			* log(1.0 + pop_k / 100.0) / (1.0 + nation.tech * 0.3)

	# Армия стремится к доле населения; в долгах — дезертирство.
	var military := race.military * (1.0 + nation.army_bonus) * (1.25 if race.has_trait(&"warlike") else 1.0)
	var target_army := nation.population * ARMY_SHARE * military
	if nation.stock[Goods.GOLD] < 0.0:
		target_army *= 0.5
	# В войну рекруты набираются медленнее, чем пополняются потери в мирное время.
	var at_war := not world.diplomacy.wars_of(nation.id).is_empty()
	nation.army = lerpf(nation.army, target_army, 0.08 if at_war else 0.15)

	var target_stability := _target_stability(nation) - (0.04 if at_war else 0.0)
	nation.stability = clampf(lerpf(nation.stability, target_stability, 0.08), 0.0, 1.0)


## Куда стремится стабильность: постройки и долголетие — вверх; чужие народы
## (с учётом расовых отношений), слишком большая территория, голод и долги — вниз.
func _target_stability(nation: Nation) -> float:
	var race := nation.race
	var target := 0.78 + nation.stability_bonus
	if race.has_trait(&"long_lived"):
		target += 0.05
	var total := nation.population
	if total > 0.0:
		for r in nation.pop.size():
			if r == race.index or nation.pop[r] <= 0.0:
				continue
			var share := nation.pop[r] / total
			var relation := race.relation_to(RaceDB.by_index(r))
			target -= share * (0.35 - relation * 0.25)
	var comfortable := 450.0 * race.expansion
	if nation.cell_count > comfortable:
		target -= minf(0.3, (nation.cell_count - comfortable) / 2500.0)
	if nation.famine_years > 0:
		target -= 0.15
	if nation.stock[Goods.GOLD] < 0.0:
		target -= 0.15
	return target
