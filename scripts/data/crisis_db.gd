class_name CrisisDB
## Реестр мировых кризисов (data/crises/*.tres).

const DIR := "res://data/crises/"

static var _reg: Registry


static func ensure_loaded() -> void:
	if _reg == null:
		_reg = Registry.new(DIR, CrisisDef)


static func all() -> Array[Resource]:
	ensure_loaded()
	return _reg.items


static func find(id: StringName) -> CrisisDef:
	ensure_loaded()
	return _reg.find(id)
