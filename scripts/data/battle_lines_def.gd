class_name BattleLinesDef
extends Resource
## Реплики пересказа боя (data/battle_lines/*.tres, этап 12.E): фаза боя и её
## варианты. Подстановки: {a}, {b} — стороны; {w}, {l} — победитель и
## побеждённый; {place} — край; {terrain} — местность; {ga}, {gb} — полководцы
## или классы героев; {fallen} — павших.

@export var id: StringName
## &"battle", &"duel", &"meeting".
@export var kind: StringName = &"battle"
@export var lines: PackedStringArray = PackedStringArray()
