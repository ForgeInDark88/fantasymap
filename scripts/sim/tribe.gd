class_name Tribe
extends RefCounted
## Племя или орда в ничейных землях (TribeSystem). id — порядковый номер
## (не меняется: мёртвые остаются в списке до уплотнения раз в год).

var id := -1
var def: TribeDef
var name := ""
var race: RaceDef
## Край, где стоит племя, и клетка для значка.
var region := -1
var cell := -1
## Воины.
var strength := 0.0
## Кочевники, собравшиеся в орду.
var horde := false
## Год, когда кочевники собрались в орду (и распалась — орда снова не раньше чем через HORDE_YEARS).
var horde_year := -1000
var alive := true
var born := 0
## «Свой» день месяца (ход раз в месяц; не зависит от id — тот же после загрузки).
var day := 0
var raids := 0
## Государство, на которое орда идёт войной (-1 — нет).
var target := -1


func label() -> String:
	return (def.horde_name if horde else def.tribe_name).replace("{name}", name)
