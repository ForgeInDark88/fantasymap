class_name HeroEventDef
extends Resource
## Событие в пути героя игрока (data/hero_events/*.tres): описание и 2–4
## варианта выбора. Ключи варианта (все необязательны, кроме text):
##   text — надпись, karma/xp — сдвиг кармы и опыт, rep — репутация у
##   владельца края, faith — у веры края; power — испытание силой (доля силы
##   героя 5-го уровня его класса): успех даёт result, item (вид артефакта) и
##   награды, провал — fail и рана risk (×3; раны ≥ 1 — гибель); без power —
##   всегда успех. gold — золото (отрицательное — плата: без денег вариант
##   скрыт), heal/wound — лечение и рана, quest — дать задание (ruins,
##   artifact, lair, treasure, embassy, raid, epidemic), cargo/amount — товар в
##   мешок, capture — плен у державы края (текст), next/delay — продолжение
##   цепочки (id события через delay месяцев), swear — присяга державе края.

@export var id: StringName
@export var title: String = ""
## {where} — край, {owner} — держава края.
@export_multiline var text: String = ""
## Где случается: &"" — везде, &"nation" — на землях государства, &"wild" — в глуши.
@export var where: StringName = &""
## Местность: &"" — любая, &"forest", &"mountains", &"coast", &"desert", &"swamp", &"cold", &"city" (край с городом).
@export var terrain: StringName = &""
@export var weight: float = 1.0
## Продолжение цепочки: случается только по ключу next варианта другого события.
@export var chained: bool = false
## Условие (этап 11.H): &"outbreak", &"war", &"foreign" (чужой язык), &"slavery",
## &"lair", &"caravan", &"rumor" — или пусто.
@export var requires: StringName = &""
@export var options: Array[Dictionary] = []
