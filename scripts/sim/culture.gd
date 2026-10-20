class_name Culture
extends RefCounted
## Культура (народ с его наречием и обычаями). Возникает вместе с новым
## государством; отколовшиеся земли сохраняют культуру прежней державы,
## поэтому наследники общей империи — люди одной культуры. Регионы под чужой
## властью со временем ассимилируются (CultureSystem). id = индекс в World.cultures.

var id := -1
var name := ""
## Народ-носитель (RaceDef.index).
var race := -1
var color := Color.WHITE
var customs := PackedStringArray()
var origin_nation := -1
var founded_year := 0
