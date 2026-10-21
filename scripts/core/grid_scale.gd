class_name GridScale
## Масштаб сетки (этап 12.A): во сколько раз по каждой оси клетки мельче
## «базовых». Мир на экране тот же, клеток в scale² раз больше. Все числа,
## зависящие от размера клетки, пересчитываются здесь, чтобы разрешение карты
## менялось одним параметром (MapSettings.grid_scale / World.grid_scale):
##   dist  — расстояния и радиусы (в клетках) × scale;
##   area  — площади и пороги по числу клеток × scale²;
##   per_cell — ёмкость, добыча и шансы «на клетку» ÷ scale²;
##   speed — скорости (клеток в день) × scale;
##   base  — площадь в «условных клетках» для интерфейса и летописи ÷ scale².
## При scale = 1 все функции возвращают аргумент без изменений (побитно):
## мир ×1 тот же, что и до введения масштаба (tests/grid_scale_test.gd).

## Допустимые масштабы.
const SCALES := [1, 2, 3]


static func valid(s: int) -> int:
	return s if SCALES.has(s) else 1


static func dist(s: int, n: float) -> float:
	return n * s


static func dist_i(s: int, n: int) -> int:
	return n * s


static func area(s: int, n: float) -> float:
	return n * (s * s)


static func area_i(s: int, n: int) -> int:
	return n * s * s


static func per_cell(s: int, v: float) -> float:
	return v / float(s * s) if s != 1 else v


static func speed(s: int, v: float) -> float:
	return v * s


## Площадь в базовых («условных») клетках — для интерфейса, летописи, достижений.
static func base(s: int, cells: float) -> float:
	return cells / float(s * s) if s != 1 else cells


static func base_i(s: int, cells: int) -> int:
	return cells / (s * s) if s != 1 else cells


## Длина в базовых клетках (расстояния в интерфейсе).
static func base_len(s: int, len: float) -> float:
	return len / float(s) if s != 1 else len
