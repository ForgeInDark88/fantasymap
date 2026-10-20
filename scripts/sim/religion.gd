class_name Religion
extends RefCounted
## Вера в мире. Стартовые веры создаются из ReligionDef, ереси и новые
## религии — в ходе истории (ReligionSystem): ответвление наследует символ,
## иконку и характер родителя, но с изменёнными догматами. id = индекс в
## World.religions, не переиспользуется (угасшие веры остаются для летописи).

var id := -1
var name := ""
var symbol := "✦"
var color := Color.WHITE
## Стартовое описание, от которого пошла вера (у ересей — описание прародителя).
var def: ReligionDef
## Вера-прародитель (-1 — изначальная) и корень семейства вер.
var parent := -1
var root := -1
var founded_year := 0
## Государство, где вера возникла (для ересей и новых вер).
var origin_nation := -1
var dogmas := PackedStringArray()
var effects: Dictionary[StringName, float] = {}
var missionary := 0.4
var tolerance := 0.5
var zeal := 0.4
var magic := 0.0
var undead := -0.5
var demons := -1.0
## Ещё есть последователи (пересчитывает ReligionSystem раз в несколько лет).
var alive := true


static func from_def(d: ReligionDef, new_id: int) -> Religion:
	var r := Religion.new()
	r.id = new_id
	r.root = new_id
	r.def = d
	r.name = d.display_name
	r.symbol = d.symbol
	r.color = d.color
	r.dogmas = d.dogmas.duplicate()
	r.effects = d.effects.duplicate()
	r.missionary = d.missionary
	r.tolerance = d.tolerance
	r.zeal = d.zeal
	r.magic = d.magic
	r.undead = d.undead
	r.demons = d.demons
	return r


func icon() -> Texture2D:
	return def.icon if def != null else null


func is_heresy() -> bool:
	return parent >= 0


## Насколько вера враждебна к другой (0 — мир, 1 — священная война):
## своя ветвь мягче, нетерпимые — жёстче; нежить и демонов судят по догмам.
func hostility(other: Religion) -> float:
	if other == null or other.id == id:
		return 0.0
	var h := 1.0 - tolerance
	if other.root == root:
		h *= 0.6  # раскольники — «свои заблудшие», хотя бывает и наоборот
	if other.def != null and other.def.id == &"eternal_night":
		h = maxf(h, -undead)
	if other.def != null and other.def.id == &"abyss":
		h = maxf(h, -demons)
	return clampf(h, 0.0, 1.0)


## Склонность расы к этой вере (по прародителю).
func race_affinity(race: RaceDef) -> float:
	return def.races.get(race.id, 0.0) if def != null else 0.0
