class_name GodDef
extends Resource
## Божество пантеона (data/gods/*.tres): сфера, натура, связь с верами (по id
## стартовых религий) и расами. Боги отвечают на молитвы, избирают героев,
## карают за грехи и влияют на Судьбу (GodSystem, Fate).

@export var id: StringName
@export var display_name: String = ""
## Имя в родительном падеже («Избранник Кровавого Вепря», «Слеза Аэлона»).
@export var genitive: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
## war, harvest, death, sea, wisdom, fire, trickery, nature, home, stone, abyss.
@export var sphere: StringName = &"war"
## Натура бога (−1 тёмный … +1 светлый): кого он избирает и за что карает.
@export_range(-1.0, 1.0) var karma: float = 0.0
## Веры, чьи последователи молятся этому богу (id ReligionDef; пусто — всем).
@export var religions: Array[StringName] = []
@export var color: Color = Color.WHITE
@export var symbol: String = "✦"
## Чем бог одаривает державу верных: эффекты на годы (ключи Nation.effects).
@export var boon: Dictionary[StringName, float] = {}
@export var boon_text: String = ""
## Оружие проклятия, если Судьба заточит душу его избранника.
@export var curse_weapon: String = ""


func name_genitive() -> String:
	return genitive if not genitive.is_empty() else display_name
