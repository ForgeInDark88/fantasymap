class_name War
extends RefCounted
## Война между двумя коалициями. Стороны: 1 — нападающие, -1 — защищающиеся.

var id := -1
var name := ""
## Повод: territory, resources, racial, revenge, independence, civil, expansion.
var cause: StringName
var start_year := 0
var end_year := -1
var attackers := PackedInt32Array()
var defenders := PackedInt32Array()
## Счёт войны: > 0 — побеждают нападающие; ±100 — решительная победа.
var score := 0.0
## Осаждаемый регион, кто осаждает (1/-1) и прогресс осады (1 — регион пал).
var siege_region := -1
var siege_side := 0
var siege_progress := 0.0
## Осада ведётся десантом с моря (у сторон нет общей сухопутной границы).
var siege_landing := false
## Месяц и день, в которые идут сражения (раз в год).
var month := 0
var day := 0
var battles := 0
var casualties := 0.0
var active := true


func side_of(nation_id: int) -> int:
	if attackers.has(nation_id):
		return 1
	if defenders.has(nation_id):
		return -1
	return 0


func members(side: int) -> PackedInt32Array:
	return attackers if side > 0 else defenders


func leader(side: int) -> int:
	var m := members(side)
	return m[0] if not m.is_empty() else -1


func remove_member(nation_id: int) -> void:
	var i := attackers.find(nation_id)
	if i >= 0:
		attackers.remove_at(i)
	i = defenders.find(nation_id)
	if i >= 0:
		defenders.remove_at(i)
