class_name MercCompany
extends RefCounted
## Вольный отряд наёмников (MercSystem): ищет нанимателя среди воюющих, служит
## за плату, без платы бунтует — переходит к врагу или грабит край.

var id := -1
var name := ""
var race: RaceDef
## Воинов (сила в бою — Nation.merc_power нанимателя) и плата в год.
var strength := 0.0
var wage := 0.0
## Наниматель (-1 — вольный) и где стоит отряд; к нанимателю идёт по карте
## (этап 12.B, профиль «army»).
var employer := -1
var m := Mover.new(-1, &"army")
var cell: int:
	get:
		return m.cell
	set(v):
		m.cell = v
		m.prev_cell = v
var alive := true
var born := 0
## Сколько раз подряд не заплатили.
var unpaid := 0
var battles := 0
