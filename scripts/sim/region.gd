class_name Region
extends RefCounted
## Регион (провинция): постоянная географическая область, нарезанная при
## создании мира с учётом рельефа (горы и реки становятся естественными
## границами). Владеют клетками по-прежнему государства, а регион — единица
## управления: у него есть имя, народ, лояльность к владельцу и недовольство;
## войны завоёвывают регионы, восстания и распады откалывают регионы.

var id := -1
## Имя появляется, когда регион впервые кто-то занимает (на языке его расы).
var name := ""
var cells := PackedInt32Array()
## Клетка у центра масс региона (точка для подписи).
var center := -1
## Соседние регионы (по суше).
var neighbors := PackedInt32Array()
var coastal := false
## Сколько клеток региона у каждого государства: id → число клеток (учёт World).
var owner_counts: Dictionary[int, int] = {}

## Лояльность текущему владельцу (0..1) и накопленное недовольство (≥ 1 — бунт).
var loyalty := 1.0
var unrest := 0.0
## Год последней смены владельца (завоевания) — недавно завоёванные бунтуют чаще.
var conquered_year := -1000
## До этого года регион не бунтует (после подавленного мятежа).
var pacified_until := -1000
## Претензии: государство, потерявшее регион, → год, до которого оно помнит о нём.
var claims: Dictionary[int, int] = {}
## Вера жителей: id религии → доля (сумма ≈ 1; пусто — регион не заселён).
var faith: Dictionary[int, float] = {}


## Самая распространённая вера (-1 — нет).
func main_faith() -> int:
	var best := -1
	var best_share := 0.0
	for r in faith:
		if faith[r] > best_share:
			best_share = faith[r]
			best = r
	return best


## Государство, которому принадлежит большая часть клеток региона (-1 — ничей).
func controller() -> int:
	var best := -1
	var best_count := 0
	for id_ in owner_counts:
		if owner_counts[id_] > best_count:
			best_count = owner_counts[id_]
			best = id_
	return best


func area() -> int:
	return cells.size()
