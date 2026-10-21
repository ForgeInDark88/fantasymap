class_name MarketDB
## Реестр товаров рынка data/goods/*.tres (GoodDef). index — позиция в
## массивах рынка государства (Nation.market_*).

const DIR := "res://data/goods/"

static var _reg: Registry


static func ensure_loaded() -> void:
	if _reg == null:
		_reg = Registry.new(DIR, GoodDef)


static func all() -> Array[Resource]:
	ensure_loaded()
	return _reg.items


static func size() -> int:
	ensure_loaded()
	return _reg.items.size()


static func find(id: StringName) -> GoodDef:
	ensure_loaded()
	return _reg.find(id)


static func index_of(id: StringName) -> int:
	ensure_loaded()
	var g: GoodDef = _reg.find(id)
	return _reg.items.find(g) if g != null else -1
