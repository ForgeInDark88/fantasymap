class_name MapSettings
extends Resource
## Параметры генерации мира. Одинаковые настройки + seed = одинаковый мир.

const SIZE_PRESETS: Array[Vector2i] = [
	Vector2i(256, 160),
	Vector2i(384, 240),
	Vector2i(512, 320),
	Vector2i(768, 480),
]
const SIZE_NAMES: Array[String] = ["Маленькая", "Средняя", "Большая", "Огромная"]
const DEFAULT_SIZE_PRESET := 1
## Детализация в игре по умолчанию (этап 12.D): ×2. MapSettings.new() остаётся ×1 —
## на нём эталоны, хэши и тесты; игра и панель «Мир» задают масштаб явно.
const DEFAULT_GRID_SCALE := 2
const GRID_SCALE_NAMES: Array[String] = ["×1 — крупные клетки", "×2 — подробно"]

## Размер карты в «базовых» клетках (пресеты — в них же). Фактическая сетка —
## base × grid_scale по каждой оси: cell_width(), cell_height().
@export_range(64, 2048) var width: int = 384
@export_range(64, 2048) var height: int = 240
## Масштаб сетки (GridScale): 1 — клетка как раньше, 2 — каждая базовая клетка
## делится на 2×2 (мир тот же, деталей больше).
@export_range(1, 3) var grid_scale: int = 1
@export var world_seed: int = 12345
## Доля суши (0.15..0.85).
@export_range(0.15, 0.85) var land_fraction: float = 0.40
@export_range(1, 12) var continents: int = 4
## Множитель количества рек.
@export_range(0.25, 3.0) var river_density: float = 1.0
## Сдвиг климата: < 0 холоднее, > 0 теплее.
@export_range(-0.3, 0.3) var temperature_bias: float = 0.0

@export_group("Государства")
## Сколько государств появляется в начале мира.
@export_range(0, 64) var nation_count: int = 14
## Какие расы участвуют (id из data/races). Пусто — все.
@export var enabled_races: Array[StringName] = []


func apply_size_preset(preset: int) -> void:
	var s := SIZE_PRESETS[clampi(preset, 0, SIZE_PRESETS.size() - 1)]
	width = s.x
	height = s.y


func cell_width() -> int:
	return width * grid_scale


func cell_height() -> int:
	return height * grid_scale


func size_preset_index() -> int:
	return SIZE_PRESETS.find(Vector2i(width, height))
