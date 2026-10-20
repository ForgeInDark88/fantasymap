class_name Cave
extends RefCounted
## Узел подземного мира (UndergroundSystem): пещера, жила, логово чудовищ или
## древние руины на глубине 1–3 под клеткой поверхности. Входы (глубина 1)
## открываются в горах и холмах. id = индекс в World.caves.

const KIND_NAMES := {&"cavern": "пещеры", &"mithril": "мифриловая жила", &"gems": "самоцветная жила",
	&"lair": "логово чудовищ", &"ruins": "древние руины"}

var id := -1
var name := ""
var kind: StringName = &"cavern"
## Клетка поверхности над узлом и глубина (1 — у поверхности, 3 — бездна).
var cell := -1
var depth := 1
## Вход с поверхности.
var entrance := false
var neighbors := PackedInt32Array()
## Хозяин (-1 — дикие глубины) и сила обитающих там чудовищ.
var owner := -1
var monsters := 0.0
## Построен подземный город; руины исследованы.
var city := false
var explored := false


func kind_name() -> String:
	return KIND_NAMES.get(kind, "пещеры")
