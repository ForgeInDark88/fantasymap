class_name City
extends RefCounted
## Город. Принадлежит государству, но население может быть другой расы
## (например, после завоевания) — это понадобится для многорасовых государств.

var id := -1
var name := ""
var cell := -1
var nation_id := -1
var race_id: StringName
var population := 0.0
var founded_year := 0
var is_capital := false
var alive := true
## Привлекательность места (реки, побережье, родной биом) — доля горожан.
var weight := 1.0
var coastal := false
## Биомы в радиусе 2 клеток (битовая маска индексов) — для условий построек.
var near_biomes := 0
## id построек (BuildingDef.id).
var buildings: Array[StringName] = []
