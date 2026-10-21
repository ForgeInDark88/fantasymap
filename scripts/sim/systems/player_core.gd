class_name PlayerCore
extends RefCounted
## Ядро режима «Сыграй за героя» (часть PlayerSystem): кто герой игрока,
## журнал, начало и конец игры, наследники, репутация, раны, сила в бою,
## спутники, развитие.

## Шанс в месяц события в пути (в дороге — выше).
const EVENT_CHANCE := 0.06
const TRAVEL_EVENT_CHANCE := 0.12
## Морской переход между прибрежными краями (месяцев).
const SEA_MONTHS := 3
## Предел записей журнала.
const JOURNAL_MAX := 200
## Риск охоты на чудовищ (ниже, чем у автономных героев: игрок выбирает сам).
const HUNT_RISK := 0.02
## Раны: заживление в месяц (в пути и без дела / отдых / отдых в городе), рана на охоте, в поединке.
const HEAL_IDLE := 0.04
const HEAL_REST := 0.12
const HEAL_CITY := 0.25
const HUNT_WOUND := Vector2(0.2, 0.45)
const DUEL_WOUND := Vector2(0.3, 0.7)
## Награда державы за чудовище и доля добычи в руинах (золотом).
const BOUNTY := Vector2(5.0, 15.0)
const LOOT := Vector2(10.0, 40.0)
## Стартовый кошель своего героя; сила спутника в бою героя игрока.
const START_GOLD := 30.0
const COMPANION_SHARE := 0.5
## Развитие: что даёт очко.
const PERKS := {"strength": "Сила (+8% к силе)", "wit": "Ум (+0.04 к уму)", "charm": "Обаяние (скидки, переговоры, репутация)"}


static func hero_of(world: World) -> Hero:
	return world.heroes[world.player] if world.player >= 0 and world.player < world.heroes.size() else null


static func is_player(world: World, hero: Hero) -> bool:
	return world.player == hero.id and world.player >= 0


static func note(world: World, text: String) -> void:
	world.player_journal.append({"year": world.year, "month": world.month, "text": text})
	if world.player_journal.size() > JOURNAL_MAX:
		world.player_journal.remove_at(0)


# ---------------------------------------------------------------------------
# Начало и конец игры за героя
# ---------------------------------------------------------------------------


## Взять под управление героя-странника.
static func take_control(world: World, hero_id: int) -> bool:
	if not Features.HERO_PLAY or hero_id < 0 or hero_id >= world.heroes.size():
		return false
	var h := world.heroes[hero_id]
	if not h.alive or h.is_ruler:
		return false
	world.player = hero_id
	world.count(&"player_heroes")
	world.player_cmd = {}
	world.player_choice = {}
	world.player_idle = 0
	h.goal_cell = -1
	h.party_leader = -1
	note(world, "Вы — %s, %s, %s. Мир ждёт ваших дел." % [h.display_name(), h.race.display_name.to_lower(), h.hero_class.display_name.to_lower()])
	return true


## Создать своего героя: раса, класс, имя, стартовый регион.
static func create_hero(world: World, race: RaceDef, cls: HeroClassDef, name: String, region_id: int) -> Hero:
	if not Features.HERO_PLAY or race == null or cls == null or region_id < 0 or region_id >= world.regions.size() or world.regions[region_id].cells.is_empty():
		return null
	var region := world.regions[region_id]
	world.ensure_region_name(region)
	var clean := name.strip_edges()
	if clean.is_empty() or world.used_names.has(clean):
		clean = ""
	var hero := HeroSystem.make_hero(world, race, cls, region.cells[world.rng.randi_range(0, region.cells.size() - 1)], clean)
	if not clean.is_empty():
		world.used_names[clean] = true
	hero.level = 1
	hero.gold = START_GOLD
	hero.add_deed(world, "начал свой путь в регионе %s" % region.name)
	world.log_event(&"hero", "В регионе %s начал свой путь герой %s — %s, %s." % [region.name, hero.name,
		race.display_name.to_lower(), cls.display_name.to_lower()])
	take_control(world, hero.id)
	return hero


