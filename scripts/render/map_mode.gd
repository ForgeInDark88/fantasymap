class_name MapMode
## Режимы отображения карты.

const POLITICAL := 0
const RACES := 1
const POPULATION := 2
const RESOURCES := 3
const BIOMES := 4
const HEIGHT := 5
const TEMPERATURE := 6
const MOISTURE := 7

const NAMES: Array[String] = ["Политика", "Расы", "Население", "Ресурсы", "Биомы", "Высоты", "Темп.", "Влажн."]


## Какой «базовый» рисунок нужен режиму (политика и расы рисуются поверх биомов).
static func base_mode(mode: int) -> int:
	return BIOMES if mode == POLITICAL or mode == RACES else mode


## Режимы, чей рисунок зависит от хода симуляции (перерисовываются на лету).
static func is_dynamic(mode: int) -> bool:
	return mode == POPULATION
