class_name LoreDB
## Реестр артефактов (data/artifacts) и богов (data/gods).

static var _artifacts: Registry
static var _gods: Registry


static func ensure_loaded() -> void:
	if _artifacts == null:
		_artifacts = Registry.new("res://data/artifacts/", ArtifactDef)
		_gods = Registry.new("res://data/gods/", GodDef)


static func artifacts() -> Array[Resource]:
	ensure_loaded()
	return _artifacts.items


static func artifact(id: StringName) -> ArtifactDef:
	ensure_loaded()
	return _artifacts.find(id)


static func gods() -> Array[Resource]:
	ensure_loaded()
	return _gods.items


static func god(id: StringName) -> GodDef:
	ensure_loaded()
	return _gods.find(id)
