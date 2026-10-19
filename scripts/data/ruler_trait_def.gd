class_name RulerTraitDef
extends Resource
## Черта характера правителя (data/ruler_traits/*.tres). Каждому новому
## правителю случайно выпадает одна черта — она меняет решения государства.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Относительная частота выпадения.
@export var weight: float = 1.0
@export var aggression_mult: float = 1.0
@export var stability: float = 0.0
@export var science_mult: float = 1.0
@export var trade_mult: float = 1.0
@export var army_mult: float = 1.0
## Множитель шанса строить постройки.
@export var build_mult: float = 1.0
## Прибавка к мнению соседей о государстве.
@export var charisma: float = 0.0
