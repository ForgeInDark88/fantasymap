class_name MapRenderer
extends Node2D
## Отображение карты: одна текстура (1 тексель = 1 клетка) на Sprite2D.
##
## Почему не TileMapLayer: карта 384×240 — это ~92 тыс. клеток, а при
## симуляции цвета (границы, владельцы) меняются каждый «год». Перестроить
## TileMap на 100+ тыс. ячеек — десятки миллисекунд и много памяти на ноды/квадранты;
## обновить одну текстуру — один вызов ImageTexture.update() и один draw call.
## Для политических режимов (этап 2) поверх ляжет шейдер, читающий текстуру
## владельцев клеток, — тогда перерисовка границ будет вообще на GPU.

## Размер клетки в мировых единицах.
const CELL_SIZE := 4.0

var map: WorldMap
var mode := MapMode.BIOMES

var _sprite: Sprite2D
var _texture: ImageTexture


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * CELL_SIZE
	# Пиксельная чёткость при приближении, мип-карты — без «ряби» при отдалении.
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	add_child(_sprite)
	EventBus.world_generated.connect(_on_world_generated)
	EventBus.map_mode_changed.connect(set_mode)


func set_mode(new_mode: int) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	redraw()


func redraw() -> void:
	if map == null:
		return
	var img := MapPainter.paint(map, mode)
	img.generate_mipmaps()
	if _texture != null and Vector2i(_texture.get_size()) == img.get_size():
		_texture.update(img)
	else:
		_texture = ImageTexture.create_from_image(img)
		_sprite.texture = _texture


## Прямоугольник карты в мировых координатах.
func get_map_rect() -> Rect2:
	if map == null:
		return Rect2()
	return Rect2(global_position, Vector2(map.width, map.height) * CELL_SIZE)


## Индекс клетки под точкой мира или -1.
func cell_at(world_pos: Vector2) -> int:
	if map == null:
		return -1
	var p := (to_local(world_pos) / CELL_SIZE).floor()
	if not map.in_bounds(int(p.x), int(p.y)):
		return -1
	return map.index_of(int(p.x), int(p.y))


func _on_world_generated(new_map: WorldMap, _elapsed_ms: int) -> void:
	map = new_map
	redraw()
