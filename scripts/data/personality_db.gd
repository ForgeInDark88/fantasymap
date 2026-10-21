class_name PersonalityDB
## Реестр характеров государств data/personalities/*.tres (PersonalityDef).

const DIR := "res://data/personalities/"

static var _reg: Registry


static func ensure_loaded() -> void:
	if _reg == null:
		_reg = Registry.new(DIR, PersonalityDef)


static func all() -> Array[Resource]:
	ensure_loaded()
	return _reg.items


static func find(id: StringName) -> PersonalityDef:
	ensure_loaded()
	return _reg.find(id)
