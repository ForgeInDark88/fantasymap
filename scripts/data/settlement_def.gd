class_name SettlementDef
extends Resource
## Вид поселения (data/settlement/*.tres, этап 12.C): деревня поселенцев, колония
## за морем, пограничный форт, гарнизон-аванпост в завоёванном крае. Поселение —
## источник влияния: земля державы растёт от своих городов и поселений (ближние
## клетки — раньше), пока «дотягивается» влияние (reach), — цельными пятнами.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Дальность влияния сверх базовой (InfluenceSystem.REACH), в базовых клетках пути.
@export var reach: float = 2.0
## Цена: жители (уходят из города-отправителя), золото, дерево, камень.
@export var cost_pop: float = 200.0
@export var cost_gold: float = 30.0
@export var cost_wood: float = 20.0
@export var cost_stone: float = 0.0
## Прибавка к обороне края (осады, WarSystem._city_defense).
@export var defense: float = 0.0
## Через сколько лет деревня может стать городом (CitySystem; 0 — никогда).
@export var town_after: int = 0
@export var color: Color = Color(0.85, 0.75, 0.5)
