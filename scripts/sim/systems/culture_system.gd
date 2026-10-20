class_name CultureSystem
extends RefCounted
## Культура: ассимиляция регионов и народов, престиж, мягкая сила.
##
## Регион под властью государства другой культуры постепенно её перенимает —
## быстрее при общей вере, родственном народе, сильной власти и высокой
## культуре владельца, медленнее у терпимых вер и рыхлых форм правления
## (кланы, племена). Перенявший культуру регион лоялен; родственные народы
## (не враждебные титульному) вместе с культурой перенимают и язык — их клетки
## переходят к народу государства. Это мирная альтернатива бунтам.
## Престиж культуры (города, храмы, библиотеки, университеты, чудеса, знания,
## возраст державы) располагает соседей, а маленькие соседи могут сами
## попроситься под покровительство блестящей державы.

## Раз в сколько лет пересчитывать (со сдвигом по id).
const PERIOD := 5
## Базовый ход ассимиляции региона в год (при 1.0 регион перенимает культуру).
const ASSIM_RATE := 0.012
## Шанс в год маленькому соседу попроситься в вассалы культурной державы.
const SOFT_VASSAL_CHANCE := 0.012
const CUSTOMS: Array[String] = ["кровная месть", "почитание предков", "закон гостеприимства", "морские праздники",
	"кочевые обычаи", "клановые советы", "поединки чести", "ремесленные гильдии", "праздник урожая",
	"обряды луны", "татуировки воинов", "культ поэтов", "каменные курганы", "общинные пиры",
	"устная летопись", "ночные бдения", "торговые клятвы", "песни о героях", "молчаливые старейшины",
	"брачные выкупы", "охотничьи посвящения"]
## Скорость ассимиляции по форме правления.
const GOV_ASSIM := {&"empire": 1.4, &"monarchy": 1.1, &"republic": 1.0, &"oligarchy": 0.9, &"theocracy": 1.2,
	&"necrocracy": 0.8, &"clans": 0.7, &"tribal": 0.6}
## Вклад построек в престиж культуры.
const BUILDING_PRESTIGE := {&"temple": 1.0, &"library": 2.0, &"university": 4.0, &"wonder": 12.0, &"mage_tower": 2.0,
	&"sacred_grove": 2.0, &"market": 0.5, &"necropolis": 1.0, &"bank": 1.0}


func tick(world: World, nation: Nation) -> void:
	if (world.year + nation.id + 2) % PERIOD != 0 or nation.culture < 0:
		return
	nation.culture_level = prestige(world, nation)
	var faith := world.religions[nation.state_religion] if nation.state_religion >= 0 and nation.state_religion < world.religions.size() else null
	var tolerance := faith.tolerance if faith != null else 0.5
	var base: float = ASSIM_RATE * PERIOD * GOV_ASSIM.get(nation.government.id if nation.government != null else &"", 1.0) \
			* (0.5 + nation.stability) * (1.0 + nation.culture_level / (nation.culture_level + 40.0)) \
			* (1.3 - tolerance * 0.6) * nation.effect(&"culture_mult")
	for rid in nation.region_counts:
		var region := world.regions[rid]
		if region.culture < 0:
			region.culture = nation.culture
		if region.culture == nation.culture or region.controller() != nation.id:
			continue
		var people := world.cell_race[region.center] if region.center >= 0 else World.NO_RACE
		var kin := 1.6 if people == nation.race.index else (1.0 if people == World.NO_RACE or nation.race.relation_to(RaceDB.by_index(people)) > 0.0 else 0.5)
		var shared_faith: float = 0.5 + region.faith.get(nation.state_religion, 0.0)
		region.assim += base * kin * shared_faith
		if region.assim >= 1.0:
			assimilate(world, nation, region)
	_soft_power(world, nation)


