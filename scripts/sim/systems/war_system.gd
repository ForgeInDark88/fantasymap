class_name WarSystem
extends RefCounted
## Ход войн: раз в год (в день начала войны) — генеральное сражение и
## продвижение осады.
##
## Шанс победы стороны — доля её военной мощи (Nation.power() с героями,
## поделённой между всеми войнами участника). Победитель осаждает регион на
## линии фронта — там, где земли проигравшего прямо граничат с его землями;
## если общей сухопутной границы нет, но есть порт — высаживается десант на
## побережье. Скорость осады падает от стен и крепостей (дворфы), эльфы
## сильнее в лесах. Взятие региона идёт «волной» от фронта: победитель
## получает только связные с фронтом клетки, поэтому анклавов не возникает.
## Война кончается решительной победой (счёт ±100), гибелью лидера стороны
## или переговорами, когда стороны выдохлись.

## Сколько лет помнится потерянный в войне регион (претензия на возврат).
const CLAIM_YEARS := 80


func tick_day(world: World) -> void:
	var d := world.diplomacy
	var due: Array[War] = []
	for war in d.wars:
		if war.month == world.month and war.day == world.day:
			due.append(war)
	for war in due:
		_prune(world, war)
		if war.attackers.is_empty() or war.defenders.is_empty():
			_finish(world, war, 1 if war.defenders.is_empty() else -1)
			continue
		_battle(world, war)
		_check_end(world, war)


func _prune(world: World, war: War) -> void:
	for m in war.attackers.duplicate() + war.defenders.duplicate():
		if not world.nations[m].alive:
			war.remove_member(m)


func _side_power(world: World, war: War, side: int) -> float:
	var total := 0.0
	for m in war.members(side):
		var n := world.nations[m]
		total += n.power() / maxf(1.0, world.diplomacy.wars_of(m).size())
	return total


func _battle(world: World, war: War) -> void:
	var rng := world.rng
	var pa := _side_power(world, war, 1)
	var pd := _side_power(world, war, -1)
	var share := pa / (pa + pd) if pa + pd > 0.0 else 0.5
	var p := clampf(0.5 + (share - 0.5) * 1.4, 0.05, 0.95)
	var winner := 1 if rng.randf() < p else -1
	var margin := absf(share - 0.5) * 2.0  # 0 — равные силы, 1 — подавляющее превосходство
	war.battles += 1

	# Потери: проигравшие теряют больше; трусливые бегут и теряют ещё больше,
	# нежить поднимает павших в свои ряды.
	var fallen := 0.0
	for m in war.members(-winner):
		var n := world.nations[m]
		var loss := n.army * rng.randf_range(0.06, 0.14) * (1.5 if n.race.has_trait(&"cowardly") else 1.0)
		n.army -= loss
		fallen += loss
	for m in war.members(winner):
		var n := world.nations[m]
		var loss := n.army * rng.randf_range(0.02, 0.06)
		n.army -= loss
		fallen += loss
		if n.race.has_trait(&"raise_dead"):
			n.army += fallen * 0.25
	war.casualties += fallen
	war.score += winner * (4.0 + 8.0 * rng.randf()) * (0.6 + margin)
	HeroSystem.on_battle(world, war, winner)

	# Усталость от войны.
	for m in war.attackers + war.defenders:
		var n := world.nations[m]
		n.stability = maxf(0.0, n.stability - 0.006)
		n.stock[Goods.GOLD] -= n.army * 0.002

	_advance_siege(world, war, winner, margin)


