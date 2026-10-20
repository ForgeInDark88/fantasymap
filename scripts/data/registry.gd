class_name Registry
extends RefCounted
## Реестр однотипных данных из папки data/<категория>/: список в алфавитном
## порядке файлов (index = позиция) и поиск по id. Используется новыми
## реестрами (религии, технологии, организации, кризисы, артефакты, боги…).

var items: Array[Resource] = []
var _by_id: Dictionary[StringName, Resource] = {}


func _init(dir: String, script: Script) -> void:
	for res in DataLoader.load_dir(dir, script):
		if res.get("id") == null or _by_id.has(res.id):
			push_error("Registry: в %s повторяется или пуст id %s" % [dir, res.get("id")])
			continue
		if "index" in res:
			res.index = items.size()
		items.append(res)
		_by_id[res.id] = res


func find(id: StringName) -> Resource:
	return _by_id.get(id)


func has(id: StringName) -> bool:
	return _by_id.has(id)


func size() -> int:
	return items.size()