## Вернуться к наблюдению.
static func release(world: World) -> void:
	world.player = -1
	world.player_cmd = {}
	world.player_choice = {}
	world.player_journal.clear()
	world.player_rep.clear()
	world.player_quests.clear()
	world.player_offers.clear()
	world.player_idle = 0


## Кем можно продолжить после гибели: дети, ученики, супруг, спутники.
static func successors(world: World, hero: Hero) -> Array[Hero]:
	var res: Array[Hero] = []
	var ids: Array[int] = []
	ids.append_array(Array(hero.children))
	for o in world.heroes:
		if o.mentor == hero.id or o.party_leader == hero.id:
			ids.append(o.id)
	if hero.spouse >= 0:
		ids.append(hero.spouse)
	for id in ids:
		var h := world.heroes[id]
		if h.alive and not h.is_ruler and not res.has(h):
			res.append(h)
	return res


## Герой игрока погиб: «Чертоги Судьбы» с выбором продолжения (вызывает Hero.die).
static func on_death(world: World, hero: Hero) -> void:
	world.count(&"player_deaths")
	note(world, "%s пал. Душа уходит в Чертоги Судьбы." % hero.display_name())
	var options: Array = []
	for s in successors(world, hero).slice(0, 2):
		options.append({"text": "Продолжить за героя %s" % s.display_name(), "act": "heir", "hero": s.id})
	options.append({"text": "Выбрать другого героя", "act": "pick"})
	options.append({"text": "Вернуться к наблюдению", "act": "observe"})
	world.player_cmd = {}
	world.player_choice = {"kind": "death", "title": "Чертоги Судьбы",
		"text": "%s погиб на %d-м году жизни, совершив %d деяний. Судьба ещё решит участь его души, а ваша история может продолжиться." % [
			hero.display_name(), hero.age, hero.deeds.size()], "options": options}


# ---------------------------------------------------------------------------
# Репутация, раны, спутники, развитие
# ---------------------------------------------------------------------------


static func rep(world: World, key: String, amount: float) -> void:
	world.player_rep[key] = clampf(float(world.player_rep.get(key, 0.0)) + amount, -1.0, 1.0)


## Рана героя игрока; при ранах ≥ 1 — гибель (cause — для летописи).
static func wound(world: World, h: Hero, amount: float, cause: String) -> void:
	h.wounds = minf(1.0, h.wounds + amount)
	if h.wounds >= 1.0:
		world.log_event(&"hero", "Герой %s %s." % [h.display_name(), cause])
		h.die(world)
	elif h.wounds > 0.6:
		note(world, "Раны тяжелы (%d%%): пора к лекарю или на отдых." % roundi(h.wounds * 100.0))


## Сила в бою с учётом спутников по отряду.
static func fight_power(world: World, h: Hero) -> float:
	var p := h.power()
	for o in world.wandering_heroes():
		if o.party_leader == h.id and o.alive and o.cell >= 0 and h.cell >= 0 and world.region_of[o.cell] == world.region_of[h.cell]:
			p += o.power() * COMPANION_SHARE
	return p


static func companions(world: World, h: Hero) -> Array[Hero]:
	var res: Array[Hero] = []
	for o in world.wandering_heroes():
		if o.party_leader == h.id and o.alive:
			res.append(o)
	return res


static func _companion_candidate(world: World, h: Hero) -> Hero:
	var rid := world.region_of[h.cell]
	for o in world.wandering_heroes():
		if o != h and o.alive and o.party_leader < 0 and o.nation_id < 0 and o.cell >= 0 and world.region_of[o.cell] == rid \
				and o.bond(h.id) + h.charm * 0.05 > 0.2 and not companions(world, o).size() > 0:
			return o
	return null


## Вложить очко развития: "strength", "wit" или "charm".
static func spend_perk(world: World, stat: String) -> bool:
	var h := hero_of(world)
	if h == null or h.perk_points <= 0 or not PERKS.has(stat):
		return false
	h.perk_points -= 1
	h.set(stat, int(h.get(stat)) + 1)
	note(world, "Развитие: %s." % String(PERKS[stat]).to_lower())
	return true
