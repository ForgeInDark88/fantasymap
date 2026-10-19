class_name GovernmentDef
extends Resource
## Форма правления (data/governments/*.tres): как сменяется власть и как она
## влияет на государство. Форма задаётся в RaceDef.state_forms третьим полем.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Как сменяется правитель:
##   heir — наследник из той же династии (возможен кризис престолонаследия);
##   election — выборы каждые election_period лет;
##   strongest — после смерти вождя власть берёт сильнейший (частые смуты);
##   eternal — бессмертный правитель, пока его не уничтожат.
@export_enum("heir", "election", "strongest", "eternal") var succession: String = "heir"
@export var election_period: int = 6
## Базовый шанс смуты при смене правителя (растёт при низкой стабильности).
@export_range(0.0, 1.0) var crisis_chance: float = 0.05
@export var stability_bonus: float = 0.0
@export var aggression_mult: float = 1.0
@export var trade_mult: float = 1.0
@export var science_mult: float = 1.0
@export var army_mult: float = 1.0
## Допускает династические браки.
@export var dynastic: bool = false
