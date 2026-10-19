extends Node2D
## Корневая сцена: связывает камеру, рендер карты и ввод мыши с EventBus.
## Игровой логики здесь нет — она в WorldState/World (и в движке симуляции на этапе 3).

@onready var _renderer: MapRenderer = $MapRenderer
@onready var _camera: MapCamera = $MapCamera

var _hovered_cell := -1
var _last_map_size := Vector2i.ZERO


func _ready() -> void:
	EventBus.world_generated.connect(_on_world_generated)
	_camera.map_clicked.connect(_on_map_clicked)

	var settings := MapSettings.new()
	settings.world_seed = randi_range(1, 999999)
	EventBus.generate_requested.emit(settings)


func _process(_delta: float) -> void:
	var cell := _renderer.cell_at(get_global_mouse_position())
	if cell != _hovered_cell:
		_hovered_cell = cell
		EventBus.cell_hovered.emit(cell)


## Клик по карте: выбираем государство под курсором (или снимаем выбор).
func _on_map_clicked(pos: Vector2) -> void:
	var cell := _renderer.cell_at(pos)
	EventBus.cell_clicked.emit(cell)
	var world := WorldState.world
	EventBus.nation_selected.emit(world.owner[cell] if world != null and cell >= 0 else -1)


func _on_world_generated(world: World, _elapsed_ms: int) -> void:
	_hovered_cell = -2  # обновить подсказку для нового мира
	var rect := _renderer.get_map_rect()
	_camera.bounds = rect
	# Камеру сбрасываем только если поменялся размер карты — при перегенерации
	# с тем же размером удобно сравнивать миры с одного ракурса.
	var size := Vector2i(world.map.width, world.map.height)
	if size != _last_map_size:
		_last_map_size = size
		_camera.fit_to(rect)
