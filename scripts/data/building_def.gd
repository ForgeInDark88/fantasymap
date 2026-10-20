class_name BuildingDef
extends Resource
## Постройка в городе (data/buildings/*.tres). Каждая строится в городе не более
## одного раза; эффекты всех построек суммируются на уровне государства.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Записывать постройку в летопись (рядовые фермы и лесопилки — нет).
@export var notable: bool = false
## Строится ли обычным порядком (чудеса света появляются только благодаря героям).
@export var buildable: bool = true

@export_group("Условия")
## Стоимость: id ресурса (gold, wood, stone, metal) → количество.
@export var cost: Dictionary[StringName, float] = {}
## Минимальное население города.
@export var min_population: float = 0.0
## Нужен выход к морю.
@export var requires_coast: bool = false
## Рядом с городом (радиус 2) должен быть хотя бы один из этих биомов.
@export var requires_biomes: Array[StringName] = []
## Только для этих рас (пусто — для всех).
@export var allowed_races: Array[StringName] = []
## Нужна хотя бы одна из этих особенностей расы (пусто — не нужна).
@export var required_traits: Array[StringName] = []
## Нужна технология (data/techs; пусто — не нужна).
@export var requires_tech: StringName = &""
## Не строится, если в городе уже есть одна из этих построек (например, стены и крепость).
@export var excludes: Array[StringName] = []

## Маска индексов requires_biomes (строится EconomyDB при загрузке).
var required_biome_mask := 0

@export_group("Эффекты")
## Прибавка к ёмкости земли (доля): 0.08 = +8% к пропитанию.
@export var food_bonus: float = 0.0
## Добыча в год: id ресурса → количество.
@export var production: Dictionary[StringName, float] = {}
## Прибавка к стабильности государства.
@export var stability: float = 0.0
## Прибавка к размеру армии (доля).
@export var army_bonus: float = 0.0
## Оборона города при осадах (этап 4).
@export var defense: float = 0.0
## Ускорение науки (доля).
@export var science_bonus: float = 0.0
