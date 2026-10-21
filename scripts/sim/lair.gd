class_name Lair
extends RefCounted
## Логово чудовищ (LairSystem): в диком крае, набегает на соседей; великое
## чудовище бродит по краям вокруг логова (region — где оно сейчас).

var id := -1
var def: LairDef
## Имя великого чудовища («Скарвакс Пепельный»), у прочих — пусто.
var name := ""
## Логово (клетка и край) и край, где чудовище сейчас.
var cell := -1
var home := -1
var region := -1
var strength := 0.0
var alive := true
var born := 0
var day := 0
var raids := 0
## Кто разорил (для летописи и хроник): «герой N» / «государство N».
var slain_by := ""


func label() -> String:
	if def.great and not name.is_empty():
		return "%s (%s)" % [name, def.monster]
	return def.display_name
