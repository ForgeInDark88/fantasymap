class_name LoreDB
## Реестр артефактов (data/artifacts), богов (data/gods) и событий пути героя (data/hero_events).

static var _artifacts: Registry
static var _gods: Registry
static var _events: Registry


static func ensure_loaded() -> void:
	if _artifacts == null:
		_artifacts = Registry.new("res://data/artifacts/", ArtifactDef)
		_gods = Registry.new("res://data/gods/", GodDef)
		_events = Registry.new("res://data/hero_events/", HeroEventDef)


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


static func hero_events() -> Array[Resource]:
	ensure_loaded()
	return _events.items


static func hero_event(id: StringName) -> HeroEventDef:
	ensure_loaded()
	return _events.find(id)
