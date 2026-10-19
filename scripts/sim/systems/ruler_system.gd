class_name RulerSystem
extends RefCounted
## Смена власти по форме правления (GovernmentDef.succession):
##   heir      — наследник рода; при слабой власти — кризис престолонаследия:
##               претендент поднимает часть страны (гражданская война), а по
##               династическому браку корону может унаследовать соседний двор;
##   election  — выборы раз в N лет (правителя могут переизбрать);
##   strongest — после смерти вождя власть берёт сильнейший, смуты часты;
##   eternal   — бессмертный владыка правит, пока его не уничтожат.
## Прославленный герой, служащий государству, может сам взойти на трон.


func tick(world: World, nation: Nation) -> void:
	nation.ruler_age += 1
	nation.reign_left -= 1
	if nation.reign_left > 0:
		return
	var gov := nation.government
	var old := nation.ruler_display()
	match gov.succession if gov != null else "heir":
		"election":
			_election(world, nation, old)
		"eternal":
			# Срок «бессмертного» вышел — его свергли или он ушёл во тьму.
			_new_dynasty(world, nation, "%s: %s низвергнут, власть захватил %s.")
		"strongest":
			if not _crisis(world, nation, old):
				_new_dynasty(world, nation, "%s: %s пал, власть взял сильнейший — %s.")
		_:
			if not _crisis(world, nation, old):
				if _hero_takes_throne(world, nation, old):
					return
				world.new_ruler(nation, false)
				world.log_event(&"ruler", "%s: %s умер, на престол взошёл %s из рода %s." % [
					nation.name, old, _ruler_with_trait(nation), nation.dynasty], PackedInt32Array([nation.id]))
	nation.stability = maxf(0.0, nation.stability - world.rng.randf_range(0.0, 0.06))


func _election(world: World, nation: Nation, old: String) -> void:
	if world.rng.randf() < 0.3:
		nation.reign_left = nation.government.election_period
		return  # переизбран — без записи в летописи
	world.new_ruler(nation, true)
	world.log_event(&"ruler", "%s: выборы — %s уступает место; избран %s." % [
		nation.name, old, _ruler_with_trait(nation)], PackedInt32Array([nation.id]))


func _new_dynasty(world: World, nation: Nation, template: String) -> void:
	var old := nation.ruler_display()
	if _hero_takes_throne(world, nation, old):
		return
	world.new_ruler(nation, true)
	world.log_event(&"ruler", template % [nation.name, old, _ruler_with_trait(nation)], PackedInt32Array([nation.id]))


## Кризис престолонаследия. Возвращает true, если он случился.
func _crisis(world: World, nation: Nation, old: String) -> bool:
	var rng := world.rng
	var gov := nation.government
	var chance := (gov.crisis_chance if gov != null else 0.05) * 0.7 + (1.0 - nation.stability) * 0.08
	if nation.ruler_trait != null and nation.ruler_trait.id == &"weak":
		chance += 0.1
	if rng.randf() > chance:
		return false
	# Династический брак: корону наследует соседний двор — личная уния.
	var d := world.diplomacy
	for other in nation.borders:
		if d.married(nation.id, other, world.year) and world.nations[other].overlord < 0 \
				and nation.overlord < 0 and rng.randf() < 0.4:
			var heir := world.nations[other]
			d.set_overlord(world, nation.id, heir.id)
			world.new_ruler(nation, true)
			world.log_event(&"vassal", "%s умер без наследника. По династическому браку корону %s получает двор %s — личная уния." % [
				old, nation.name, heir.name], PackedInt32Array([nation.id, heir.id]))
			return true
	# Претендент поднимает отдалённые регионы — гражданская война.
	var regions := _far_regions(world, nation)
	world.new_ruler(nation, false)
	if regions.size() >= 1 and nation.region_counts.size() >= 6 and rng.randf() < 0.5:
		var rebel := world.split_off(nation, regions, nation.race)
		if rebel.alive:
			world.log_event(&"rebellion", "Смута в государстве %s после смерти правителя (%s): претендент %s провозглашает %s." % [
				nation.short_name, old, rebel.ruler_display(), rebel.name], PackedInt32Array([nation.id, rebel.id]))
			d.declare_war(world, rebel.id, nation.id, &"civil")
			return true
	world.log_event(&"ruler", "%s: после смерти правителя (%s) — смута; трон захватил %s." % [
		nation.name, old, _ruler_with_trait(nation)], PackedInt32Array([nation.id]))
	nation.stability = maxf(0.0, nation.stability - 0.1)
	return true


## Регионы, дальние от столицы, — опора претендента (до трети страны).
func _far_regions(world: World, nation: Nation) -> PackedInt32Array:
	if nation.capital_city < 0:
		return PackedInt32Array()
	var cap := Vector2(world.map.cell_pos(world.cities[nation.capital_city].cell))
	var owned: Array = []
	for rid in nation.region_counts:
		if world.regions[rid].controller() == nation.id:
			owned.append(rid)
	owned.sort_custom(func(a: int, b: int) -> bool:
		return Vector2(world.map.cell_pos(world.regions[a].center)).distance_squared_to(cap) \
				> Vector2(world.map.cell_pos(world.regions[b].center)).distance_squared_to(cap))
	var result := PackedInt32Array()
	if owned.is_empty():
		return result
	# Берём самый дальний регион и его связных соседей — претенденту нужна сплошная земля.
	var count := maxi(1, owned.size() / 3)
	var queue := [owned[0]]
	result.append(owned[0])
	while not queue.is_empty() and result.size() < count:
		var rid: int = queue.pop_front()
		for nb in world.regions[rid].neighbors:
			if owned.has(nb) and not result.has(nb):
				result.append(nb)
				queue.append(nb)
				if result.size() >= count:
					break
	return result


## Прославленный герой на службе государства берёт власть и основывает династию.
func _hero_takes_throne(world: World, nation: Nation, old: String) -> bool:
	for hid in nation.hero_ids:
		var hero := world.heroes[hid]
		if hero.alive and hero.level >= 6 and hero.race_id == nation.race_id and world.rng.randf() < 0.25:
			world.new_ruler(nation, true)
			nation.ruler_name = hero.name
			nation.dynasty = hero.name
			nation.dynasty_names = {hero.name: 1}
			nation.ruler_number = 1
			nation.ruler_age = hero.age
			hero.become_ruler(world)
			world.log_event(&"hero", "%s: после %s трон занял прославленный герой %s (%s)." % [
				nation.name, old, hero.name, hero.hero_class.display_name.to_lower()], PackedInt32Array([nation.id]))
			return true
	return false


static func _ruler_with_trait(nation: Nation) -> String:
	if nation.ruler_trait == null:
		return nation.ruler_display()
	return "%s (%s)" % [nation.ruler_display(), nation.ruler_trait.display_name.to_lower()]
