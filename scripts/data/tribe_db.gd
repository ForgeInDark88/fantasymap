class_name TribeDB
## Реестр data/tribes/*.tres (TribeDef).

const DIR := "res://data/tribes/"

static var _reg: Registry


static func ensure_loaded() -> void:
	if _reg == null:
		_reg = Registry.new(DIR, TribeDef)


static func all() -> Array[Resource]:
	ensure_loaded()
	return _reg.items


static func find(id: StringName) -> TribeDef:
	ensure_loaded()
	return _reg.find(id)
