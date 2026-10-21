class_name Settler
extends RefCounted
## Поселенцы в пути (этап 12.C): группа из тесного города идёт к выбранному месту
## (профиль «settler»; за море — из гавани на корабле) и, дойдя, основывает
## поселение. В пути их могут перехватить чудовища, кочевники, вражеское войско.

var id := -1
var nation := -1
var from_city := -1
## Куда идут, вид будущего поселения, сколько их и почему ушли (для летописи и карточки).
var target := -1
var kind: StringName = &"village"
var people := 200.0
var reason: StringName = &"crowded"
var m := Mover.new(-1, &"settler")
var cell: int:
	get:
		return m.cell
	set(v):
		m.cell = v
		m.prev_cell = v
var born := 0
var alive := true
