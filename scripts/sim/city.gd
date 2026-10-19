class_name City
extends RefCounted
## Город. Принадлежит государству, но население может быть другой расы
## (например, после завоевания) — это понадобится для многорасовых государств.

## Пороги населения для уровней города.
const TIER_THRESHOLDS: Array[float] = [1500.0, 5000.0, 15000.0, 40000.0]
const TIER_NAMES: Array[String] = ["Деревня", "Городок", "Город", "Крупный город", "Великий город"]

var id := -1
var name := ""
var cell := -1
var nation_id := -1
var race_id: StringName
var population := 0.0
var founded_year := 0
var is_capital := false
var alive := true
## Привлекательность места (реки, побережье, родной биом).
var weight := 1.0
## «Удача» города (логнормальный множитель): одни деревни так и остаются
## деревнями, другие вырастают в великие города.
var luck := 1.0
var coastal := false
## Биомы в радиусе 2 клеток (битовая маска индексов) — для условий построек.
var near_biomes := 0
## id построек (BuildingDef.id).
var buildings: Array[StringName] = []


## 0 — деревня … 4 — великий город.
func tier() -> int:
	var t := 0
	for threshold in TIER_THRESHOLDS:
		if population >= threshold:
			t += 1
	return t


func tier_name() -> String:
	return TIER_NAMES[tier()]


## Чем живёт город — по его постройкам.
func specialization() -> String:
	if buildings.has(&"fortress") or (buildings.has(&"walls") and buildings.has(&"barracks")):
		return "крепость"
	if buildings.has(&"harbor"):
		return "порт"
	if buildings.has(&"deep_mine") or buildings.has(&"mine"):
		return "горняцкий"
	if buildings.has(&"library"):
		return "город учёных"
	if buildings.has(&"market"):
		return "торговый"
	if buildings.has(&"temple") or buildings.has(&"sacred_grove") or buildings.has(&"necropolis"):
		return "святыня"
	if buildings.has(&"lumber_mill") or buildings.has(&"quarry"):
		return "ремесленный"
	return "сельский"
