class_name QuestDB
## Реестр видов заданий героя data/quests/*.tres (QuestDef).

const DIR := "res://data/quests/"

static var _reg: Registry


static func ensure_loaded() -> void:
	if _reg == null:
		_reg = Registry.new(DIR, QuestDef)


static func all() -> Array[Resource]:
	ensure_loaded()
	return _reg.items


static func find(id: StringName) -> QuestDef:
	ensure_loaded()
	return _reg.find(id)
