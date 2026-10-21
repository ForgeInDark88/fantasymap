class_name MoveProfileDef
extends Resource
## Профиль движения (data/movement/*.tres, этап 12.B): как быстро идёт юнит
## (армия, флот, герой, караван, поселенцы, племя, чудовище, гонец) — в
## базовых клетках в сутки (× grid_scale) — и что его замедляет: рельеф, реки
## без моста, зима, вражеская земля; дороги ускоряют. Сухопутные юниты плывут
## на кораблях со скоростью sea_speed (порт → берег); флоты ходят только по воде.

@export var id: StringName
@export var display_name: String = ""
## Скорость на равнине без дороги (базовых клеток в сутки).
@export var speed: float = 1.0
## Множители скорости по биомам (BiomeDef.id); нет в словаре — 1.
@export var biome_mult: Dictionary = {}
## Дорога (RoadSystem), река без дороги (брод), зима в холодных краях, чужая земля врага.
@export var road_mult: float = 1.5
@export var river_mult: float = 0.6
@export var winter_mult: float = 0.7
@export var enemy_mult: float = 0.85
## Только по воде (флоты, пираты).
@export var water_only: bool = false
## Может сесть на корабль в порту и плыть (сухопутные юниты).
@export var can_sail: bool = true
## Скорость под парусом (базовых клеток в сутки).
@export var sea_speed: float = 2.4
## Видит врага (разведка, дозор) за столько базовых клеток.
@export var scout_range: float = 4.0

var _by_biome := PackedFloat32Array()


## Множитель скорости по индексу биома (кэш: без поиска id в словаре на каждом шаге).
func mult(biome: int) -> float:
	if _by_biome.is_empty():
		var all := BiomeDB.all()
		_by_biome.resize(all.size())
		for i in all.size():
			_by_biome[i] = float(biome_mult.get((all[i] as BiomeDef).id, 1.0))
	return _by_biome[biome] if biome < _by_biome.size() else 1.0
