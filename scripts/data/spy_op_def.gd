class_name SpyOpDef
extends Resource
## Тайная операция разведки (data/spy_ops/*.tres). Последствия реализует
## SpySystem по полю kind; здесь — цена, шансы и последствия разоблачения.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## sabotage — диверсия (постройка или склад), incite — подстрекательство мятежа,
## steal_tech — кража технологии, assassinate — убийство правителя,
## bribe_vassal — подкуп вассала, disinformation — рассорить двух соседей.
@export_enum("sabotage", "incite", "steal_tech", "assassinate", "bribe_vassal", "disinformation") var kind: String = "sabotage"
## Цена в очках разведки.
@export var cost: float = 10.0
## Базовый шанс успеха (дальше — соотношение разведок и шпионы-герои).
@export_range(0.0, 1.0) var success: float = 0.6
## Шанс разоблачения (при неудаче — выше вдвое).
@export_range(0.0, 1.0) var exposure: float = 0.2
## Обида жертвы при разоблачении и шанс, что она объявит войну.
@export_range(0.0, 1.0) var scandal_grudge: float = 0.15
@export_range(0.0, 1.0) var scandal_war: float = 0.0
## Относительная частота выбора.
@export var weight: float = 1.0
