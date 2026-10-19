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
## Сколько лет ещё продлится правление.
var reign_left := 20

var capital_city := -1
var city_ids := PackedInt32Array()

# --- Территория (учёт World) ---
var cells := PackedInt32Array()
var cell_count: int:
	get:
		return cells.size()
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


func ruler_display() -> String:
	return "%s %s" % [ruler_title, ruler_name]


func total_capacity() -> float:
	var total := 0.0
	for c in capacity:
		total += c
	return total * (1.0 + food_bonus)


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
	return p * modifier("army_mult")
