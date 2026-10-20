class_name Fate
## Суд Судьбы над павшими героями (решает игрок в панели «Судьба»):
##   second_chance — вернуть героя на землю (слабее, но живого);
##   ignore        — пусть покоится с миром;
##   curse         — заточить душу в оружие: на карте появляется пустой трон
##                   со стражем; одолевший стража герой получит проклятое оружие.

## Судьба возвращает героя не больше этого числа раз.
const MAX_RETURNS := 2


static func pending(world: World) -> Array[Hero]:
	var result: Array[Hero] = []
	for id in world.fate_queue:
		result.append(world.heroes[id])
	return result


static func second_chance(world: World, hero: Hero) -> bool:
	if hero.returns >= max_returns(hero):
		return false
	_take(world, hero)
	# Возвращается туда, где жил его народ (или в любой регион с людьми).
	var cell := -1
	for attempt in 50:
		var region := world.regions[world.rng.randi_range(0, world.regions.size() - 1)]
		if region.cells.is_empty():
			continue
		var c := region.cells[world.rng.randi_range(0, region.cells.size() - 1)]
		var o := world.owner[c]
		if o >= 0 and (world.nations[o].race == hero.race or attempt > 30):
			cell = c
			break
	if cell < 0:
		return false
	hero.alive = true
	world.add_wandering(hero)
	hero.returns += 1
	hero.fate = &"returned"
	hero.cell = cell
	hero.level = maxi(1, hero.level - 1)
	hero.age = mini(hero.age, hero.max_age - 10)
	hero.karma = minf(1.0, hero.karma + 0.25)
	hero.add_deed(world, "вернулся из-за грани по воле Судьбы")
	var region := world.region_at(cell)
	world.log_event(&"fate", "Судьба даровала второй шанс: %s вернулся в мир живых в регионе %s." % [
		hero.display_name(), region.name], PackedInt32Array([world.owner[cell]]))
	return true


## Избранник бога может вернуться на раз больше.
static func max_returns(hero: Hero) -> int:
	return MAX_RETURNS + (1 if hero.chosen else 0)


static func ignore(world: World, hero: Hero) -> void:
	_take(world, hero)
	hero.fate = &"rest"


## Заточить душу героя в оружие и воздвигнуть пустой трон в глухом месте.
static func curse(world: World, hero: Hero) -> Landmark:
	# Пустой трон встаёт в глухих руинах, если такие есть.
	var ruin := RuinSystem.remote_ruin(world)
	var cell := ruin.cell if ruin != null else _remote_cell(world)
	if cell < 0:
		return null
	_take(world, hero)
	hero.fate = &"cursed"
	# Душа избранника бога заточается в оружие этого бога.
	var god := LoreDB.god(hero.patron_god) if hero.patron_god != &"" else null
	var weapon := god.curse_weapon if god != null and not god.curse_weapon.is_empty() else hero.hero_class.weapon
	var artifact := "%s %s" % [weapon, _genitive(hero.name)]
	var region := world.region_at(cell)
	world.ensure_region_name(region)
	var lm := world.add_landmark(&"throne", "Трон %s%s" % [_genitive(hero.name), (" в руинах %s" % ruin.name.trim_prefix("Руины ")) if ruin != null else ""], cell, hero.id)
	lm.artifact = artifact + " (проклятый)"
	lm.guardian = hero.power() * 1.6 + 1500.0
	world.log_event(&"fate", "Судьба прокляла героя %s: его душа заточена в оружие «%s». В регионе %s возник пустой трон, его стережёт чудовище." % [
		hero.display_name(), artifact, region.name], PackedInt32Array())
	return lm


static func _take(world: World, hero: Hero) -> void:
	var i := world.fate_queue.find(hero.id)
	if i >= 0:
		world.fate_queue.remove_at(i)


## Глухое место: ничья земля (или горы), подальше от столиц.
static func _remote_cell(world: World) -> int:
	var rng := world.rng
	var best := -1
	var best_score := -INF
	for attempt in 200:
		var c := rng.randi_range(0, world.map.cell_count() - 1)
		if not world.map.is_land(c) or world.city_cell[c] >= 0:
			continue
		var score := rng.randf()
		if world.owner[c] < 0:
			score += 2.0
		var b := world.map.biome[c]
		if b == Biome.MOUNTAINS or b == Biome.SWAMP or b == Biome.SNOW or b == Biome.DESERT:
			score += 1.0
		if score > best_score:
			best_score = score
			best = c
	return best


## «Эдрик» → «Эдрика»: грубое родительное для имён (для названий артефактов).
static func _genitive(name: String) -> String:
	var last := name[name.length() - 1]
	if last in ["а"]:
		return name.substr(0, name.length() - 1) + "ы"
	if last in ["я"]:
		return name.substr(0, name.length() - 1) + "и"
	if "аеёиоуыэюя".contains(last):
		return name
	return name + "а"
