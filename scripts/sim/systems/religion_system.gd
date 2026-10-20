class_name ReligionSystem
extends RefCounted
## Религии: распространение, эффекты догматов, ереси и расколы.
##
## Раз в год (в день государства) вера государства давит на его регионы —
## тем сильнее, чем выше миссионерство, стабильность и чем охотнее народ
## региона принимает эту веру; соседние регионы и торговые партнёры приносят
## свои веры, миссионеры (особенно при жрецах и паладинах на службе) — в
## соседние страны, а завоеватели-фанатики обращают покорённых силой.
## Единство веры влияет на стабильность, догматы — на экономику, армию и рост.
## При слабой власти и большой территории в государственной вере рождается
## ересь; у теократий и фанатиков она может обернуться расколом — религиозной
## гражданской войной. Если подданные почти все сменили веру, правитель
## принимает её сам.

## Раз в сколько лет пересчитывать веры государства (со сдвигом по id); скорости
## ниже — за год и умножаются на период.
const PERIOD := 3
## Скорость обращения подданных в государственную веру (доля в год × миссионерство).
const CONVERT_RATE := 0.035
## Влияние веры соседнего региона.
const NEIGHBOR_RATE := 0.02
## Влияние веры торгового партнёра на один из регионов.
const TRADE_RATE := 0.04
## Сила миссии в соседнюю страну.
const MISSION_RATE := 0.12
## Доли меньше этой исчезают (вера угасла в регионе).
const MIN_SHARE := 0.02
## Ересь: базовый шанс в год, минимальный возраст веры, предел числа живых вер.
const HERESY_CHANCE := 0.0012
const HERESY_MIN_AGE := 60
const MAX_RELIGIONS := 24
## Влияние единства веры на стабильность: (единство − 0.75) × это × нетерпимость.
const UNITY_STABILITY := 0.16

## Шаблоны имён ересей: пророк (имена на языке расы не склоняются).
const HERESY_NAMES: Array[String] = ["Учение %s", "Путь %s", "Братство %s", "Откровение %s", "Слово %s"]
const HERESY_DOGMAS: Array[String] = ["Бедность духовенства", "Прямая молитва без жрецов", "Святость меча",
	"Тайное знание избранных", "Покаяние огнём", "Равенство перед богом", "Почитание пророка",
	"Отказ от роскоши", "Священная торговля", "Учение о конце времён"]
const EFFECT_KEYS: Array[StringName] = [&"science_mult", &"army_mult", &"trade_mult", &"growth_mult", &"aggression_mult"]


func tick(world: World, nation: Nation) -> void:
	if world.religions.is_empty() or (world.year + nation.id) % PERIOD != 0:
		return
	var rng := world.rng
	if nation.state_religion < 0:
		nation.state_religion = pick_for_race(world, nation.race)
	var faith := world.religions[nation.state_religion]
	var mission := faith.missionary * (1.0 + 0.3 * _priests(world, nation)) * (1.0 + 0.4 * _temple_share(world, nation))
	var total := 0
	var followers := 0.0
	var state := nation.state_religion
	var base_rate := CONVERT_RATE * PERIOD * mission * (0.4 + nation.stability)
	var affinity_cache := {}
	for rid in nation.region_counts:
		var region := world.regions[rid]
		var cells: int = nation.region_counts[rid]
		var rf := region.faith
		if rf.is_empty():
			rf[state] = 1.0
		# Народ региона (по центру) — насколько он склонен к этой вере.
		var people := world.cell_race[region.center] if region.center >= 0 else World.NO_RACE
		var affinity: float = affinity_cache.get(people, -1.0)
		if affinity < 0.0:
			affinity = faith.race_affinity(RaceDB.by_index(people)) if people != World.NO_RACE else 0.3
			affinity_cache[people] = affinity
		var rate := base_rate * (0.4 + affinity)
		# Завоеватель-фанатик обращает покорённых силой.
		if world.year - region.conquered_year < PERIOD and faith.zeal > 0.6:
			rate += 0.15
		# Уже целиком своя вера — сдвигать нечего.
		if rf.size() > 1 or not rf.has(state):
			shift(rf, state, rate)
		# Вера соседнего региона (раз в несколько лет — влияние медленное, но дешёвое).
		if not region.neighbors.is_empty() and rng.randf() < 0.5:
			var nb := world.regions[region.neighbors[rng.randi_range(0, region.neighbors.size() - 1)]]
			var other := nb.main_faith()
			if other >= 0 and other != nation.state_religion:
				shift(rf, other, NEIGHBOR_RATE * PERIOD / 0.5 * world.religions[other].missionary * nb.faith[other])
		total += cells
		followers += rf.get(state, 0.0) * cells
	nation.faith_unity = followers / total if total > 0 else 1.0
	_trade_spread(world, nation)
	_missions(world, nation, faith, mission)
	_apply_effects(nation, faith)
	if not _ruler_converts(world, nation):
		_maybe_heresy(world, nation, faith)


