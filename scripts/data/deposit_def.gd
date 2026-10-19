class_name DepositDef
extends Resource
## Месторождение (data/deposits/*.tres): даёт клетке прибавку к добыче ресурса.

@export var id: StringName
@export var display_name: String = ""
@export var color: Color = Color.WHITE
## id ресурса из Goods.IDS (wood, stone, metal, gold).
@export var goods: StringName = &"metal"
## Сколько ресурса в год добавляет клетке.
@export var amount: float = 2.0
## Базовый шанс появления на клетке подходящего биома.
@export_range(0.0, 0.2) var chance: float = 0.01
## Вес по биомам (id биома → множитель шанса). Нет в списке — не встречается.
@export var biome_weights: Dictionary[StringName, float] = {}
