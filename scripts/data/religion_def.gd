class_name ReligionDef
extends Resource
## Стартовая религия (data/religions/*.tres). В мире по ней создаётся объект
## Religion; ереси и новые веры рождаются уже в ходе истории — как ответвления
## с изменёнными догматами.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Символ для подписей и иконка.
@export var symbol: String = "✦"
@export var icon: Texture2D
@export var color: Color = Color.WHITE
## Склонность рас к этой вере: id расы → вес. Стартовые государства выбирают
## государственную религию по этим весам; обращение народа тоже идёт легче.
@export var races: Dictionary[StringName, float] = {}

@export_group("Догматы")
## Названия догматов (для карточки).
@export var dogmas: PackedStringArray = []
## Эффекты для государства с этой государственной религией — те же ключи, что
## у форм правления: science_mult, army_mult, trade_mult, growth_mult,
## aggression_mult; stability — прибавка к стабильности.
@export var effects: Dictionary[StringName, float] = {}

@export_group("Характер веры")
## Миссионерство (0..1): как быстро вера обращает соседей и подданных.
@export_range(0.0, 1.0) var missionary: float = 0.4
## Терпимость (0..1): мягче к иноверцам, меньше недовольства и священных войн.
@export_range(0.0, 1.0) var tolerance: float = 0.5
## Рвение (0..1): склонность к священным войнам и ересям.
@export_range(0.0, 1.0) var zeal: float = 0.4
## Отношение к магии, нежити и демонам (−1 — враждебна, +1 — почитает).
@export_range(-1.0, 1.0) var magic: float = 0.0
@export_range(-1.0, 1.0) var undead: float = -0.5
@export_range(-1.0, 1.0) var demons: float = -1.0
