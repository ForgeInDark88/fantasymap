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
