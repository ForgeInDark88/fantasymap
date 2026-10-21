class_name WorldTerritory
extends "res://scripts/sim/world_geo.gd"
## Территория: владение клетками (set_owner), длины границ, учёт регионов,
## города (основание, передача, разрушение, столицы), отделение регионов.


## Восстановление города после загрузки (без генерации имени и учёта владельца).
func restore_city(city: City) -> void:
	cities.append(city)
	if city.alive:
		city_cell[city.cell] = city.id
		_mark_city_area(city.cell, 1)


# ---------------------------------------------------------------------------
# Территория
# ---------------------------------------------------------------------------


## Передаёт клетку государству nation_id (-1 — сделать ничьей).
## Жители клетки переезжают вместе с ней в пропорции её доли в ёмкости земли;
## город в клетке переходит к новому владельцу. Поддерживает учёт регионов
## и длины общих границ между государствами.
func set_owner(cell: int, nation_id: int) -> void:
	var old := owner[cell]
	if old == nation_id:
		return
	_update_borders(cell, old, nation_id)
	_update_region(cell, old, nation_id)
	var r := cell_race[cell]
	var moved := 0.0
	if old >= 0:
		var on := nations[old]
		_remove_cell(on, cell)
		if r != NO_RACE:
			var cap := cell_capacity(RaceDB.by_index(r), cell)
			if on.capacity[r] > 0.0:
				moved = on.pop[r] * clampf(cap / on.capacity[r], 0.0, 1.0)
			on.capacity[r] = maxf(0.0, on.capacity[r] - cap)
			on.pop[r] = maxf(0.0, on.pop[r] - moved)
	owner[cell] = nation_id
	var v := nation_id + 1
	owner_texels[cell * 4] = v & 0xff
	owner_texels[cell * 4 + 1] = (v >> 8) & 0xff
	if nation_id >= 0:
		var nn := nations[nation_id]
		if r == NO_RACE:
			# Ничейную землю заселяет народ нового владельца.
			r = nn.race.index
			cell_race[cell] = r
		_add_cell(nn, cell)
		var cap := cell_capacity(RaceDB.by_index(r), cell)
		cell_cap[cell] = cap
		nn.capacity[r] += cap
		nn.pop[r] += moved
	if city_cell[cell] >= 0:
		_transfer_city(cities[city_cell[cell]], nation_id)
	ownership_version += 1


## Длина общих границ: число пар соседних клеток разных владельцев.
func _update_borders(cell: int, old: int, new: int) -> void:
	# Соседи без выделения массива (горячий путь: каждая смена владельца клетки).
	var w := map.width
	var x := cell % w
	if x > 0:
		_border_pair(owner[cell - 1], old, new)
	if x < w - 1:
		_border_pair(owner[cell + 1], old, new)
	if cell >= w:
		_border_pair(owner[cell - w], old, new)
	if cell < owner.size() - w:
		_border_pair(owner[cell + w], old, new)


func _border_pair(o: int, old: int, new: int) -> void:
	if o < 0:
		return
	if old >= 0 and o != old:
		_add_border(old, o, -1)
	if new >= 0 and o != new:
		_add_border(new, o, 1)


func _add_border(a: int, b: int, delta: int) -> void:
	_add_border_one(nations[a].borders, b, delta)
	_add_border_one(nations[b].borders, a, delta)


static func _add_border_one(borders: Dictionary, key: int, delta: int) -> void:
	var v: int = borders.get(key, 0) + delta
	if v <= 0:
		borders.erase(key)
	else:
		borders[key] = v


func _update_region(cell: int, old: int, new: int) -> void:
	var rid := region_of[cell]
	if rid < 0:
		return
	var region := regions[rid]
	if old >= 0:
		_dec(region.owner_counts, old)
		_dec(nations[old].region_counts, rid)
	if new >= 0:
		region.owner_counts[new] = region.owner_counts.get(new, 0) + 1
		nations[new].region_counts[rid] = nations[new].region_counts.get(rid, 0) + 1
		if region.name.is_empty():
			# Регион называет тот, кто первым его заселил, — на своём языке.
			region.name = NameGenerator.unique(used_names, NameGenerator.place_name.bind(nations[new].race, rng))
		# Первые поселенцы приносят свою веру и культуру.
		ReligionSystem.ensure_faith(region, nations[new].state_religion)
		if region.culture < 0:
			region.culture = nations[new].culture
		if old >= 0:
			region.conquered_year = year


