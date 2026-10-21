class_name TeleportDef
extends Resource
## Допустимый «телепорт» (data/teleports/*.tres, этап 12.B): мгновенное
## перемещение, которое не ходьба, — магия, портал, воля Судьбы или Бога,
## появление нового юнита. Всё остальное идёт по карте (MovementSystem).
## Каждый телепорт виден на карте (вспышка effect) и проверяется тестом.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## Вид вспышки на карте: &"flash", &"mist", &"spawn".
@export var effect: StringName = &"flash"
@export var color: Color = Color(0.8, 0.7, 1.0)
