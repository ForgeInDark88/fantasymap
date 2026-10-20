class_name ReligionDB
## Реестр стартовых религий (data/religions/*.tres).

const DIR := "res://data/religions/"

static var _reg: Registry


static func ensure_loaded() -> void:
	if _reg == null:
		_reg = Registry.new(DIR, ReligionDef)


static func all() -> Array[Resource]:
	ensure_loaded()
	return _reg.items


static func find(id: StringName) -> ReligionDef:
	ensure_loaded()
	return _reg.find(id)
