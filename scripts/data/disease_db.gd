class_name DiseaseDB
## Реестр data/diseases/*.tres (DiseaseDef).

const DIR := "res://data/diseases/"

static var _reg: Registry


static func ensure_loaded() -> void:
	if _reg == null:
		_reg = Registry.new(DIR, DiseaseDef)


static func all() -> Array[Resource]:
	ensure_loaded()
	return _reg.items


static func find(id: StringName) -> DiseaseDef:
	ensure_loaded()
	return _reg.find(id)
