class_name TechDef
extends Resource
## Технология (data/techs/*.tres). Государство копит очки исследований
## (прирост его науки, учёные-герои) и открывает технологии по очереди,
## выбирая направление по характеру правителя и форме правления. Эффекты —
## те же ключи, что у вер и форм правления (см. Nation.effects).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Ветка: military, economy, society, magic, navy.
@export_enum("military", "economy", "society", "magic", "navy") var branch: String = "economy"
## Стоимость в очках исследований (≈ прирост науки за несколько десятков лет).
@export var cost: float = 0.5
## Нужные заранее технологии.
@export var requires: Array[StringName] = []
## Эффекты для открывшего государства: *_mult — множители (science, army,
## trade, growth, aggression, production, siege, naval, expansion, culture, spy),
## stability, food (доля ёмкости земли), defense (оборона регионов) — прибавки.
@export var effects: Dictionary[StringName, float] = {}
## Склонность рас: id расы → множитель вероятности выбрать и открыть
## (0 — расе технология недоступна вовсе). Расы не из списка — 1.
@export var race_weights: Dictionary[StringName, float] = {}
## Записывать открытие в летопись.
@export var notable: bool = false

## Индекс в реестре (задаёт TechDB).
var index := -1


func race_weight(race: RaceDef) -> float:
	return race_weights.get(race.id, 1.0)
