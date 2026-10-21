class_name SettlementDB
## Реестр data/settlement/*.tres (SettlementDef).

const DIR := "res://data/settlement/"

static var _reg: Registry


static func ensure_loaded() -> void:
	if _reg == null:
		_reg = Registry.new(DIR, SettlementDef)


static func all() -> Array[Resource]:
	ensure_loaded()
	return _reg.items


static func find(id: StringName) -> SettlementDef:
	ensure_loaded()
	return _reg.find(id)
