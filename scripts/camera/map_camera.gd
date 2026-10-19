class_name MapCamera
extends Camera2D
## Свободная камера карты.
##   Колесо / Q,E / жест щипка — зум к курсору.
##   ЛКМ-перетаскивание, СКМ или ПКМ — панорамирование; клик ЛКМ без движения — выбор.
##   WASD / стрелки — перемещение (Shift — быстрее), F — показать всю карту.

## Клик по карте (без перетаскивания), в мировых координатах.
signal map_clicked(world_pos: Vector2)

@export var min_zoom := 0.2
@export var max_zoom := 16.0
@export var zoom_step := 1.15
## Скорость клавиатурного перемещения в пикселях экрана в секунду.
@export var pan_speed := 900.0

## Камера не уезжает центром за этот прямоугольник.
var bounds := Rect2()

const DRAG_THRESHOLD := 5.0

var _drag_button := MOUSE_BUTTON_NONE
var _drag_moved := false
var _press_pos := Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = false
	make_current()


func fit_to(rect: Rect2) -> void:
	bounds = rect
	var vp := get_viewport_rect().size
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var z := minf(vp.x / rect.size.x, vp.y / rect.size.y) * 0.95
	zoom = Vector2.ONE * clampf(z, min_zoom, max_zoom)
	position = rect.get_center()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE:
		var mm := event as InputEventMouseMotion
		if not _drag_moved and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_drag_moved = true
		if _drag_moved:
			position -= mm.relative / zoom.x
			_clamp_position()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.factor, mg.position)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		position += pg.delta * 12.0 / zoom.x
		_clamp_position()
	elif event.is_action_pressed("cam_reset"):
		fit_to(bounds)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_zoom_at(zoom_step, mb.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_zoom_at(1.0 / zoom_step, mb.position)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if _drag_button == MOUSE_BUTTON_NONE:
					_drag_button = mb.button_index
					_press_pos = mb.position
					# СКМ/ПКМ всегда тянут карту; ЛКМ — только после порога (иначе это клик).
					_drag_moved = mb.button_index != MOUSE_BUTTON_LEFT
			elif mb.button_index == _drag_button:
				if mb.button_index == MOUSE_BUTTON_LEFT and not _drag_moved:
					map_clicked.emit(_screen_to_world(mb.position))
				_drag_button = MOUSE_BUTTON_NONE


func _process(delta: float) -> void:
	# Не двигаем камеру, пока пользователь печатает в поле ввода.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var dir := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if dir != Vector2.ZERO:
		var speed := pan_speed * (2.5 if Input.is_action_pressed("cam_fast") else 1.0)
		position += dir * speed * delta / zoom.x
		_clamp_position()
	var zoom_dir := Input.get_axis("cam_zoom_out", "cam_zoom_in")
	if zoom_dir != 0.0:
		_zoom_at(pow(3.0, zoom_dir * delta), get_viewport_rect().size * 0.5)


## Зум с сохранением точки мира под курсором.
func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var before := _screen_to_world(screen_pos)
	var z := clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(z, z)
	position = before - (screen_pos - get_viewport_rect().size * 0.5) / z
	_clamp_position()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - get_viewport_rect().size * 0.5) / zoom.x


func _clamp_position() -> void:
	if bounds.size == Vector2.ZERO:
		return
	position = position.clamp(bounds.position, bounds.end)
