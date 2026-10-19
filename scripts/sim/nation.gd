class_name Nation
extends RefCounted
## Государство. id совпадает с индексом в World.nations и никогда не переиспользуется
## (погибшие государства остаются с alive = false — для летописи и истории).

var id := -1
## Полное название («Королевство Альмар») и короткое — для подписи на карте.
var name := ""
var short_name := ""
var race_id: StringName
var race: RaceDef
var color := Color.WHITE

var ruler_name := ""
var ruler_title := ""

var capital_city := -1
var city_ids := PackedInt32Array()
var cell_count := 0

var population := 0.0
var army := 0.0
var wealth := 0.0
## 0..1 — при низкой стабильности государство распадается (этап 4).
var stability := 0.8

var founded_year := 0
var alive := true
## Клетка для подписи названия (самая «глубокая» точка территории).
var label_cell := -1


func ruler_display() -> String:
	return "%s %s" % [ruler_title, ruler_name]
