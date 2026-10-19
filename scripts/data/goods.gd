class_name Goods
## Виды ресурсов. Еда считается отдельно (через ёмкость земли и запас еды),
## остальные добываются с клеток (биом + месторождение) и в постройках.

const FOOD := 0
const WOOD := 1
const STONE := 2
const METAL := 3
const GOLD := 4

const COUNT := 5
const IDS: Array[StringName] = [&"food", &"wood", &"stone", &"metal", &"gold"]
const NAMES: Array[String] = ["Еда", "Дерево", "Камень", "Металл", "Золото"]


static func index_of(id: StringName) -> int:
	return IDS.find(id)