func _advance_siege(world: World, war: War, winner: int, margin: float) -> void:
	if war.siege_side != winner or not _is_valid_target(world, war, war.siege_region, winner):
		_pick_target(world, war, winner)
		war.siege_side = winner
		war.siege_progress = 0.0
		if war.siege_region < 0:
			return
		var city := _region_city(world, war.siege_region, war.members(-winner))
		var who := world.nations[war.leader(winner)].short_name
		if war.siege_landing:
			world.log_event(&"siege", "%s высаживает десант в регионе %s." % [who, world.regions[war.siege_region].name],
					PackedInt32Array(war.attackers + war.defenders))
		elif city != null and city.tier() >= 2:
			world.log_event(&"siege", "%s осаждает город %s." % [who, city.name], PackedInt32Array(war.attackers + war.defenders))
	var region := world.regions[war.siege_region]
	var defense := _region_defense(world, region, war.members(-winner))
	# Десант медленнее: снабжение через море.
	# Осадное дело ускоряет осады, мореходство — десанты (верфи — ещё сильнее).
	var attacker := world.nations[war.leader(winner)]
	var speed := (0.35 + 0.5 * margin) * attacker.effect(&"siege_mult")
	# Дорога к осаждаемому городу от города наступающих — подвоз и переброска войск.
	var target_city := _region_city(world, war.siege_region, war.members(-winner))
	if target_city != null:
		for rid in world.city_roads.get(target_city.id, PackedInt32Array()):
			var road := world.roads[rid]
			if road.alive and not road.sea and war.members(winner).has(world.cities[road.other(target_city.id)].nation_id):
				speed *= 1.25
				break
	if war.siege_landing:
		speed *= 0.6 * attacker.effect(&"naval_mult") * (1.25 if _has_building(world, war.members(winner), &"shipyard") else 1.0)
	war.siege_progress += speed / (1.0 + defense)
	if war.siege_progress >= 1.0:
		_capture(world, war, region, winner)
		war.siege_region = -1
		war.siege_progress = 0.0


## Клетка проигравших, граничащая с клеткой победителей (без выделения памяти).
func _touches(world: World, cell: int, winners: PackedInt32Array) -> bool:
	var w := world.map.width
	var n := world.owner.size()
	var x := cell % w
	var o := -1
	if x > 0:
		o = world.owner[cell - 1]
		if o >= 0 and winners.has(o):
			return true
	if x < w - 1:
		o = world.owner[cell + 1]
		if o >= 0 and winners.has(o):
			return true
	if cell >= w:
		o = world.owner[cell - w]
		if o >= 0 and winners.has(o):
			return true
	if cell + w < n:
		o = world.owner[cell + w]
		if o >= 0 and winners.has(o):
			return true
	return false


## Есть ли у победителей клетки в регионе или в соседних с ним регионах (дешёвый отсев).
func _near_winners(world: World, region: Region, winners: PackedInt32Array) -> bool:
	for w in winners:
		if region.owner_counts.has(w):
			return true
	for nb in region.neighbors:
		var other := world.regions[nb]
		for w in winners:
			if other.owner_counts.has(w):
				return true
	return false


## Цель — регион на линии фронта (клетки проигравших прямо граничат с победителями).
## Если сухопутного фронта нет, а у победителей есть порт — прибрежный регион для десанта.
func _pick_target(world: World, war: War, winner: int) -> void:
	var losers := war.members(-winner)
	var winners := war.members(winner)
	var best := -1
	var best_score := -INF
	var coastal_best := -1
	var coastal_score := -INF
	# Регионы с городами проигравших и с трофеями — заранее, без обхода клеток.
	var city_regions := {}
	for m in losers:
		for id in world.nations[m].city_ids:
			city_regions[world.region_of[world.cities[id].cell]] = true
	var trophy_regions := {}
	for lm in world.landmarks:
		if lm.active and (lm.kind == &"source" or lm.kind == &"portal"):
			trophy_regions[world.region_of[lm.cell]] = true
	for m in losers:
		for rid in world.nations[m].region_counts:
			var region := world.regions[rid]
			var front := false
			if _near_winners(world, region, winners):
				for c in region.cells:
					if world.owner[c] == m and _touches(world, c, winners):
						front = true
						break
			var coast := not front and region.coastal
			if not front and not coast:
				continue
			var score := float(world.nations[m].region_counts[rid]) + world.rng.randf() * 20.0
			if city_regions.has(rid):
				score += 40.0  # города — главная цель
			for w in winners:
				if region.claims.has(w):
					score += 60.0  # возвращаем своё
			if trophy_regions.has(rid):
				score += 80.0  # источник силы и врата бездны — главные трофеи
			if front and score > best_score:
				best_score = score
				best = rid
			elif coast and score > coastal_score:
				coastal_score = score
				coastal_best = rid
	war.siege_landing = false
	war.siege_region = best
	if best < 0 and coastal_best >= 0 and _has_port(world, winners):
		war.siege_region = coastal_best
		war.siege_landing = true


