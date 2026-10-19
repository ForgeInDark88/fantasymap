class_name MapMode
## Режимы отображения карты. Население и ресурсы появятся на следующих этапах.

const POLITICAL := 0
const RACES := 1
const BIOMES := 2
const HEIGHT := 3
const TEMPERATURE := 4
const MOISTURE := 5

const NAMES: Array[String] = ["Политика", "Расы", "Биомы", "Высоты", "Температура", "Влажность"]


## Какой «базовый» рисунок нужен режиму (политика и расы рисуются поверх биомов).
static func base_mode(mode: int) -> int:
	return BIOMES if mode == POLITICAL or mode == RACES else mode
