class_name Ruin
extends RefCounted
## Руины (RuinSystem): развалины павшего города или столицы, гробница героя,
## храм забытых богов. Хранят богатство (золото, знания, оружие) и опасность
## (чудовища, проклятия); их исследуют герои и государства, а со временем на
## руинах может возродиться город или культ. id = индекс в World.ruins.

const KIND_NAMES := {&"city": "развалины города", &"capital": "развалины столицы", &"tomb": "гробница героя",
	&"temple": "храм забытых богов"}

var id := -1
var name := ""
var kind: StringName = &"city"
var cell := -1
## Откуда руины (для летописи и карточки).
var origin := ""
var created_year := 0
## Сколько ещё можно найти (иссякает при раскопках) и сила стражей.
var wealth := 0.0
var danger := 0.0
var cursed := false
## Герой, похороненный в гробнице (-1 — нет).
var hero_id := -1
## На руинах вырос новый город.
var revived := false


func kind_name() -> String:
	return KIND_NAMES.get(kind, "руины")


func depleted() -> bool:
	return wealth < 15.0
