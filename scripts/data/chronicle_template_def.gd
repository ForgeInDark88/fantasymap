class_name ChronicleTemplateDef
extends Resource
## Шаблон летописца (data/chronicle_templates/*.tres) для связных историй
## панели «Хроники». parts — части текста по ключам (intro, intro_dark,
## intro_<раса>, victory, outro…), из вариантов выбирается один. В тексте:
## {имя} — подстановка сущности (nation, hero, war, era, year…), [слово] —
## синоним из words этого шаблона или общего шаблона &"common".

@export var id: StringName
## era, war, hero, nation, religion, org, common.
@export var topic: StringName = &""
@export var titles: PackedStringArray = []
@export var parts: Dictionary[String, PackedStringArray] = {}
@export var words: Dictionary[String, PackedStringArray] = {}
