class_name Nation
extends RefCounted
## Государство. id совпадает с индексом в World.nations и никогда не переиспользуется
## (погибшие государства остаются с alive = false — для летописи и истории).
##
## Поля, помеченные «учёт World», меняются только через World.set_owner(),
## остальные — системами симуляции (scripts/sim/systems).

var id := -1
## Полное название («Королевство Альмар») и короткое — для подписи на карте.
var name := ""
var short_name := ""
var race_id: StringName
var race: RaceDef
var color := Color.WHITE

var ruler_name := ""
var ruler_title := ""
var ruler_age := 30
## Сколько лет ещё продлится правление (до смерти или до выборов).
var reign_left := 20
var ruler_trait: RulerTraitDef
## Номер правителя с таким именем в династии (Эдрик II); 1 — без номера.
var ruler_number := 1
var government: GovernmentDef
## Правящий род и имена его правителей (для порядковых номеров).
var dynasty := ""
var dynasty_names: Dictionary[String, int] = {}
## Присягнувшие государству герои (id в World.heroes).
var hero_ids := PackedInt32Array()

var capital_city := -1
var city_ids := PackedInt32Array()

# --- Территория (учёт World) ---
var cells := PackedInt32Array()
var cell_count: int:
	get:
		return cells.size()
## Территория менялась с прошлой проверки анклавов (EnclaveSystem).
var territory_dirty := true
var sum_x := 0.0
var sum_y := 0.0
## Добыча с клеток территории в год (по Goods), без построек и бонусов.
var yields := PackedFloat32Array()
## Регионы, где у государства есть клетки: id региона → число клеток (учёт World).
var region_counts: Dictionary[int, int] = {}
## Соседи по суше: id государства → длина общей границы (учёт World).
var borders: Dictionary[int, int] = {}

# --- Население по расам (индекс = RaceDef.index) ---
## Жители. Покорённые народы остаются жить в своих клетках.
var pop := PackedFloat32Array()
## Сколько жителей каждой расы может прокормить территория (учёт World).
var capacity := PackedFloat32Array()
var population: float:
	get:
		var total := 0.0
		for p in pop:
			total += p
		return total

# --- Экономика ---
## Запасы ресурсов (по Goods).
var stock := PackedFloat32Array()
## Чистый прирост запасов за последний год (по Goods).
var income := PackedFloat32Array()
var wealth: float:
	get:
		return stock[Goods.GOLD]
var army := 0.0
## 0..1 — при низкой стабильности государство распадается (этап 4).
var stability := 0.8
var tech := 0.0
## Накопленные «очки» экспансии (тратятся на занятие клеток).
var expansion_points := 0.0
var famine_years := 0

# --- Суммарные эффекты построек (пересчитывает CitySystem) ---
var food_bonus := 0.0
var stability_bonus := 0.0
var army_bonus := 0.0
var science_bonus := 0.0
var building_production := PackedFloat32Array()

# --- Дипломатия (меняет Diplomacy / системы этапа 4) ---
## Сюзерен (-1 — независимо) и год, с которого государство — вассал.
var overlord := -1
var vassal_since := 0
var allies: Dictionary[int, bool] = {}
var trade_partners: Dictionary[int, bool] = {}
## Сколько лет подряд экспансии некуда расти (повод для войны и колоний).
var stalled_years := 0
## Сколько лет подряд стабильность на дне (повод для распада).
var collapse_years := 0
## Временные эффекты событий: {id, until, army_mult, growth_mult, science_mult}.
var modifiers: Array[Dictionary] = []

# --- Технологии (TechSystem) ---
## Открытые технологии (id → true, в порядке открытия), изучаемая сейчас и
## накопленные на неё очки; tech_seen — значение tech на прошлом пересчёте.
var techs: Dictionary[StringName, bool] = {}
var researching: StringName = &""
var research := 0.0
var tech_seen := 0.0

# --- Разведка и наследие (SpySystem, LegacySystem) ---
## Очки разведки: копятся от золота, тайных канцелярий и шпионов-героев.
var intel := 0.0
## Соседи по подземным ходам (кэш UndergroundSystem, не сохраняется).
var tunnel_neighbors: Dictionary = {}
## Организации, где государство состоит (кэш OrgSystem, id в World.orgs).
var org_ids := PackedInt32Array()
## Наследие империи, осколком которой государство является (-1 — нет).
var legacy := -1

# --- Культура (CultureSystem) ---
## Культура государства (id в World.cultures) и её «вес» — престиж, мягкая сила.
var culture := -1
## Язык государства (id в World.languages; LanguageSystem): язык края столицы.
var language := -1
var culture_level := 0.0

# --- Вера (ReligionSystem) ---
## Государственная религия (id в World.religions, -1 — нет) и доля её
## последователей среди подданных (по клеткам регионов).
var state_religion := -1
var faith_unity := 1.0

