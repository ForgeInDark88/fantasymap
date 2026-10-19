class_name WorldMap
extends RefCounted
## Данные карты в плоских Packed-массивах (индекс клетки = y * width + x).
##
## Плоские массивы вместо объектов на клетку: компактно, быстро итерировать
## в GDScript и легко сохранять. Эту структуру читает и симуляция, и рендер,
## но не знает ни о том, ни о другом.

## Пороги высоты (высота суши нормирована по рангу, поэтому они постоянны).
const HILL_LEVEL := 0.80
const MOUNTAIN_LEVEL := 0.935

var width: int
var height: int
var settings: MapSettings

## < 0 — вода (-1 самая глубокая), 0 — уровень моря, > 0 — суша (0..1, ранг высоты).
var elevation := PackedFloat32Array()
## 0 (холодно) .. 1 (жарко).
var temperature := PackedFloat32Array()
## 0 (сухо) .. 1 (влажно).
var moisture := PackedFloat32Array()
## Индекс биома (см. Biome).
var biome := PackedByteArray()
## 0 — нет реки, 1..3 — мощность реки.
var river := PackedByteArray()


func _init(w: int = 0, h: int = 0) -> void:
	width = w
	height = h
	var n := w * h
	elevation.resize(n)
	temperature.resize(n)
	moisture.resize(n)
	biome.resize(n)
	river.resize(n)


func cell_count() -> int:
	return width * height


func index_of(x: int, y: int) -> int:
	return y * width + x


func cell_pos(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func is_land(i: int) -> bool:
	return not Biome.is_water(biome[i])


## Индексы 4 соседей (без выхода за край).
func neighbors4(i: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var x := i % width
	if x > 0:
		result.append(i - 1)
	if x < width - 1:
		result.append(i + 1)
	if i >= width:
		result.append(i - width)
	if i < width * (height - 1):
		result.append(i + width)
	return result


## Человекочитаемые величины для интерфейса.
func temperature_celsius(i: int) -> float:
	return lerpf(-30.0, 38.0, temperature[i])


func altitude_meters(i: int) -> float:
	var e := elevation[i]
	if e >= 0.0:
		return e * e * 4800.0
	return e * 6000.0
