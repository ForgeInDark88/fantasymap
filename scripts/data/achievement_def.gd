class_name AchievementDef
extends Resource
## Достижение (data/achievements/*.tres). Только отметки об увиденном — без
## целей и условий победы. Условие (cond) и его параметры:
##   count        — счётчик мира key (World.count) достиг target;
##   event        — запись летописи вида kind, в тексте которой есть contains;
##   peace_years  — target лет подряд без единой войны (проверка раз в год);
##   nation_share — одна держава владеет долей share всей занятой суши;
##   race_share   — государства расы race владеют долей share занятой суши;
##   hero_level   — герой достиг уровня target;
##   religion_races — одна вера — вера большинства у target рас;
##   nations_total  — в истории мира target государств;
##   year         — мир дожил до target года;
##   ui           — событие интерфейса key (экспорт хроники и т. п.).

@export var id: StringName
@export var title: String = ""
@export_multiline var description: String = ""
@export var hidden: bool = false
@export var cond: StringName = &"count"
@export var key: StringName = &""
@export var kind: StringName = &""
@export var contains: String = ""
@export var race: StringName = &""
@export var target: float = 1.0
@export var share: float = 0.25