func _has_building(world: World, members: PackedInt32Array, building: StringName) -> bool:
	for m in members:
		for id in world.nations[m].city_ids:
			if world.cities[id].buildings.has(building):
				return true
	return false


func _has_port(world: World, members: PackedInt32Array) -> bool:
	for m in members:
		for id in world.nations[m].city_ids:
			if world.cities[id].buildings.has(&"harbor"):
				return true
	return false


func _is_valid_target(world: World, war: War, rid: int, winner: int) -> bool:
	if rid < 0:
		return false
	var region := world.regions[rid]
	for m in war.members(-winner):
		if region.owner_counts.has(m):
			return true
	return false


func _region_city(world: World, rid: int, owners: PackedInt32Array) -> City:
	var best: City = null
	for c in world.regions[rid].cells:
		var id := world.city_cell[c]
		if id >= 0 and owners.has(world.cities[id].nation_id):
			var city := world.cities[id]
			if best == null or city.population > best.population:
				best = city
	return best


## Оборона региона: стены и крепости городов, эльфийские леса.
func _region_defense(world: World, region: Region, owners: PackedInt32Array) -> float:
	var defense := 0.0
	var city := _region_city(world, region.id, owners)
	if city != null:
		for b in city.buildings:
			var def := EconomyDB.get_building(b)
			if def != null:
				defense += def.defense
	var center_owner := world.owner[region.center]
	if center_owner >= 0:
		defense += world.nations[center_owner].effect(&"defense")
	if center_owner >= 0 and world.nations[center_owner].race.has_trait(&"forest_bond"):
		var biome := world.map.biome[region.center]
		if biome == Biome.FOREST or biome == Biome.JUNGLE:
			defense += 1.5
	return defense


## Взятие региона «волной» от линии фронта (или от берега при десанте):
## переходят только связные с фронтом клетки проигравших внутри региона.
func _capture(world: World, war: War, region: Region, winner: int) -> void:
	var losers := war.members(-winner)
	var winners := war.members(winner)
	var city := _region_city(world, region.id, losers)
	if city != null:
		TechSystem.on_city_captured(world, world.nations[war.leader(winner)], world.nations[city.nation_id])
	var capital_lost: Nation = null
	if city != null and city.is_capital:
		capital_lost = world.nations[city.nation_id]
	var queue := PackedInt32Array()
	var seen := {}
	var taker := war.leader(winner)
	for c in region.cells:
		var o := world.owner[c]
		if o < 0 or not losers.has(o):
			continue
		var start := _touches(world, c, winners) if not war.siege_landing else world.is_coastal(c)
		if start:
			queue.append(c)
			seen[c] = true
			if not war.siege_landing:
				for nb in world.map.neighbors4(c):
					if winners.has(world.owner[nb]):
						taker = world.owner[nb]
						break
	var qi := 0
	while qi < queue.size():
		var c := queue[qi]
		qi += 1
		for nb in world.map.neighbors4(c):
			if seen.has(nb) or world.region_of[nb] != region.id:
				continue
			var o := world.owner[nb]
			if o >= 0 and losers.has(o):
				seen[nb] = true
				queue.append(nb)
	var losers_hit := {}
	for c in queue:
		losers_hit[world.owner[c]] = true
		world.set_owner(c, taker)
	if queue.is_empty():
		return
	# Проигравшие помнят утраченное; победитель, вернувший своё, претензию снимает.
	for loser in losers_hit:
		region.claims[loser] = world.year + CLAIM_YEARS
	region.claims.erase(taker)
	region.unrest = 0.0
	# Мятежный регион, возвращённый прежним владельцем, надолго затихает.
	if (war.cause == &"independence" or war.cause == &"civil") and winner < 0:
		region.pacified_until = world.year + world.rng.randi_range(40, 70)
	war.score += winner * 12.0
	var conqueror := world.nations[taker]
	var ids := PackedInt32Array([taker]) + PackedInt32Array(losers_hit.keys())
	if city != null and city.alive and world.owner[city.cell] == taker:
		# Орки и гоблины иногда сжигают захваченные городки дотла.
		if conqueror.race.has_trait(&"raiders") and city.tier() <= 1 and world.rng.randf() < 0.35:
			world.log_event(&"conquest", "%s сжигает город %s." % [conqueror.short_name, city.name], ids)
			world.destroy_city(city)
		else:
			world.log_event(&"conquest", "%s захватывает регион %s и город %s." % [conqueror.short_name, region.name, city.name], ids)
	else:
		world.log_event(&"conquest", "%s захватывает регион %s." % [conqueror.short_name, region.name], ids)
	if capital_lost != null and capital_lost.alive:
		war.score += winner * 25.0
		capital_lost.stability = maxf(0.0, capital_lost.stability - 0.15)
		world.log_event(&"conquest", "Пала столица государства %s!" % capital_lost.name, PackedInt32Array([capital_lost.id]))
		if capital_lost.government != null and capital_lost.government.succession == "eternal":
			var old := capital_lost.ruler_display()
			world.new_ruler(capital_lost, true)
			world.log_event(&"ruler", "%s уничтожен вместе со столицей; власть над %s захватил %s." % [
				old, capital_lost.name, capital_lost.ruler_display()], PackedInt32Array([capital_lost.id]))
	# Отрезанные клочки проигравших внутри земель победителя присоединяются сразу.
	for loser in losers_hit:
		EnclaveSystem.absorb_if_split(world, world.nations[loser])
	world.cleanup_dead()


