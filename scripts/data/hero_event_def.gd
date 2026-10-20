class_name HeroEventDef
extends Resource
## Событие в пути героя игрока (data/hero_events/*.tres): описание и 2–4
## варианта выбора. Ключи варианта (все необязательны, кроме text):
##   text — надпись, karma/xp — сдвиг кармы и опыт, rep — репутация у
##   владельца края, faith — у веры края; power — испытание силой (доля силы
##   героя 5-го уровня его класса): успех даёт result, item (вид артефакта) и
##   награды, провал — fail и шанс гибели risk; без power — всегда успех.

@export var id: StringName
@export var title: String = ""
## {where} — край, {owner} — держава края.
@export_multiline var text: String = ""
## Где случается: &"" — везде, &"nation" — на землях государства, &"wild" — в глуши.
@export var where: StringName = &""
@export var weight: float = 1.0
@export var options: Array[Dictionary] = []
