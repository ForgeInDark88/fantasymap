class_name DataLoader
## Загрузка всех ресурсов из папки data/ в стабильном (алфавитном) порядке.


static func load_dir(dir: String, expected_script: Script) -> Array[Resource]:
	var result: Array[Resource] = []
	var files := PackedStringArray()
	# list_directory корректно работает и в экспортированной сборке (учитывает .remap).
	for file_name in ResourceLoader.list_directory(dir):
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			files.append(file_name)
	files.sort()
	for file_name in files:
		var res := load(dir + file_name)
		if res == null or res.get_script() != expected_script:
			push_error("DataLoader: %s%s — не %s" % [dir, file_name, expected_script.resource_path.get_file()])
			continue
		result.append(res)
	return result