func _check_end(world: World, war: War) -> void:
	if war.attackers.is_empty() or not world.nations[war.leader(1)].alive:
		_finish(world, war, -1)
		return
	if war.defenders.is_empty() or not world.nations[war.leader(-1)].alive:
		_finish(world, war, 1)
		return
	if absf(war.score) >= 100.0:
		_finish(world, war, 1 if war.score > 0 else -1)
		return
	var years := world.year - war.start_year
	# С демонами не договариваются: только решительная победа или гибель.
	var demonic := world.nations[war.leader(1)].race.has_trait(&"demonic") or world.nations[war.leader(-1)].race.has_trait(&"demonic")
	if not demonic and years >= 6 and world.rng.randf() < 0.05 + years * 0.01:
		# Переговоры: при заметном перевесе — победа по очкам, иначе — белый мир.
		_finish(world, war, 0 if absf(war.score) < 30.0 else (1 if war.score > 0 else -1))


func _finish(world: World, war: War, winner_side: int) -> void:
	var d := world.diplomacy
	d.end_war(world, war, winner_side)
	var winner_id := war.leader(winner_side) if winner_side != 0 else -1
	var loser_id := war.leader(-winner_side) if winner_side != 0 else -1
	var ids := PackedInt32Array(war.attackers + war.defenders)
	if winner_side == 0 or winner_id < 0:
		world.log_event(&"peace", "%s завершилась белым миром после %d лет." % [war.name, world.year - war.start_year], ids)
		return
	var winner := world.nations[winner_id]
	var text := "%s окончена: победа за %s." % [war.name, winner.short_name]
	if loser_id >= 0 and world.nations[loser_id].alive:
		var loser := world.nations[loser_id]
		loser.stability = maxf(0.0, loser.stability - 0.1)
		# Решительная победа над слабым — вассалитет; иначе — контрибуция.
		if absf(war.score) >= 100.0 and loser.cell_count < winner.cell_count * 0.35 and not loser.race.has_trait(&"demonic") \
				and war.cause != &"independence" and loser.overlord < 0 and world.rng.randf() < 0.5:
			d.set_overlord(world, loser.id, winner.id)
			text += " %s становится вассалом." % loser.short_name
		else:
			var tribute := maxf(0.0, loser.stock[Goods.GOLD]) * 0.25
			loser.stock[Goods.GOLD] -= tribute
			winner.stock[Goods.GOLD] += tribute
			if tribute >= 10.0:
				text += " %s платит %d золота." % [loser.short_name, roundi(tribute)]
	if war.cause == &"independence":
		if winner_side > 0:
			text += " %s обретает независимость." % winner.short_name
		elif loser_id >= 0 and world.nations[loser_id].alive and world.nations[loser_id].overlord < 0:
			# Восстание подавлено — бунтари снова под властью сюзерена.
			d.set_overlord(world, loser_id, winner_id)
	world.log_event(&"peace", text, ids)
