class_name LairDB
## Реестр data/lairs/*.tres (LairDef).

const DIR := "res://data/lairs/"

static var _reg: Registry


static func ensure_loaded() -> void:
	if _reg == null:
		_reg = Registry.new(DIR, LairDef)


static func all() -> Array[Resource]:
	ensure_loaded()
	return _reg.items


static func find(id: StringName) -> LairDef:
	ensure_loaded()
	return _reg.find(id)
