class_name BiomeDB
## Реестр биомов: загружает все BiomeDef из data/biomes/ и раздаёт их по индексу.
##
## Чтобы добавить биом: константа в Biome + .tres-файл с тем же index
## + правило классификации в MapGenerator._assign_biomes().

const BIOMES_DIR := "res://data/biomes/"

static var _defs: Array[BiomeDef] = []


static func ensure_loaded() -> void:
	if not _defs.is_empty():
		return
	_defs.resize(Biome.COUNT)
	# list_directory корректно работает и в экспортированной сборке (учитывает .remap).
	for file_name in ResourceLoader.list_directory(BIOMES_DIR):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var def := load(BIOMES_DIR + file_name) as BiomeDef
		if def == null:
			push_error("BiomeDB: %s не является BiomeDef" % file_name)
			continue
		if def.index < 0 or def.index >= Biome.COUNT:
			push_error("BiomeDB: у %s неверный index %d" % [file_name, def.index])
			continue
		_defs[def.index] = def
	for i in Biome.COUNT:
		if _defs[i] == null:
			push_error("BiomeDB: нет данных для биома с индексом %d" % i)
			var fallback := BiomeDef.new()
			fallback.index = i
			fallback.display_name = "?"
			_defs[i] = fallback


static func get_def(index: int) -> BiomeDef:
	ensure_loaded()
	return _defs[index]


static func all() -> Array[BiomeDef]:
	ensure_loaded()
	return _defs


static func find_by_id(id: StringName) -> BiomeDef:
	ensure_loaded()
	for def in _defs:
		if def.id == id:
			return def
	return null
