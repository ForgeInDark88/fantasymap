class_name OrgDB
## Реестр организаций (data/orgs) и тайных операций (data/spy_ops).

const ORGS_DIR := "res://data/orgs/"
const OPS_DIR := "res://data/spy_ops/"

static var _orgs: Registry
static var _ops: Registry


static func ensure_loaded() -> void:
	if _orgs == null:
		_orgs = Registry.new(ORGS_DIR, OrgDef)
		_ops = Registry.new(OPS_DIR, SpyOpDef)


static func orgs() -> Array[Resource]:
	ensure_loaded()
	return _orgs.items


static func find_org(id: StringName) -> OrgDef:
	ensure_loaded()
	return _orgs.find(id)


static func ops() -> Array[Resource]:
	ensure_loaded()
	return _ops.items


static func find_op(id: StringName) -> SpyOpDef:
	ensure_loaded()
	return _ops.find(id)
