class_name Outbreak
extends RefCounted
## Поветрие (DiseaseSystem): болезнь в нескольких краях; в каждом — сколько
## месяцев ей там ещё держаться. Кончается, когда больных краёв не осталось.

var id := -1
var def: DiseaseDef
## Край → месяцев болезни впереди.
var regions: Dictionary[int, int] = {}
var origin := -1
var born := 0
var day := 0
var deaths := 0.0
var peak := 0
var alive := true
## Государства, где поветрие уже было (летопись — раз на державу).
var nations: Dictionary[int, bool] = {}
