class_name HeroOrder
extends RefCounted
## Орден или гильдия героев (OrderSystem): рыцарский орден, гильдия магов,
## братство теней, гильдия охотников, круг жрецов. Основывает прославленный
## герой; члены не бьются друг с другом, растут быстрее, а держава, где стоит
## их обитель, получает пользу. Орден угасает, когда в нём не остаётся живых.
## id = индекс в World.orders.

var id := -1
var name := ""
## &"knights", &"mages", &"shadows", &"hunters", &"priests".
var kind: StringName = &"knights"
var founder := -1
var leader := -1
var founded_year := 0
var ended_year := -1
## Натура ордена (средняя карма основателя): кого принимают.
var karma := 0.0
## Обитель: клетка (обычно город основателя).
var hall_cell := -1
var members := PackedInt32Array()
var alive := true
## Сколько всего героев прошло через орден.
var total := 0


func kind_name() -> String:
	return OrderSystem.KIND_NAMES.get(kind, "орден")
