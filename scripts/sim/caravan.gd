class_name Caravan
extends RefCounted
## Караван (CaravanSystem): везёт товар по дороге или морскому пути из
## дешёвого рынка в дорогой. Товар списан с рынка отправителя при выходе и
## придёт на рынок получателя по прибытии; разбойники и пираты могут его отнять.

var id := -1
var road := -1
var from_city := -1
var to_city := -1
var from_nation := -1
var to_nation := -1
## Индекс товара (MarketDB) и количество; цена у отправителя (для пошлины и летописи).
var good := 0
var amount := 0.0
var price := 0.0
## Месяцев в пути всего и пройдено.
var months := 1
var done := 0
var alive := true
var robbed := false
## Охрана: id героя игрока (-1 — без охраны); охраняемый караван грабят реже.
var escort := -1
## «Свой» день месяца для хода.
var day := 0


## Доля пройденного пути (для показа).
func progress() -> float:
	return clampf(float(done) / float(maxi(1, months)), 0.0, 1.0)
