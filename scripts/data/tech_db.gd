class_name TechDB
## Реестр технологий (data/techs/*.tres).

const DIR := "res://data/techs/"
const BRANCH_NAMES := {"military": "Военное дело", "economy": "Хозяйство", "society": "Общество",
	"magic": "Магия", "navy": "Мореходство"}
const BRANCH_COLORS := {"military": Color(0.9, 0.45, 0.4), "economy": Color(0.85, 0.75, 0.4),
	"society": Color(0.55, 0.75, 0.95), "magic": Color(0.75, 0.55, 0.95), "navy": Color(0.4, 0.75, 0.8)}

static var _reg: Registry


static func ensure_loaded() -> void:
	if _reg == null:
		_reg = Registry.new(DIR, TechDef)
		for t in _reg.items:
			for req in (t as TechDef).requires:
				if not _reg.has(req):
					push_error("TechDB: у технологии %s неизвестное требование %s" % [t.id, req])


static func all() -> Array[Resource]:
	ensure_loaded()
	return _reg.items


static func find(id: StringName) -> TechDef:
	ensure_loaded()
	return _reg.find(id)
