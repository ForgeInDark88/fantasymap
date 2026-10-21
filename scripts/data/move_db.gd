class_name MoveDB
## Реестр профилей движения (data/movement/*.tres) и допустимых телепортов
## (data/teleports/*.tres).

const DIR := "res://data/movement/"
const TELEPORT_DIR := "res://data/teleports/"

static var _profiles: Dictionary = {}
static var _teleports: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var reg := Registry.new(DIR, MoveProfileDef)
	for p in reg.items:
		_profiles[(p as MoveProfileDef).id] = p
	var treg := Registry.new(TELEPORT_DIR, TeleportDef)
	for t in treg.items:
		_teleports[(t as TeleportDef).id] = t


static func profile(id: StringName) -> MoveProfileDef:
	ensure_loaded()
	return _profiles.get(id, _profiles.get(&"hero"))


static func profiles() -> Array:
	ensure_loaded()
	return _profiles.values()


static func teleport(id: StringName) -> TeleportDef:
	ensure_loaded()
	return _teleports.get(id)


static func teleports() -> Array:
	ensure_loaded()
	return _teleports.values()
