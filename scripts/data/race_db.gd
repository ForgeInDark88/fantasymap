class_name RaceDB
## Реестр рас и особенностей: загружает data/races/*.tres и data/traits/*.tres.

const RACES_DIR := "res://data/races/"
const TRAITS_DIR := "res://data/traits/"

static var _races: Array[RaceDef] = []
static var _by_id: Dictionary[StringName, RaceDef] = {}
static var _traits: Dictionary[StringName, TraitDef] = {}


static func ensure_loaded() -> void:
	if not _races.is_empty():
		return
	BiomeDB.ensure_loaded()
	for res in DataLoader.load_dir(TRAITS_DIR, TraitDef):
		var t := res as TraitDef
		_traits[t.id] = t
	for res in DataLoader.load_dir(RACES_DIR, RaceDef):
		var race := res as RaceDef
		race.index = _races.size()
		race.build_cache()
		for t in race.traits:
			if not _traits.has(t):
				push_warning("RaceDB: у расы %s неизвестная особенность %s" % [race.id, t])
		_races.append(race)
		_by_id[race.id] = race
	if _races.is_empty():
		push_error("RaceDB: не найдено ни одной расы в " + RACES_DIR)


static func all() -> Array[RaceDef]:
	ensure_loaded()
	return _races


static func count() -> int:
	ensure_loaded()
	return _races.size()


static func get_race(id: StringName) -> RaceDef:
	ensure_loaded()
	return _by_id.get(id)


static func by_index(index: int) -> RaceDef:
	return _races[index]


static func get_trait(id: StringName) -> TraitDef:
	ensure_loaded()
	return _traits.get(id)
