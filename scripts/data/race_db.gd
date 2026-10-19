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
	for file_name in _resource_files(TRAITS_DIR):
		var t := load(TRAITS_DIR + file_name) as TraitDef
		if t == null:
			push_error("RaceDB: %s не является TraitDef" % file_name)
			continue
		_traits[t.id] = t
	for file_name in _resource_files(RACES_DIR):
		var race := load(RACES_DIR + file_name) as RaceDef
		if race == null:
			push_error("RaceDB: %s не является RaceDef" % file_name)
			continue
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


static func get_race(id: StringName) -> RaceDef:
	ensure_loaded()
	return _by_id.get(id)


static func get_trait(id: StringName) -> TraitDef:
	ensure_loaded()
	return _traits.get(id)


static func _resource_files(dir: String) -> PackedStringArray:
	var result := PackedStringArray()
	for file_name in ResourceLoader.list_directory(dir):
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			result.append(file_name)
	result.sort()  # стабильный порядок → детерминированная генерация
	return result
