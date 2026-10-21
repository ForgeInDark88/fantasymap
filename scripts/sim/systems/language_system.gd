class_name LanguageSystem
extends RefCounted
## Языки и наречия (этап 11.C). У каждого народа — праязык; край говорит на
## языке своих жителей и медленно переходит на язык владельца (быстрее —
## если языки одной семьи). Края далеко от столицы (и государства, отколовшиеся
## от державы своего языка) рождают наречия; наречие, прожившее долго и
## широко, становится самостоятельным языком. Режим карты «Языки».
##
## Ход: раз в PERIOD лет в «свой» год государства (как культура); раз в год —
## подсчёт краёв, наречия → языки, вымершие языки.

const PERIOD := 5
## Переход края на язык владельца за год (× стабильность); своя семья — вдвое быстрее.
const ASSIM_RATE := 0.025
## Наречие: шанс в год для края дальше этой доли ширины карты от столицы.
const DIALECT_CHANCE := 0.008
const DIALECT_DIST := 0.1
## Наречие становится языком через столько лет при стольких краях.
const LANGUAGE_YEARS := 120
const LANGUAGE_REGIONS := 3


static func title(world: World, id: int) -> String:
	if id < 0 or id >= world.languages.size():
		return "—"
	var l := world.languages[id]
	return ("наречие " if l.dialect else "язык ") + l.name


## Корень семьи языков (праязык).
static func root(world: World, id: int) -> int:
	var cur := id
	var guard := 0
	while cur >= 0 and world.languages[cur].parent >= 0 and guard < 64:
		cur = world.languages[cur].parent
		guard += 1
	return cur


## Праязык народа (создаётся при первой нужде).
static func proto(world: World, race: RaceDef) -> int:
	for l in world.languages:
		if l.parent < 0 and l.race == race:
			return l.id
	var l := Language.new()
	l.id = world.languages.size()
	l.race = race
	l.name = NameGenerator.place_name(race, world.rng)
	l.color = race.color.lerp(Color.from_hsv(world.rng.randf(), 0.5, 0.85), 0.25)
	l.born = world.year
	world.languages.append(l)
	return l.id


## Наречие языка parent_id в краях region_ids.
static func new_dialect(world: World, parent_id: int, region_ids: PackedInt32Array) -> int:
	var parent := world.languages[parent_id]
	var l := Language.new()
	l.id = world.languages.size()
	l.race = parent.race
	l.parent = parent_id
	l.dialect = true
	l.name = NameGenerator.place_name(parent.race, world.rng)
	var h := parent.color.h + world.rng.randf_range(-0.07, 0.07)
	l.color = Color.from_hsv(fposmod(h, 1.0), clampf(parent.color.s * world.rng.randf_range(0.8, 1.2), 0.2, 1.0),
		clampf(parent.color.v * world.rng.randf_range(0.8, 1.15), 0.3, 1.0))
	l.born = world.year
	world.languages.append(l)
	for rid in region_ids:
		world.regions[rid].language = l.id
		world.regions[rid].lang_assim = 0.0
	world.count(&"dialects")
	return l.id


## Языки при создании мира: края государств — на праязыке их народа.
static func seed_world(world: World) -> void:
	for n in world.nations:
		if not n.alive:
			continue
		n.language = proto(world, n.race)
		for rid in n.region_counts:
			if world.regions[rid].language < 0:
				world.regions[rid].language = n.language


func tick(world: World, nation: Nation) -> void:
	if (world.year + nation.id + 3) % PERIOD != 0:
		return
	var rng := world.rng
	if nation.capital_city >= 0:
		var cap_lang := world.regions[world.region_of[world.cities[nation.capital_city].cell]].language
		if cap_lang >= 0:
			nation.language = cap_lang
	if nation.language < 0:
		nation.language = proto(world, nation.race)
	var cap := world.cities[nation.capital_city].cell if nation.capital_city >= 0 else -1
	var cap_pos := world.map.cell_pos(cap) if cap >= 0 else Vector2i.ZERO
	var far := float(world.map.width) * DIALECT_DIST
	var nroot := root(world, nation.language)
	var rate := ASSIM_RATE * PERIOD * (0.4 + nation.stability)
	var dialect_regions := PackedInt32Array()
	for rid in nation.region_counts:
		var region := world.regions[rid]
		if region.controller() != nation.id:
			continue
		if region.language < 0:
			region.language = nation.language
			continue
		if region.language != nation.language:
			region.lang_assim += rate * (2.0 if root(world, region.language) == nroot else 1.0)
			if region.lang_assim >= 1.0:
				region.language = nation.language
				region.lang_assim = 0.0
				world.count(&"language_shifts")
			continue
		if cap >= 0 and dialect_regions.is_empty():
			var d := Vector2(world.map.cell_pos(region.center) - cap_pos).length()
			if d > far and rng.randf() < DIALECT_CHANCE * PERIOD * (d / far):
				dialect_regions.append(rid)
	if not dialect_regions.is_empty():
		# Наречие захватывает и соседние края того же языка, тоже далёкие от столицы.
		var first := world.regions[dialect_regions[0]]
		for nb in first.neighbors:
			var r := world.regions[nb]
			if r.language == nation.language and r.controller() == nation.id and dialect_regions.size() < 4 \
					and Vector2(world.map.cell_pos(r.center) - cap_pos).length() > far * 0.8:
				dialect_regions.append(nb)
		var parent := nation.language
		var id := new_dialect(world, parent, dialect_regions)
		if rng.randf() < 0.35:
			world.log_event(&"language", "В дальних краях государства %s (%s) заговорили по-своему: родилось %s (от: %s)." % [
				nation.short_name, first.name, title(world, id), title(world, parent)], PackedInt32Array([nation.id]))


## Раз в год: сколько краёв говорит; старые широкие наречия становятся языками; вымершие — уходят.
func tick_year(world: World) -> void:
	for l in world.languages:
		l.regions = 0
	for r in world.regions:
		if r.language >= 0:
			world.languages[r.language].regions += 1
	for l in world.languages:
		if not l.alive:
			continue
		if l.regions == 0 and world.year - l.born > 5:
			l.alive = false
			if not l.dialect:
				world.log_event(&"language", "Умолк %s: на нём больше никто не говорит." % title(world, l.id))
			continue
		if l.dialect and world.year - l.born >= LANGUAGE_YEARS and l.regions >= LANGUAGE_REGIONS:
			var was := title(world, l.id)
			l.dialect = false
			world.count(&"languages_born")
			world.log_event(&"language", "%s стало самостоятельным языком — %s." % [was.left(1).to_upper() + was.substr(1), title(world, l.id)])