## Эффекты догматов и единства веры.
func _apply_effects(nation: Nation, faith: Religion) -> void:
	var e: Dictionary = faith.effects.duplicate()
	e[&"stability"] = e.get(&"stability", 0.0) + (nation.faith_unity - 0.75) * UNITY_STABILITY * (1.5 - faith.tolerance)
	nation.set_effects(&"religion", e)


func _trade_spread(world: World, nation: Nation) -> void:
	var rng := world.rng
	for partner in nation.trade_partners:
		var other := world.nations[partner]
		if other.state_religion < 0 or other.state_religion == nation.state_religion or rng.randf() > 0.15 * PERIOD:
			continue
		var rid := _random_region(world, nation)
		if rid >= 0:
			shift(world.regions[rid].faith, other.state_religion, TRADE_RATE * world.religions[other.state_religion].missionary)


func _missions(world: World, nation: Nation, faith: Religion, mission: float) -> void:
	var rng := world.rng
	if nation.borders.is_empty() or faith.missionary < 0.35 or rng.randf() > mission * 0.12 * PERIOD:
		return
	var keys := nation.borders.keys()
	var target := world.nations[keys[rng.randi_range(0, keys.size() - 1)]]
	if not target.alive or target.state_religion == nation.state_religion:
		return
	var rid := _random_region(world, target)
	if rid < 0:
		return
	var region := world.regions[rid]
	shift(region.faith, nation.state_religion, MISSION_RATE * faith.missionary)
	if rng.randf() < 0.25:
		world.log_event(&"religion", "Миссионеры веры «%s» (%s) проповедуют в регионе %s (%s)." % [
			faith.name, nation.short_name, region.name, target.short_name], PackedInt32Array([nation.id, target.id]))


## Если подданные почти все сменили веру — правитель принимает её.
func _ruler_converts(world: World, nation: Nation) -> bool:
	if nation.faith_unity >= 0.3 or nation.race.has_trait(&"demonic"):
		return false
	var shares := nation_shares(world, nation)
	var best := -1
	for r in shares:
		if best < 0 or shares[r] > shares[best]:
			best = r
	if best < 0 or best == nation.state_religion or shares[best] < 0.55:
		return false
	var old := world.religions[nation.state_religion].name
	nation.state_religion = best
	nation.faith_unity = shares[best]
	nation.stability = maxf(0.0, nation.stability - 0.05)
	world.log_event(&"religion", "%s отрекается от веры «%s» и принимает веру «%s» — её исповедует большинство подданных." % [
		nation.name, old, world.religions[best].name], PackedInt32Array([nation.id]))
	return true


## Ересь: слабая власть, большая территория, давняя вера. У теократий и
## фанатиков — шанс раскола с религиозной гражданской войной.
func _maybe_heresy(world: World, nation: Nation, faith: Religion) -> void:
	var rng := world.rng
	if world.year - faith.founded_year < HERESY_MIN_AGE or nation.region_counts.size() < 4:
		return
	var theocracy := nation.government != null and nation.government.id == &"theocracy"
	var chance := HERESY_CHANCE * PERIOD * (1.0 + (1.0 - nation.stability) * 3.0) * (1.0 + nation.region_counts.size() / 20.0) \
			* (1.8 if theocracy else 1.0) * (0.5 + faith.zeal)
	if rng.randf() > chance:
		return
	start_heresy(world, nation)


