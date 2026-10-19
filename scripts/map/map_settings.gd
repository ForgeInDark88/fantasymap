class_name MapSettings
extends Resource
## Параметры генерации мира. Одинаковые настройки + seed = одинаковая карта.

const SIZE_PRESETS: Array[Vector2i] = [
	Vector2i(256, 160),
	Vector2i(384, 240),
	Vector2i(512, 320),
	Vector2i(768, 480),
]
const SIZE_NAMES: Array[String] = ["Маленькая", "Средняя", "Большая", "Огромная"]
const DEFAULT_SIZE_PRESET := 1

@export_range(64, 2048) var width: int = 384
@export_range(64, 2048) var height: int = 240
@export var world_seed: int = 12345
## Доля суши (0.15..0.85).
@export_range(0.15, 0.85) var land_fraction: float = 0.40
@export_range(1, 12) var continents: int = 4
## Множитель количества рек.
@export_range(0.25, 3.0) var river_density: float = 1.0
## Сдвиг климата: < 0 холоднее, > 0 теплее.
@export_range(-0.3, 0.3) var temperature_bias: float = 0.0


func apply_size_preset(preset: int) -> void:
	var s := SIZE_PRESETS[clampi(preset, 0, SIZE_PRESETS.size() - 1)]
	width = s.x
	height = s.y


func size_preset_index() -> int:
	return SIZE_PRESETS.find(Vector2i(width, height))
