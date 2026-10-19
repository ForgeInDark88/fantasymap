class_name EconomyDB
## Реестр игровых данных: месторождения (data/deposits), постройки (data/buildings)
## и случайные события (data/events).

const DEPOSITS_DIR := "res://data/deposits/"
const BUILDINGS_DIR := "res://data/buildings/"
const EVENTS_DIR := "res://data/events/"

static var _deposits: Array[DepositDef] = []
static var _buildings: Array[BuildingDef] = []
static var _building_by_id: Dictionary[StringName, BuildingDef] = {}
static var _events: Array[EventDef] = []
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for res in DataLoader.load_dir(DEPOSITS_DIR, DepositDef):
		var d := res as DepositDef
		if Goods.index_of(d.goods) < 0:
			push_error("EconomyDB: у месторождения %s неизвестный ресурс %s" % [d.id, d.goods])
			continue
		_deposits.append(d)
	for res in DataLoader.load_dir(BUILDINGS_DIR, BuildingDef):
		var b := res as BuildingDef
		for biome_id in b.requires_biomes:
			var def := BiomeDB.find_by_id(biome_id)
			if def == null:
				push_error("EconomyDB: у постройки %s неизвестный биом %s" % [b.id, biome_id])
			else:
				b.required_biome_mask |= 1 << def.index
		_buildings.append(b)
		_building_by_id[b.id] = b
	for res in DataLoader.load_dir(EVENTS_DIR, EventDef):
		_events.append(res as EventDef)


## Месторождения; индекс в массиве + 1 хранится в World.deposit (0 — нет месторождения).
static func deposits() -> Array[DepositDef]:
	ensure_loaded()
	return _deposits


static func buildings() -> Array[BuildingDef]:
	ensure_loaded()
	return _buildings


static func get_building(id: StringName) -> BuildingDef:
	ensure_loaded()
	return _building_by_id.get(id)


static func events() -> Array[EventDef]:
	ensure_loaded()
	return _events


static func get_event(id: StringName) -> EventDef:
	for e in events():
		if e.id == id:
			return e
	return null