## Рождает ересь в дальних регионах государства (панель Бога вызывает напрямую).
## Возвращает новую веру или null.
static func start_heresy(world: World, nation: Nation) -> Religion:
	if alive_count(world) >= MAX_RELIGIONS or nation.state_religion < 0 or nation.capital_city < 0:
		return null
	var rng := world.rng
	var faith := world.religions[nation.state_religion]
	var group := far_regions(world, nation, rng.randi_range(1, 4))
	if group.is_empty():
		return null
	var heresy := _derive(world, faith, nation)
	for rid in group:
		shift(world.regions[rid].faith, heresy.id, 0.6)
	var where := world.regions[group[0]].name
	world.log_event(&"religion", "Ересь в государстве %s: в регионе %s проповедуют «%s» — %s." % [
		nation.name, where, heresy.name, heresy.dogmas[heresy.dogmas.size() - 1].to_lower()], PackedInt32Array([nation.id]))
	# Раскол: теократия или фанатики при слабой власти — религиозная гражданская война.
	var theocracy := nation.government != null and nation.government.id == &"theocracy"
	var schism := (theocracy or faith.zeal > 0.6) and nation.region_counts.size() >= 6 \
			and rng.randf() < (0.55 if theocracy else 0.3) * (1.4 - nation.stability)
	if schism:
		var rebel := world.split_off(nation, group, nation.race)
		if rebel.alive:
			rebel.state_religion = heresy.id
			heresy.origin_nation = rebel.id
			world.log_event(&"religion", "Раскол церкви «%s»: последователи ереси «%s» провозглашают %s." % [
				faith.name, heresy.name, rebel.name], PackedInt32Array([nation.id, rebel.id]))
			world.diplomacy.declare_war(world, rebel.id, nation.id, &"schism")
	return heresy


## Новая вера-ответвление: изменённые догматы и характер.
static func _derive(world: World, faith: Religion, nation: Nation) -> Religion:
	var rng := world.rng
	var r := Religion.new()
	r.id = world.religions.size()
	r.def = faith.def
	r.parent = faith.id
	r.root = faith.root
	r.founded_year = world.year
	r.origin_nation = nation.id
	var prophet := NameGenerator.unique(world.used_names, NameGenerator.person_name.bind(nation.race, rng))
	r.name = HERESY_NAMES[rng.randi_range(0, HERESY_NAMES.size() - 1)] % prophet
	r.symbol = faith.symbol
	r.color = Color.from_hsv(fposmod(faith.color.h + rng.randf_range(-0.12, 0.12), 1.0),
			clampf(faith.color.s * rng.randf_range(0.7, 1.2), 0.25, 1.0), clampf(faith.color.v * rng.randf_range(0.75, 1.1), 0.35, 1.0))
	r.dogmas = faith.dogmas.duplicate()
	r.dogmas.append(HERESY_DOGMAS[rng.randi_range(0, HERESY_DOGMAS.size() - 1)])
	if r.dogmas.size() > 4:
		r.dogmas.remove_at(0)
	r.effects = faith.effects.duplicate()
	for i in rng.randi_range(1, 2):
		var key := EFFECT_KEYS[rng.randi_range(0, EFFECT_KEYS.size() - 1)]
		r.effects[key] = clampf(r.effects.get(key, 1.0) + rng.randf_range(-0.1, 0.12), 0.75, 1.3)
	r.missionary = clampf(faith.missionary + rng.randf_range(-0.15, 0.25), 0.05, 1.0)
	r.tolerance = clampf(faith.tolerance + rng.randf_range(-0.3, 0.2), 0.0, 1.0)
	r.zeal = clampf(faith.zeal + rng.randf_range(-0.1, 0.3), 0.0, 1.0)
	r.magic = faith.magic
	r.undead = faith.undead
	r.demons = faith.demons
	world.religions.append(r)
	return r


## Совсем новая вера (панель Бога): основатель — государство региона.
static func found_religion(world: World, nation: Nation) -> Religion:
	if alive_count(world) >= MAX_RELIGIONS:
		return null
	var rng := world.rng
	var base := world.religions[nation.state_religion] if nation.state_religion >= 0 else world.religions[0]
	var r := _derive(world, base, nation)
	r.parent = -1
	r.root = r.id
	r.name = "Вера %s" % NameGenerator.place_name(nation.race, rng)
	r.color = Color.from_hsv(rng.randf(), rng.randf_range(0.45, 0.8), rng.randf_range(0.65, 0.95))
	r.dogmas = PackedStringArray([HERESY_DOGMAS[rng.randi_range(0, HERESY_DOGMAS.size() - 1)],
		HERESY_DOGMAS[rng.randi_range(0, HERESY_DOGMAS.size() - 1)]])
	nation.state_religion = r.id
	for rid in nation.region_counts:
		shift(world.regions[rid].faith, r.id, 0.5)
	world.log_event(&"religion", "Пророк явился в государстве %s: рождается новая вера — «%s»." % [nation.name, r.name],
			PackedInt32Array([nation.id]))
	return r


# ---------------------------------------------------------------------------
# Раз в год для всего мира: угасание вер.
# ---------------------------------------------------------------------------

func tick_year(world: World) -> void:
	if world.year % 10 != 0:
		return
	var seen := {}
	for region in world.regions:
		for r in region.faith:
			seen[r] = true
	for n in world.nations:
		if n.alive and n.state_religion >= 0:
			seen[n.state_religion] = true
	for faith in world.religions:
		var was := faith.alive
		faith.alive = seen.has(faith.id)
		if was and not faith.alive:
			world.log_event(&"religion", "Угасла вера «%s» — у неё не осталось последователей." % faith.name)


