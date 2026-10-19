class_name HeroClassDef
extends Resource
## Класс героя (data/hero_classes/*.tres).

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Сила героя в бою — сколько воинов он стоит на 1-м уровне.
@export var power: float = 300.0
## Насколько класс подходит расе: id расы → вес. Расы не из списка — вес default_weight.
@export var race_weights: Dictionary[StringName, float] = {}
@export var default_weight: float = 0.3
## Склонность к службе государству (0 — вечный странник, 1 — охотно присягает).
@export_range(0.0, 1.0) var loyalty: float = 0.5
## Склонность к поединкам с другими героями.
@export_range(0.0, 1.0) var aggression: float = 0.5
## Склонность к добру (+1) или злу (-1); у каждого героя ещё свой разброс.
@export_range(-1.0, 1.0) var karma: float = 0.0
## Ум класса (0 — безрассуден, 1 — мудр): насколько трезво герой оценивает
## противника. Глупцы недооценивают врага и идут на верную смерть.
@export_range(0.0, 1.0) var intellect: float = 0.5
## Оружие класса — для имён артефактов («Меч …», «Посох …»).
@export var weapon: String = "Клинок"
## Цвет значка на карте.
@export var color: Color = Color.GOLD
