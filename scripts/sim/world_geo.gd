class_name WorldGeo
extends "res://scripts/sim/world_data.gd"
## География мира: месторождения, добыча и ёмкость клеток, климат, биомы,
## побережья, пригодность мест для городов.


func _fill_region_texels() -> void:
	var n := map.cell_count()
	region_texels.resize(n * 4)
	for i in n:
		var v := region_of[i] + 1
		region_texels[i * 4] = v & 0xff
		region_texels[i * 4 + 1] = (v >> 8) & 0xff
		region_texels[i * 4 + 3] = 255


## Восстановление после загрузки: добыча по месторождениям и регионы по region_of.
func restore_geography(region_count: int) -> void:
	_compute_cell_yields()
	regions = RegionGenerator.new().rebuild(self, region_count)
	_fill_region_texels()


## Смена биома суши (дрейф климата): добыча и ёмкость земли владельца пересчитываются.
func change_land_biome(cell: int, new_biome: int) -> void:
	if map.biome[cell] == new_biome or Biome.is_water(new_biome) or not map.is_land(cell):
		return
	var o := owner[cell]
	var base := cell * Goods.COUNT
	var r := cell_race[cell]
	var nation: Nation = nations[o] if o >= 0 else null
	if nation != null:
		for g in Goods.COUNT:
			nation.yields[g] -= cell_yield[base + g]
		if r != NO_RACE:
			nation.capacity[r] = maxf(0.0, nation.capacity[r] - cell_capacity(RaceDB.by_index(r), cell))
	map.biome[cell] = new_biome
	if region_of[cell] >= 0:
		goods_dirty[region_of[cell]] = true
	refresh_cell_yield(cell)
	if nation != null:
		for g in Goods.COUNT:
			nation.yields[g] += cell_yield[base + g]
		if r != NO_RACE:
			var cap := cell_capacity(RaceDB.by_index(r), cell)
			cell_cap[cell] = cap
			nation.capacity[r] += cap


## Климатический пояс клетки: 0 — север, 1 — умеренный, 2 — юг.
func climate_zone(cell: int) -> int:
	return clampi(int(float(cell / map.width) / map.height * 3.0), 0, 2)


## Урожайность в этом году у клетки (пояс × пепельная зима).
func harvest_at(cell: int) -> float:
	return zone_harvest[climate_zone(cell)] if cell >= 0 else 1.0


## Новая «метка» для обхода (см. mark).
func next_stamp() -> int:
	_stamp += 1
	return _stamp


## Привлекательность клетки для поселения расой race: родной биом, пригодность,
## река, побережье и окрестности.
func site_score(race: RaceDef, cell: int) -> float:
	var b := map.biome[cell]
	var score := race.affinity_by_biome[b] * 1.6 + BiomeDB.get_def(b).habitability * 0.7
	if map.river[cell] > 0:
		score += 0.35
	if is_coastal(cell):
		score += race.coast_affinity * 0.5
	# Окрестности тоже важны: город посреди одинокой клетки леса — плохая идея.
	var p := map.cell_pos(cell)
	var around := 0.0
	var samples := 0
	for dy in range(-3, 4, 3):
		for dx in range(-3, 4, 3):
			if map.in_bounds(p.x + dx, p.y + dy):
				around += race.affinity_by_biome[map.biome[map.index_of(p.x + dx, p.y + dy)]]
				samples += 1
	return score + around / maxf(samples, 1) * 0.8


## Сколько жителей расы race может прокормить клетка.
func cell_capacity(race: RaceDef, cell: int) -> float:
	var b := map.biome[cell]
	if Biome.is_water(b):
		return 0.0
	var def := BiomeDB.get_def(b)
	var aff := race.affinity_by_biome[b]
	# Тем, кто не нуждается в еде, плодородие безразлично.
	var food := lerpf(0.6, 0.25 + def.fertility, clampf(race.food_need, 0.0, 1.0))
	var cap := 1000.0 * food * lerpf(0.35, 1.2, aff)
	if map.river[cell] > 0:
		cap *= 1.3
	if race.has_trait(&"farmers"):
		cap *= 1.0 + def.fertility * 0.3
	return cap


func is_coastal(cell: int) -> bool:
	for nb in map.neighbors4(cell):
		var b := map.biome[nb]
		if b == Biome.OCEAN or b == Biome.SEA:
			return true
	return false


## Битовая маска биомов (бит = индекс биома) в квадрате радиуса radius вокруг клетки.
func biome_mask_near(cell: int, radius: int) -> int:
	var p := map.cell_pos(cell)
	var mask := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if map.in_bounds(p.x + dx, p.y + dy):
				mask |= 1 << map.biome[map.index_of(p.x + dx, p.y + dy)]
	return mask


func deposit_at(cell: int) -> DepositDef:
	var d := deposit[cell]
	return EconomyDB.deposits()[d - 1] if d > 0 else null


func _place_deposits() -> void:
	var n := map.cell_count()
	var defs := EconomyDB.deposits()
	for i in n:
		if not map.is_land(i):
			continue
		var biome_id := BiomeDB.get_def(map.biome[i]).id
		for d in defs.size():
			var def := defs[d]
			var weight: float = def.biome_weights.get(biome_id, 0.0)
			if weight > 0.0 and rng.randf() < def.chance * weight:
				deposit[i] = d + 1
				break


func refresh_cell_yield(i: int) -> void:
	var def := BiomeDB.get_def(map.biome[i])
	for g in Goods.COUNT:
		cell_yield[i * Goods.COUNT + g] = def.yield_of(g)
	var dep := deposit_at(i)
	if dep != null:
		cell_yield[i * Goods.COUNT + Goods.index_of(dep.goods)] += dep.amount


func _compute_cell_yields() -> void:
	var n := map.cell_count()
	cell_yield.resize(n * Goods.COUNT)
	for i in n:
		var def := BiomeDB.get_def(map.biome[i])
		for g in Goods.COUNT:
			cell_yield[i * Goods.COUNT + g] = def.yield_of(g)
		var dep := deposit_at(i)
		if dep != null:
			cell_yield[i * Goods.COUNT + Goods.index_of(dep.goods)] += dep.amount