static func _dec(counts: Dictionary, key: int) -> void:
	var v: int = counts.get(key, 0) - 1
	if v <= 0:
		counts.erase(key)
	else:
		counts[key] = v


## Город сменил владельца вместе со своей клеткой.
func _transfer_city(city: City, new_owner: int) -> void:
	var old := city.nation_id
	if old >= 0:
		var on := nations[old]
		var idx := on.city_ids.find(city.id)
		if idx >= 0:
			on.city_ids.remove_at(idx)
		if on.capital_city == city.id:
			city.is_capital = false
			choose_capital(on)
	city.nation_id = new_owner
	if new_owner >= 0:
		var nn := nations[new_owner]
		nn.city_ids.append(city.id)
		city.is_capital = false
		if nn.capital_city < 0:
			city.is_capital = true
			nn.capital_city = city.id
			nn.home_cell = city.cell
	else:
		destroy_city(city)


## Новая столица — крупнейший из оставшихся городов (или -1, если городов нет).
func choose_capital(nation: Nation) -> void:
	nation.capital_city = -1
	var best: City = null
	for id in nation.city_ids:
		var c := cities[id]
		c.is_capital = false  # столица одна
		if best == null or c.population > best.population:
			best = c
	if best != null:
		best.is_capital = true
		nation.capital_city = best.id
		nation.home_cell = best.cell


## Город разрушен: исчезает с карты, освобождает место для новых городов.
func destroy_city(city: City) -> void:
	if not city.alive:
		return
	RuinSystem.on_city_destroyed(self, city)
	city.alive = false
	city_cell[city.cell] = -1
	_mark_city_area(city.cell, -1)
	if city.nation_id >= 0:
		var nation := nations[city.nation_id]
		var idx := nation.city_ids.find(city.id)
		if idx >= 0:
			nation.city_ids.remove_at(idx)
		if nation.capital_city == city.id:
			city.is_capital = false
			choose_capital(nation)
	city.nation_id = -1


## Народ клетки сменился (ассимиляция): ёмкость и часть жителей переходят
## к новому народу того же государства.
func convert_cell_race(cell: int, new_race: int) -> void:
	var old_race := cell_race[cell]
	if old_race == new_race:
		return
	var o := owner[cell]
	if o < 0 or old_race == NO_RACE:
		cell_race[cell] = new_race
		return
	var nation := nations[o]
	var old_cap := cell_capacity(RaceDB.by_index(old_race), cell)
	var moved := 0.0
	if nation.capacity[old_race] > 0.0:
		moved = nation.pop[old_race] * clampf(old_cap / nation.capacity[old_race], 0.0, 1.0)
	nation.capacity[old_race] = maxf(0.0, nation.capacity[old_race] - old_cap)
	nation.pop[old_race] = maxf(0.0, nation.pop[old_race] - moved)
	cell_race[cell] = new_race
	var cap := cell_capacity(RaceDB.by_index(new_race), cell)
	cell_cap[cell] = cap
	nation.capacity[new_race] += cap
	nation.pop[new_race] += moved


## Дать имя ещё не заселённому региону (для знаковых мест в диких землях).
func ensure_region_name(region: Region) -> void:
	if region != null and region.name.is_empty():
		var races := RaceDB.all()
		region.name = NameGenerator.unique(used_names, NameGenerator.place_name.bind(races[rng.randi_range(0, races.size() - 1)], rng))


## Название региона клетки для текстов (безымянному даётся имя), иначе fallback.
func region_label(cell: int, fallback: String) -> String:
	var region := region_at(cell) if cell >= 0 else null
	if region == null:
		return fallback
	ensure_region_name(region)
	return region.name


func region_at(cell: int) -> Region:
	var rid := region_of[cell]
	return regions[rid] if rid >= 0 else null


