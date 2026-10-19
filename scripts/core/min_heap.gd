class_name MinHeap
extends RefCounted
## Двоичная куча (int-элемент, float-приоритет) на Packed-массивах.
## Используется для «Дейкстры» при расширении территорий и поиске путей.

var _items := PackedInt32Array()
var _prio := PackedFloat32Array()
var _size := 0


func is_empty() -> bool:
	return _size == 0


func size() -> int:
	return _size


func clear() -> void:
	_size = 0


func push(item: int, priority: float) -> void:
	if _size == _items.size():
		var cap := maxi(16, _size * 2)
		_items.resize(cap)
		_prio.resize(cap)
	var i := _size
	_size += 1
	# Просеивание вверх.
	while i > 0:
		var parent := (i - 1) >> 1
		if _prio[parent] <= priority:
			break
		_items[i] = _items[parent]
		_prio[i] = _prio[parent]
		i = parent
	_items[i] = item
	_prio[i] = priority


func top_priority() -> float:
	return _prio[0]


func pop() -> int:
	var top := _items[0]
	_size -= 1
	if _size > 0:
		var item := _items[_size]
		var priority := _prio[_size]
		var i := 0
		# Просеивание вниз.
		while true:
			var child := i * 2 + 1
			if child >= _size:
				break
			if child + 1 < _size and _prio[child + 1] < _prio[child]:
				child += 1
			if _prio[child] >= priority:
				break
			_items[i] = _items[child]
			_prio[i] = _prio[child]
			i = child
		_items[i] = item
		_prio[i] = priority
	return top
