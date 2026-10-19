class_name WarSystem
extends RefCounted
## Ход войн: раз в год — генеральное сражение и продвижение осады.
##
## Шанс победы стороны — доля её военной мощи (Nation.power(), поделённой
## между всеми войнами участника). Победитель осаждает пограничный регион
## проигравшего; скорость осады падает от стен и крепостей (дворфы), эльфы
## сильнее обороняются в лесах. Взятый регион со всеми клетками, жителями и
## городами переходит к победителю — так и появляются многорасовые государства.
## Война кончается решительной победой (счёт ±100), гибелью лидера стороны
## или переговорами, когда стороны выдохлись.


func tick(world: World) -> void:
	var d := world.diplomacy
	for war in d.active_wars():
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

	# Усталость от войны.
	for m in war.attackers + war.defenders:
		var n := world.nations[m]
		n.stability = maxf(0.0, n.stability - 0.006)
		n.stock[Goods.GOLD] -= n.army * 0.002

	_advance_siege(world, war, winner, margin)


func _advance_siege(world: World, war: War, winner: int, margin: float) -> void:
	if war.siege_side != winner or not _is_valid_target(world, war, war.siege_region, winner):
		war.siege_region = _pick_target(world, war, winner)
		war.siege_side = winner
		war.siege_progress = 0.0
		if war.siege_region < 0:
			return
		var city := _region_city(world, war.siege_region, war.members(-winner))
		if city != null and city.tier() >= 2:
			world.log_event(&"siege", "%s осаждает город %s." % [
				world.nations[war.leader(winner)].short_name, city.name], PackedInt32Array(war.attackers + war.defenders))
	var region := world.regions[war.siege_region]
	var defense := _region_defense(world, region, war.members(-winner))
	war.siege_progress += (0.35 + 0.5 * margin) / (1.0 + defense)
	if war.siege_progress >= 1.0:
		_capture(world, war, region, winner)
		war.siege_region = -1
		war.siege_progress = 0.0


## Пограничный регион, где у проигравших есть клетки, соседний с землями победителей.
func _pick_target(world: World, war: War, winner: int) -> int:
	var losers := war.members(-winner)
	var winners := war.members(winner)
	var best := -1
	var best_score := -INF
	for m in losers:
		for rid in world.nations[m].region_counts:
			var region := world.regions[rid]
			var adjacent := false
			for w in winners:
				if region.owner_counts.has(w):
					adjacent = true
					break
				for nb in region.neighbors:
					if world.regions[nb].owner_counts.has(w):
						adjacent = true
						break
				if adjacent:
					break
			if not adjacent:
				continue
			var score := float(world.nations[m].region_counts[rid]) + world.rng.randf() * 20.0
			if _region_city(world, rid, losers) != null:
				score += 40.0  # города — главная цель
			if score > best_score:
				best_score = score
				best = rid
	return best


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
	if center_owner >= 0 and world.nations[center_owner].race.has_trait(&"forest_bond"):
		var biome := world.map.biome[region.center]
		if biome == Biome.FOREST or biome == Biome.JUNGLE:
			defense += 1.5
	return defense


func _capture(world: World, war: War, region: Region, winner: int) -> void:
	var losers := war.members(-winner)
	var winners := war.members(winner)
	var city := _region_city(world, region.id, losers)
	var capital_lost: Nation = null
	if city != null and city.is_capital:
		capital_lost = world.nations[city.nation_id]
	# Клетки достаются тому из победителей, кто граничит с регионом (обычно лидеру).
	var taker := winners[0]
	for w in winners:
		if region.owner_counts.has(w):
			taker = w
			break
	var losers_hit := {}
	for c in region.cells:
		var o := world.owner[c]
		if o >= 0 and losers.has(o):
			losers_hit[o] = true
			world.set_owner(c, taker)
	region.unrest = 0.0
	# Мятежный регион, возвращённый прежним владельцем, надолго затихает.
	if (war.cause == &"independence" or war.cause == &"civil") and winner < 0:
		region.pacified_until = world.year + world.rng.randi_range(40, 70)
	war.score += winner * 12.0
	var conqueror := world.nations[taker]
	if city != null and city.alive:
		# Орки и гоблины иногда сжигают захваченные городки дотла.
		if conqueror.race.has_trait(&"raiders") and city.tier() <= 1 and world.rng.randf() < 0.35:
			world.log_event(&"conquest", "%s сжигает город %s." % [conqueror.short_name, city.name],
					PackedInt32Array([taker]))
			world.destroy_city(city)
		else:
			world.log_event(&"conquest", "%s захватывает регион %s и город %s." % [conqueror.short_name, region.name, city.name],
					PackedInt32Array([taker]) + PackedInt32Array(losers_hit.keys()))
	else:
		world.log_event(&"conquest", "%s захватывает регион %s." % [conqueror.short_name, region.name],
				PackedInt32Array([taker]) + PackedInt32Array(losers_hit.keys()))
	if capital_lost != null:
		war.score += winner * 25.0
		capital_lost.stability = maxf(0.0, capital_lost.stability - 0.15)
		world.log_event(&"conquest", "Пала столица государства %s!" % capital_lost.name, PackedInt32Array([capital_lost.id]))
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
	if years >= 6 and world.rng.randf() < 0.05 + years * 0.01:
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
		if absf(war.score) >= 100.0 and loser.cell_count < winner.cell_count * 0.35 \
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