# --- Эффекты (религия, технологии, организации, кризисы) ---
## Источник → {ключ: значение}. Ключи *_mult перемножаются, остальные
## (stability) складываются; итог — в effects (см. set_effects / effect).
## Милость бога (GodSystem): чей дар и до какого года (эффекты — в effect_sources[&"god"]).
var god_boon: StringName = &""
var god_boon_until := 0
var effect_sources: Dictionary[StringName, Dictionary] = {}
var effects: Dictionary[StringName, float] = {}

## Клетка последней столицы (для руин храма, когда государство падёт).
var home_cell := -1

var founded_year := 0
var alive := true
## Клетка для подписи названия.
var label_cell := -1


func _init() -> void:
	var races := RaceDB.count()
	pop.resize(races)
	capacity.resize(races)
	yields.resize(Goods.COUNT)
	stock.resize(Goods.COUNT)
	income.resize(Goods.COUNT)
	building_production.resize(Goods.COUNT)


const ROMAN: Array[String] = ["", "", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]


func ruler_display() -> String:
	var number := " " + ROMAN[ruler_number] if ruler_number > 1 and ruler_number < ROMAN.size() else ""
	return "%s %s%s" % [ruler_title, ruler_name, number]


## Политический множитель: форма правления × характер правителя × эффекты
## веры, технологий и прочего (aggression_mult, trade_mult, science_mult, army_mult).
func policy(key: String) -> float:
	var m: float = effects.get(StringName(key), 1.0)
	if government != null:
		m *= government.get(key)
	if ruler_trait != null:
		m *= ruler_trait.get(key)
	return m


func policy_stability() -> float:
	return (government.stability_bonus if government != null else 0.0) + (ruler_trait.stability if ruler_trait != null else 0.0) \
			+ effects.get(&"stability", 0.0)


## Задаёт эффекты одного источника (&"religion", &"techs"…) и пересчитывает итог.
func set_effects(source: StringName, values: Dictionary) -> void:
	if values.is_empty():
		effect_sources.erase(source)
	else:
		effect_sources[source] = values
	effects.clear()
	for src in effect_sources:
		var d: Dictionary = effect_sources[src]
		for k in d:
			var key := StringName(k)
			if String(key).ends_with("_mult"):
				effects[key] = effects.get(key, 1.0) * float(d[k])
			else:
				effects[key] = effects.get(key, 0.0) + float(d[k])


## Итоговый эффект по ключу: множитель (1 по умолчанию) или прибавка (0).
func effect(key: StringName) -> float:
	return effects.get(key, 1.0 if String(key).ends_with("_mult") else 0.0)


func total_capacity() -> float:
	var total := 0.0
	for c in capacity:
		total += c
	return total * (1.0 + food_bonus + effect(&"food"))


func centroid() -> Vector2:
	var n := cells.size()
	return Vector2(sum_x / n, sum_y / n) if n > 0 else Vector2.ZERO


## Доля «титульной» расы в населении (1 — однородное государство).
func primary_share() -> float:
	var total := population
	return pop[race.index] / total if total > 0.0 else 1.0


## Произведение множителя mult_key по действующим временным эффектам.
func modifier(mult_key: String) -> float:
	var m := 1.0
	for mod in modifiers:
		m *= mod.get(mult_key, 1.0)
	return m


## Военная мощь: армия × наука × стабильность × снаряжение (металл) × особенности.
func power() -> float:
	if not alive:
		return 0.0
	var p := army * (1.0 + tech * 0.04) * (0.6 + 0.4 * stability)
	p *= 1.0 + 0.25 * clampf(stock[Goods.METAL] / (army / 200.0 + 1.0), 0.0, 1.0)
	if race.has_trait(&"warlike"):
		p *= 1.2
	return p * modifier("army_mult") * policy("army_mult") * (1.0 + 0.25 * sources) + hero_power + merc_power

## Вклад присягнувших героев в военную мощь (пересчитывает HeroSystem).
var hero_power := 0.0
## Нанятые вольные отряды (MercSystem): их сила в бою.
var merc_power := 0.0

# --- Рынок и общество (этап 11.D, MarketSystem) ---
## По товарам рынка (MarketDB, индекс — позиция): запас, цена, за прошлый год —
## произведено, потреблено, вывезено, ввезено, испорчено; спрос за год.
var market_stock := PackedFloat32Array()
var market_price := PackedFloat32Array()
var market_made := PackedFloat32Array()
var market_used := PackedFloat32Array()
var market_out := PackedFloat32Array()
var market_in := PackedFloat32Array()
var market_lost := PackedFloat32Array()
var market_demand := PackedFloat32Array()
## Сословия (доли, сумма 1): знать, горожане, крестьяне, рабы.
var classes := PackedFloat32Array([0.04, 0.12, 0.84, 0.0])
## Рабство дозволено; индекс цен (инфляция; 1 — как при основании).
var slavery := false
var inflation := 1.0
## Сколько источников силы контролирует государство (пересчитывает EconomySystem).
var sources := 0
