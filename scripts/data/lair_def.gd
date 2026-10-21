class_name LairDef
extends Resource
## Логово чудовищ (data/lairs/*.tres): гнездо в диких землях, откуда чудовища
## набегают на соседние края. Великие чудовища (дракон, кракен…) — одиночки:
## бродят шире, бьют сильнее, за их голову герои получают славу (LairSystem).

@export var id: StringName
@export var display_name: String = ""
## Кто живёт в логове (для летописи): «тролли», «дракон».
@export var monster: String = ""
@export_multiline var description: String = ""
## Биомы (BiomeDef.id), где появляется логово.
@export var biomes: Array[StringName] = []
@export var weight: float = 1.0
@export var min_year: int = 0
## Великое чудовище: одно на логово, бродит до great_range краёв, на мир — не больше нескольких.
@export var great: bool = false
@export var great_range: int = 3
## Сила (воинов против армий и героев), шанс набега в месяц, урон набега (доля населения края и золото).
@export var strength: Vector2 = Vector2(1500.0, 4000.0)
@export var raid_chance: float = 0.08
@export var raid_pop: float = 0.01
@export var raid_gold: float = 40.0
## Добыча за разорённое логово (золото) и рост силы в год.
@export var loot: float = 150.0
@export var growth: float = 0.03
@export var color: Color = Color(0.85, 0.3, 0.2)
