class_name BattleRecord
extends RefCounted
## Запись столкновения (этап 12.E): битва армий, поединок героев или встреча.
## Хранит то, что нужно для просмотра: где и когда, кто с кем, силы и потери,
## исход. replay_seed — зерно пересказа (BattleReplay): один и тот же бой всегда
## рассказывается одинаково, а просмотр не трогает ГСЧ мира.

var id := -1
## &"battle", &"duel", &"meeting".
var kind: StringName = &"battle"
var year := 0
var month := 0
var day := 0
var cell := -1
var region := -1
## Стороны: {nation, name, power, losses, general, hero} (hero — id героя или -1).
var sides: Array[Dictionary] = []
## Индекс победившей стороны (-1 — ничья, у встречи — нет).
var winner := -1
## Битва: павших всего; поединок: погиб ли побеждённый; встреча: итог (&"friend", &"rival", &"talk").
var fallen := 0.0
var killed := false
var outcome: StringName = &""
## Рельеф поля (BiomeDef.id) и река рядом — для описания.
var terrain: StringName = &""
var river := false
var replay_seed := 0


func to_array() -> Array:
	return [id, str(kind), year, month, day, cell, region, sides, winner, fallen, killed, str(outcome), str(terrain), river, replay_seed]


static func from_array(a: Array) -> BattleRecord:
	var r := BattleRecord.new()
	r.id = int(a[0])
	r.kind = StringName(a[1])
	r.year = int(a[2])
	r.month = int(a[3])
	r.day = int(a[4])
	r.cell = int(a[5])
	r.region = int(a[6])
	for s in a[7]:
		var d: Dictionary = s
		r.sides.append({"nation": int(d.nation), "name": str(d.name), "power": float(d.power), "losses": float(d.losses),
			"general": str(d.get("general", "")), "hero": int(d.get("hero", -1))})
	r.winner = int(a[8])
	r.fallen = float(a[9])
	r.killed = bool(a[10])
	r.outcome = StringName(a[11])
	r.terrain = StringName(a[12])
	r.river = bool(a[13])
	r.replay_seed = int(a[14])
	return r