## Самый многочисленный народ региона (RaceDef.index или NO_RACE).
func region_majority_race(region: Region, owner_id: int = -2) -> int:
	# Однородному государству считать нечего — там живёт его народ.
	if owner_id >= 0 and nations[owner_id].primary_share() > 0.999:
		return nations[owner_id].race.index
	var counts := PackedInt32Array()
	counts.resize(RaceDB.count())
	var best := NO_RACE
	var best_count := 0
	for c in region.cells:
		if owner_id != -2 and owner[c] != owner_id:
			continue
		var r := cell_race[c]
		if r == NO_RACE:
			continue
		counts[r] += 1
		if counts[r] > best_count:
			best_count = counts[r]
			best = r
	return best


## Население части региона, принадлежащей государству: ёмкость его клеток × заселённость.
func region_population(region: Region, owner_id: int) -> float:
	if owner_id < 0:
		return 0.0
	var nation := nations[owner_id]
	var total := 0.0
	for c in region.cells:
		if owner[c] != owner_id:
			continue
		var r := cell_race[c]
		if r == NO_RACE or nation.capacity[r] <= 0.0:
			continue
		total += cell_capacity(RaceDB.by_index(r), c) * nation.pop[r] / nation.capacity[r]
	return total


func _add_cell(nation: Nation, cell: int) -> void:
	nation.territory_dirty = true
	cell_slot[cell] = nation.cells.size()
	nation.cells.append(cell)
	nation.sum_x += cell % map.width
	nation.sum_y += cell / map.width
	var base := cell * Goods.COUNT
	for g in Goods.COUNT:
		nation.yields[g] += cell_yield[base + g]


func _remove_cell(nation: Nation, cell: int) -> void:
	nation.territory_dirty = true
	var slot := cell_slot[cell]
	var last_index := nation.cells.size() - 1
	var last := nation.cells[last_index]
	nation.cells[slot] = last
	cell_slot[last] = slot
	nation.cells.resize(last_index)
	cell_slot[cell] = -1
	if last_index == 0:
		_maybe_dead = true
	nation.sum_x -= cell % map.width
	nation.sum_y -= cell / map.width
	var base := cell * Goods.COUNT
	for g in Goods.COUNT:
		nation.yields[g] -= cell_yield[base + g]


func nation_at(cell: int) -> Nation:
	var id := owner[cell]
	return nations[id] if id >= 0 else null


func city_at(cell: int) -> City:
	var id := city_cell[cell]
	return cities[id] if id >= 0 else null


func add_city(nation: Nation, cell: int, race: RaceDef, is_capital: bool) -> City:
	var city := City.new()
	city.id = cities.size()
	city.cell = cell
	city.nation_id = nation.id
	city.race_id = race.id
	city.is_capital = is_capital
	city.founded_year = year
	city.name = NameGenerator.unique(used_names, NameGenerator.place_name.bind(race, rng))
	city.coastal = is_coastal(cell)
	city.weight = clampf(site_score(race, cell) * 0.5, 0.5, 2.0)
	city.luck = clampf(exp(rng.randfn(0.0, 0.6)), 0.25, 5.0)
	city.near_biomes = biome_mask_near(cell, 2 * grid_scale)
	cities.append(city)
	city_cell[cell] = city.id
	_mark_city_area(cell, 1)
	nation.city_ids.append(city.id)
	if is_capital:
		nation.capital_city = city.id
		nation.home_cell = city.cell
	return city


# ---------------------------------------------------------------------------
# Места для городов
# ---------------------------------------------------------------------------


## Можно ли основать город в клетке (нет других городов ближе CITY_SPACING).
func can_place_city(cell: int) -> bool:
	return city_block[cell] == 0


func _mark_city_area(cell: int, delta: int) -> void:
	var p := map.cell_pos(cell)
	var r := CITY_SPACING * grid_scale
	for y in range(maxi(0, p.y - r), mini(map.height, p.y + r + 1)):
		for x in range(maxi(0, p.x - r), mini(map.width, p.x + r + 1)):
			var i := y * map.width + x
			city_block[i] = clampi(city_block[i] + delta, 0, 255)
