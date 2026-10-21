class_name Mover
extends RefCounted
## Положение и путь движущегося юнита (этап 12.B): армии, флота, героя,
## каравана, гонца, поселенцев, племени, чудовища. Юнит стоит в клетке cell и
## идёт по пути path (клетки впереди, с индекса step) со скоростью своего
## профиля движения (MoveProfileDef): frac — сколько суток уже потрачено на
## переход в следующую клетку. Никаких прыжков: клетка меняется только на
## соседнюю (MovementSystem.advance), мгновенно — лишь допустимые телепорты
## (MovementSystem.teleport, data/teleports). Всё это — часть симуляции и
## сохраняется; отрисовка лишь сглаживает показ между сутками.

var cell := -1
var path := PackedInt32Array()
var step := 0
var frac := 0.0
## Профиль движения (MoveProfileDef.id).
var profile: StringName = &"hero"
## Куда идёт (последняя клетка пути; -1 — стоит).
var dest := -1
## Чей юнит (для чужой земли и дорог); -1 — ничей.
var nation := -1
## Сколько клеток прошёл за последние сутки и клетка в их начале (проверка
## «телепортов» в тестах, направление значка на карте).
var moved := 0
var prev_cell := -1
## В последние сутки дошёл до конца пути (событие «пришёл» — ровно один раз).
var arrived := false
## Сутки подряд без движения при непустом пути (застрял — повод перепланировать).
var stuck := 0
## Профиль движения (кэш ссылки на MoveProfileDef; не сохраняется).
var _prof: MoveProfileDef = null


func prof() -> MoveProfileDef:
	if _prof == null or _prof.id != profile:
		_prof = MoveDB.profile(profile)
	return _prof


func _init(start_cell: int = -1, profile_id: StringName = &"hero") -> void:
	cell = start_cell
	prev_cell = start_cell
	profile = profile_id


func walking() -> bool:
	return step < path.size()


func next_cell() -> int:
	return path[step] if step < path.size() else -1


## Клеток пути осталось.
func remaining() -> int:
	return path.size() - step


func set_path(p: PackedInt32Array) -> void:
	path = p
	step = 0
	frac = 0.0
	stuck = 0
	dest = p[p.size() - 1] if not p.is_empty() else -1


func stop() -> void:
	path = PackedInt32Array()
	step = 0
	frac = 0.0
	dest = -1


## Оставшийся путь (для показа и сохранения).
func ahead() -> PackedInt32Array:
	return path.slice(step) if step < path.size() else PackedInt32Array()


func to_dict() -> Dictionary:
	# Пройденная часть пути не нужна — сохраняем оставшуюся.
	return {"cell": cell, "path": Array(ahead()), "frac": frac, "profile": str(profile), "nation": nation,
		"moved": moved, "prev": prev_cell, "arrived": arrived, "stuck": stuck}


static func from_dict(d: Dictionary) -> Mover:
	var m := Mover.new(int(d.get("cell", -1)), StringName(d.get("profile", "hero")))
	var p := PackedInt32Array()
	for c in d.get("path", []):
		p.append(int(c))
	m.path = p
	m.dest = p[p.size() - 1] if not p.is_empty() else -1
	m.frac = float(d.get("frac", 0.0))
	m.nation = int(d.get("nation", -1))
	m.moved = int(d.get("moved", 0))
	m.prev_cell = int(d.get("prev", m.cell))
	m.arrived = bool(d.get("arrived", false))
	m.stuck = int(d.get("stuck", 0))
	return m
