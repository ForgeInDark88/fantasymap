class_name Settlement
extends RefCounted
## Поселение (этап 12.C): деревня, колония, форт или аванпост державы в клетке —
## источник влияния (InfluenceSystem). Город — тоже источник, но живёт в
## World.cities; деревня со временем может стать городом (CitySystem).

var id := -1
var def: SettlementDef
var kind: StringName = &"village"
var name := ""
var cell := -1
var nation := -1
var founded := 0
var alive := true
