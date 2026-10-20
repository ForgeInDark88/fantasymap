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
const RELIGION := 8
const CULTURE := 9
const TRADE := 10
const UNDERGROUND := 11

const NAMES: Array[String] = ["Политика", "Расы", "Население", "Ресурсы", "Биомы", "Высоты", "Темп.", "Влажн.",
	"Религии", "Культура", "Торговля", "Подземелья"]
## Клавиши режимов по порядку: 1–9, 0, −, =.
const HOTKEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]


## Какой «базовый» рисунок нужен режиму (политика и расы рисуются поверх биомов).
static func base_mode(mode: int) -> int:
	return BIOMES if mode == POLITICAL or mode == RACES or is_region_mode(mode) or mode == TRADE or mode == UNDERGROUND else mode


## Режимы с заливкой по регионам (цвет региона — из палитры регионов).
static func is_region_mode(mode: int) -> bool:
	return mode == RELIGION or mode == CULTURE


## Подпись клавиши режима для подсказки.
static func hotkey_label(mode: int) -> String:
	return OS.get_keycode_string(HOTKEYS[mode]) if mode < HOTKEYS.size() else ""


## Режимы, чей рисунок зависит от хода симуляции (перерисовываются на лету).
static func is_dynamic(mode: int) -> bool:
	return mode == POPULATION
