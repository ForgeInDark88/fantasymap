class_name Society
extends RefCounted
## Тайное общество или культ (SocietySystem): своё влияние в регионах, своя
## цель. Культ несёт свою веру и, захватив власть, обращает державу; братство
## тайно грабит казну; заговор стремится посадить на трон своего вожака.
## id = индекс в World.societies.

var id := -1
var name := ""
## cult — культ, brotherhood — тайное братство, conspiracy — заговор.
var kind: StringName = &"conspiracy"
## Вера культа (-1 — без веры).
var religion := -1
## Государство, где общество возникло, и вожак.
var home := -1
var leader := ""
var founded_year := 0
## Влияние: id региона → 0..1.
var influence: Dictionary[int, float] = {}
## Государство, где общество захватило власть (-1 — нет).
var seized := -1
var alive := true


func kind_name() -> String:
	match kind:
		&"cult":
			return "культ"
		&"brotherhood":
			return "тайное братство"
	return "заговор"


func total_influence() -> float:
	var t := 0.0
	for r in influence:
		t += influence[r]
	return t