static func assimilate(world: World, nation: Nation, region: Region) -> void:
	var old := world.cultures[region.culture].name if region.culture >= 0 else "—"
	region.culture = nation.culture
	region.assim = 0.0
	world.count(&"assimilations")
	region.unrest *= 0.5
	# Не враждебные титульному народу жители перенимают и язык.
	var converted := 0
	for c in region.cells:
		if world.owner[c] != nation.id:
			continue
		var r := world.cell_race[c]
		if r == World.NO_RACE or r == nation.race.index:
			continue
		if nation.race.relation_to(RaceDB.by_index(r)) > -0.3 and not RaceDB.by_index(r).has_trait(&"demonic"):
			world.convert_cell_race(c, nation.race.index)
			converted += 1
	if converted > 0 or world.rng.randf() < 0.3:
		world.log_event(&"culture", "Регион %s (%s) перенял культуру %s%s." % [region.name, nation.short_name,
			world.cultures[nation.culture].name, (" — прежние обычаи (%s) забыты" % old) if converted > 0 else ""],
			PackedInt32Array([nation.id]))


## Блестящая держава притягивает слабых соседей под своё покровительство.
func _soft_power(world: World, nation: Nation) -> void:
	var d := world.diplomacy
	if nation.overlord >= 0 or not d.wars_of(nation.id).is_empty():
		return
	for other_id in nation.borders:
		var big := world.nations[other_id]
		if not big.alive or big.overlord >= 0 or big.race.has_trait(&"demonic"):
			continue
		if big.culture_level < nation.culture_level * 2.0 + 5.0 or nation.power() > big.power() * 0.3:
			continue
		if d.opinion(world, nation.id, other_id) < 0.2 or world.rng.randf() > SOFT_VASSAL_CHANCE * PERIOD:
			continue
		d.set_overlord(world, nation.id, other_id)
		world.log_event(&"culture", "%s, очарованное культурой державы %s, добровольно переходит под её покровительство." % [
			nation.name, big.name], PackedInt32Array([nation.id, other_id]))
		return


## Престиж культуры: города (по уровню), постройки, знания и возраст державы.
static func prestige(world: World, nation: Nation) -> float:
	var p := 0.0
	for id in nation.city_ids:
		var city := world.cities[id]
		p += pow(city.tier() + 1.0, 1.3) * 0.5
		for b in city.buildings:
			p += BUILDING_PRESTIGE.get(b, 0.2)
	p += nation.techs.size() * 0.6
	p += sqrt(maxf(0.0, world.year - nation.founded_year)) * 0.5
	return p * nation.effect(&"culture_mult")


## Новая культура государства: имя по его названию, цвет — близкий к его цвету.
static func new_culture(world: World, nation: Nation) -> Culture:
	var c := Culture.new()
	c.id = world.cultures.size()
	c.name = nation.short_name
	c.race = nation.race.index
	c.origin_nation = nation.id
	c.founded_year = world.year
	var base := nation.color
	c.color = Color.from_hsv(fposmod(base.h + world.rng.randf_range(-0.04, 0.04), 1.0), clampf(base.s * 0.85, 0.3, 1.0), clampf(base.v, 0.5, 0.95))
	var a := world.rng.randi_range(0, CUSTOMS.size() - 1)
	var b := (a + world.rng.randi_range(1, CUSTOMS.size() - 1)) % CUSTOMS.size()
	c.customs = PackedStringArray([CUSTOMS[a], CUSTOMS[b]])
	world.cultures.append(c)
	return c


## Культура большинства группы регионов (для отколовшихся земель).
static func majority_culture(world: World, region_ids: PackedInt32Array, fallback: int) -> int:
	var sum := {}
	for rid in region_ids:
		var region := world.regions[rid]
		if region.culture >= 0:
			sum[region.culture] = sum.get(region.culture, 0) + region.cells.size()
	var best := fallback
	var best_v := 0
	for c in sum:
		if sum[c] > best_v:
			best_v = sum[c]
			best = c
	return best
