class_name Artifact
extends RefCounted
## Предмет-артефакт (ArtifactSystem): у него свой вид (ArtifactDef), имя и
## история владения. В каждый момент он у героя, в сокровищнице государства
## или лежит потерянным в какой-то клетке (в руинах, на поле боя).
## id = индекс в World.artifacts.

var id := -1
var def: ArtifactDef
var name := ""
## Владелец: герой, сокровищница государства или клетка, где предмет потерян.
var hero := -1
var nation := -1
var cell := -1
var created_year := 0
## «123 г.: выкован героем …», «140 г.: взят в бою …».
var history := PackedStringArray()


func power_mult() -> float:
	return def.power_mult if def != null else 1.2


func is_lost() -> bool:
	return hero < 0 and nation < 0
