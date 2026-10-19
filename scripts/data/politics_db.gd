class_name PoliticsDB
## Реестр политических данных: формы правления, черты правителей, классы героев.

const GOVERNMENTS_DIR := "res://data/governments/"
const RULER_TRAITS_DIR := "res://data/ruler_traits/"
const HERO_CLASSES_DIR := "res://data/hero_classes/"

static var _governments: Dictionary[StringName, GovernmentDef] = {}
static var _traits: Array[RulerTraitDef] = []
static var _classes: Array[HeroClassDef] = []
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for res in DataLoader.load_dir(GOVERNMENTS_DIR, GovernmentDef):
		_governments[res.id] = res
	for res in DataLoader.load_dir(RULER_TRAITS_DIR, RulerTraitDef):
		_traits.append(res)
	for res in DataLoader.load_dir(HERO_CLASSES_DIR, HeroClassDef):
		_classes.append(res)
	if not _governments.has(&"monarchy"):
		push_error("PoliticsDB: нет формы правления monarchy (используется по умолчанию)")


static func government(id: StringName) -> GovernmentDef:
	ensure_loaded()
	return _governments.get(id, _governments.get(&"monarchy"))


static func ruler_traits() -> Array[RulerTraitDef]:
	ensure_loaded()
	return _traits


static func hero_classes() -> Array[HeroClassDef]:
	ensure_loaded()
	return _classes


static func get_hero_class(id: StringName) -> HeroClassDef:
	for c in hero_classes():
		if c.id == id:
			return c
	return null


## Случайная черта правителя с учётом весов.
static func random_ruler_trait(rng: RandomNumberGenerator) -> RulerTraitDef:
	var total := 0.0
	for t in ruler_traits():
		total += t.weight
	var r := rng.randf() * total
	for t in ruler_traits():
		r -= t.weight
		if r <= 0.0:
			return t
	return _traits.back()


## Класс героя для расы (взвешенно по race_weights).
static func random_hero_class(race: RaceDef, rng: RandomNumberGenerator) -> HeroClassDef:
	var total := 0.0
	for c in hero_classes():
		total += c.race_weights.get(race.id, c.default_weight)
	var r := rng.randf() * total
	for c in hero_classes():
		r -= c.race_weights.get(race.id, c.default_weight)
		if r <= 0.0:
			return c
	return _classes.back()