# ---------------------------------------------------------------------------
# Вспомогательное
# ---------------------------------------------------------------------------

## Сдвиг долей: вера r получает долю amount от остальных.
static func shift(faith: Dictionary, r: int, amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if amount <= 0.0:
		return
	var keep := 1.0 - amount
	var drop := -1
	for k in faith:
		var v: float = faith[k] * keep
		faith[k] = v
		if v < MIN_SHARE and k != r:
			drop = k
	faith[r] = faith.get(r, 0.0) + amount
	# Угасшая в регионе вера (за раз — одна, остальные уйдут в следующие годы).
	if drop >= 0:
		faith[r] += faith[drop]
		faith.erase(drop)


## Заселённый регион без веры получает веру первого владельца.
static func ensure_faith(region: Region, religion: int) -> void:
	if region.faith.is_empty() and religion >= 0:
		region.faith[religion] = 1.0


## Государственная вера для расы: по склонностям рас стартовых вер.
static func pick_for_race(world: World, race: RaceDef) -> int:
	var total := 0.0
	for r in world.religions:
		if r.alive and r.parent < 0:
			total += r.race_affinity(race)
	if total <= 0.0:
		return 0 if not world.religions.is_empty() else -1
	var roll := world.rng.randf() * total
	for r in world.religions:
		if r.alive and r.parent < 0:
			roll -= r.race_affinity(race)
			if roll <= 0.0:
				return r.id
	return world.religions[0].id


## Самая распространённая вера в группе регионов (для отколовшихся государств).
static func majority_faith(world: World, region_ids: PackedInt32Array, fallback: int) -> int:
	var sum := {}
	for rid in region_ids:
		var region := world.regions[rid]
		for r in region.faith:
			sum[r] = sum.get(r, 0.0) + region.faith[r] * region.cells.size()
	var best := fallback
	var best_v := 0.0
	for r in sum:
		if sum[r] > best_v:
			best_v = sum[r]
			best = r
	return best


## Доли вер среди подданных государства (по клеткам).
static func nation_shares(world: World, nation: Nation) -> Dictionary:
	var sum := {}
	var total := 0.0
	for rid in nation.region_counts:
		var cells: int = nation.region_counts[rid]
		var region := world.regions[rid]
		for r in region.faith:
			sum[r] = sum.get(r, 0.0) + region.faith[r] * cells
		total += cells
	if total > 0.0:
		for r in sum:
			sum[r] /= total
	return sum


static func alive_count(world: World) -> int:
	var n := 0
	for r in world.religions:
		if r.alive:
			n += 1
	return n


## Дальние от столицы регионы государства, связная группа до count штук.
static func far_regions(world: World, nation: Nation, count: int) -> PackedInt32Array:
	var cap := world.map.cell_pos(world.cities[nation.capital_city].cell)
	var cap_region := world.region_of[world.cities[nation.capital_city].cell]
	var start := -1
	var best_d := -1.0
	for rid in nation.region_counts:
		if rid == cap_region or world.regions[rid].controller() != nation.id:
			continue
		var d := Vector2(world.map.cell_pos(world.regions[rid].center) - cap).length()
		if d > best_d:
			best_d = d
			start = rid
	var group := PackedInt32Array()
	if start < 0:
		return group
	group.append(start)
	var i := 0
	while i < group.size() and group.size() < count:
		for nb in world.regions[group[i]].neighbors:
			if group.size() >= count:
				break
			if nb != cap_region and not group.has(nb) and world.regions[nb].controller() == nation.id:
				group.append(nb)
		i += 1
	return group


func _random_region(world: World, nation: Nation) -> int:
	if nation.region_counts.is_empty():
		return -1
	var keys := nation.region_counts.keys()
	return keys[world.rng.randi_range(0, keys.size() - 1)]


## Жрецы и паладины на службе усиливают миссии.
func _priests(world: World, nation: Nation) -> int:
	var n := 0
	for hid in nation.hero_ids:
		var cls := world.heroes[hid].hero_class.id
		if cls == &"cleric" or cls == &"paladin":
			n += 1
	return n


## Доля городов с храмом.
func _temple_share(world: World, nation: Nation) -> float:
	if nation.city_ids.is_empty():
		return 0.0
	var n := 0
	for id in nation.city_ids:
		if world.cities[id].buildings.has(&"temple"):
			n += 1
	return float(n) / nation.city_ids.size()
