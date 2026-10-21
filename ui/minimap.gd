class_name Minimap
extends PanelContainer
## Миникарта (этап 11.F): весь мир в углу — державы цветом, вода и ничьи
## земли — по биомам; рамка — что видно на экране. Клик — плавный перелёт
## камеры туда. Картинка обновляется раз в REFRESH_MS (без перебора клеток в
## каждом кадре). Скрыть/показать — клавиша M или меню «☰».

const REFRESH_MS := 2000
const WIDTH := 240.0

var _rect: TextureRect
var _frame: Control
var _tex: ImageTexture
var _last_ms := -100000
var _last_version := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -WIDTH - 16.0
	offset_right = -8.0
	offset_top = -170.0
	offset_bottom = -8.0
	tooltip_text = "Миникарта: клик — перелёт камеры (M — скрыть)"
	_rect = TextureRect.new()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.custom_minimum_size = Vector2(WIDTH, 150)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_frame)
	_rect.add_child(_frame)
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void:
		_last_ms = -100000
		_last_version = -1)
	EventBus.minimap_toggled.connect(func() -> void: visible = not visible)


func _process(_delta: float) -> void:
	var world := WorldState.world
	if not visible or world == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_ms > REFRESH_MS and world.ownership_version != _last_version:
		_last_ms = now
		_last_version = world.ownership_version
		_rebuild(world)
	_frame.queue_redraw()


func _rebuild(world: World) -> void:
	var map := world.map
	var step := maxi(1, map.width / int(WIDTH))
	var w := map.width / step
	var h := map.height / step
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var i := (y * step) * map.width + x * step
			var o := world.owner[i]
			var c: Color
			if o >= 0:
				c = world.nations[o].color
			elif map.is_land(i):
				c = BiomeDB.get_def(map.biome[i]).color.darkened(0.25)
			else:
				c = Color(0.1, 0.18, 0.3)
			img.set_pixel(x, y, c)
	if _tex == null or Vector2i(_tex.get_size()) != img.get_size():
		_tex = ImageTexture.create_from_image(img)
		_rect.texture = _tex
	else:
		_tex.update(img)
	_rect.custom_minimum_size = Vector2(WIDTH, WIDTH * float(map.height) / float(map.width))
	offset_top = offset_bottom - _rect.custom_minimum_size.y - 8.0


func _renderer() -> Node:
	return get_node_or_null("/root/Main/MapRenderer")


func _draw_frame() -> void:
	var r := _renderer()
	var cam := get_viewport().get_camera_2d()
	if r == null or cam == null:
		return
	var map_rect: Rect2 = r.call("get_map_rect")
	var view_size := get_viewport().get_visible_rect().size / cam.zoom
	var view := Rect2(cam.get_screen_center_position() - view_size / 2.0, view_size)
	var k := _frame.size / map_rect.size
	var box := Rect2((view.position - map_rect.position) * k, view.size * k).intersection(Rect2(Vector2.ZERO, _frame.size))
	_frame.draw_rect(box, Color(1.0, 1.0, 1.0, 0.9), false, 1.5)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var r := _renderer()
	var world := WorldState.world
	if r == null or world == null:
		return
	var map_rect: Rect2 = r.call("get_map_rect")
	var p := map_rect.position + (mb.position - _rect.position) / _rect.size * map_rect.size
	var cell: int = r.call("cell_at", p)
	if cell >= 0:
		EventBus.focus_cell.emit(cell)
	accept_event()
