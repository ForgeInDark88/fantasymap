class_name BiomeDef
extends Resource
## Описание одного биома. Экземпляры лежат в data/biomes/*.tres.
##
## Генератор решает, КАКОЙ биом у клетки (по индексу из Biome), а всё,
## что касается свойств биома (цвет, плодородие, проходимость), берётся
## отсюда — это можно править в редакторе без изменения кода.

## Строковый идентификатор (используется в данных рас: «предпочитаемые биомы»).
@export var id: StringName
## Индекс биома — должен совпадать с константой в классе Biome.
@export var index: int = 0
@export var display_name: String = ""
@export var color: Color = Color.MAGENTA
@export var is_water: bool = false
## Базовая еда с клетки (0..1).
@export_range(0.0, 1.0) var fertility: float = 0.5
## Стоимость передвижения и экспансии (1 = равнина).
@export_range(0.5, 10.0) var move_cost: float = 1.0
## Насколько клетка пригодна для поселений (0 = непригодна).
@export_range(0.0, 1.0) var habitability: float = 0.5
