class_name MapCamera
extends Camera2D
## Свободная камера карты с плавностью (SmoothSettings.camera).
##   Колесо / Q,E / жест щипка — зум к курсору (через target_zoom).
##   ЛКМ-перетаскивание, СКМ или ПКМ — панорамирование с инерцией;
##   клик ЛКМ без движения — выбор.
##   WASD / стрелки — перемещение цели (Shift — быстрее), F — вся карта (перелёт).
## Сглаживание экспоненциальное: доля пути за кадр 1 - exp(-k·delta), поэтому
## поведение не зависит от FPS. fly_to — перелёт по дуге (отдалиться →
## сдвинуться → приблизиться) для дальних целей; любой ввод его прерывает.

## Клик по карте (без перетаскивания), в мировых координатах.
signal map_clicked(world_pos: Vector2)
## Пользователь сам двинул камеру (прерывает перелёт и слежение).
signal user_moved

@export var min_zoom := 0.2
@export var max_zoom := 16.0
@export var zoom_step := 1.15
## Скорость клавиатурного перемещения в пикселях экрана в секунду.
@export var pan_speed := 900.0

## Камера не уезжает центром за этот прямоугольник.
var bounds := Rect2()
var target_zoom := 1.0
var target_position := Vector2.ZERO

const DRAG_THRESHOLD := 5.0
## Затухание инерции после перетаскивания (1/с) и минимальная скорость (пикс. мира/с).
const INERTIA_DECAY := 4.5
const INERTIA_MIN := 4.0
## Перелёт: длительность от расстояния (в экранах), «провал» зума на дальних перелётах.
const FLIGHT_MIN := 0.45
const FLIGHT_MAX := 1.6

var _drag_button := MOUSE_BUTTON_NONE
var _drag_moved := false
var _press_pos := Vector2.ZERO
var _velocity := Vector2.ZERO
var _drag_samples: Array = []
## Точка мира, которая держится под курсором во время плавного зума.
var _anchor_world := Vector2.INF
var _anchor_screen := Vector2.ZERO
var _flight: Dictionary = {}


func _ready() -> void:
	position_smoothing_enabled = false
	target_zoom = zoom.x
	target_position = position
	make_current()


## Мгновенно показать прямоугольник (первый показ мира).
func fit_to(rect: Rect2) -> void:
	bounds = rect
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var z := _fit_zoom(rect)
	_flight = {}
	_velocity = Vector2.ZERO
	_anchor_world = Vector2.INF
	zoom = Vector2.ONE * z
	target_zoom = z
	position = rect.get_center()
	target_position = position


func _fit_zoom(rect: Rect2) -> float:
	var vp := get_viewport_rect().size
	return clampf(minf(vp.x / rect.size.x, vp.y / rect.size.y) * 0.95, min_zoom, max_zoom)


## Плавный перелёт к точке (zoom_to <= 0 — не менять зум).
func fly_to(pos: Vector2, zoom_to: float = -1.0) -> void:
	var z1 := clampf(zoom_to if zoom_to > 0.0 else target_zoom, min_zoom, max_zoom)
	pos = _clamp(pos)
	_velocity = Vector2.ZERO
	_anchor_world = Vector2.INF
	if SmoothSettings.camera_k() <= 0.0:
		_flight = {}
		zoom = Vector2.ONE * z1
		target_zoom = z1
		position = pos
		target_position = pos
		return
	var vp := get_viewport_rect().size
	var screens := position.distance_to(pos) * zoom.x / maxf(1.0, vp.x)
	var dur := clampf(FLIGHT_MIN + 0.35 * log(1.0 + screens) / log(2.0), FLIGHT_MIN, FLIGHT_MAX)
	if SmoothSettings.camera == 2:
		dur *= 1.3
	# Дальний перелёт — отдаляемся так, чтобы обе точки уместились в кадре.
	var mid := minf(zoom.x, z1)
	if screens > 1.2:
		mid = clampf(mid / (1.0 + 0.6 * minf(screens, 8.0)), min_zoom, max_zoom)
	_flight = {"from": position, "to": pos, "z0": zoom.x, "z1": z1, "mid": mid, "t": 0.0, "dur": dur}


func fly_to_rect(rect: Rect2) -> void:
	fly_to(rect.get_center(), _fit_zoom(rect))


## Слежение: цель камеры — точка (вызывать каждый кадр).
func follow(pos: Vector2) -> void:
	if not _flight.is_empty() or _drag_button != MOUSE_BUTTON_NONE:
		return
	target_position = _clamp(pos)


func is_flying() -> bool:
	return not _flight.is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE:
		var mm := event as InputEventMouseMotion
		if not _drag_moved and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_drag_moved = true
			_interrupt()
		if _drag_moved:
			var d := mm.relative / zoom.x
			position = _clamp(position - d)
			target_position = position
			_drag_samples.append([Time.get_ticks_usec(), -d])
			while _drag_samples.size() > 6:
				_drag_samples.pop_front()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_interrupt()
		_zoom_at(mg.factor, mg.position)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_interrupt()
		target_position = _clamp(target_position + pg.delta * 12.0 / zoom.x)
	elif event.is_action_pressed("cam_reset"):
		_interrupt()
		fly_to_rect(bounds)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_interrupt()
				_zoom_at(zoom_step, mb.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_interrupt()
				_zoom_at(1.0 / zoom_step, mb.position)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if _drag_button == MOUSE_BUTTON_NONE:
					_drag_button = mb.button_index
					_press_pos = mb.position
					_velocity = Vector2.ZERO
					_drag_samples.clear()
					# СКМ/ПКМ всегда тянут карту; ЛКМ — только после порога (иначе это клик).
					_drag_moved = mb.button_index != MOUSE_BUTTON_LEFT
					if _drag_moved:
						_interrupt()
			elif mb.button_index == _drag_button:
				if mb.button_index == MOUSE_BUTTON_LEFT and not _drag_moved:
					map_clicked.emit(_screen_to_world(mb.position))
				elif _drag_moved:
					_velocity = _release_velocity()
				_drag_button = MOUSE_BUTTON_NONE


## Скорость пальца/мыши за последние ~0,1 с — для инерции.
func _release_velocity() -> Vector2:
	if SmoothSettings.camera_k() <= 0.0 or _drag_samples.size() < 2:
		return Vector2.ZERO
	var now := Time.get_ticks_usec()
	var sum := Vector2.ZERO
	var first := now
	for s in _drag_samples:
		if now - int(s[0]) < 100000:
			sum += s[1]
			first = mini(first, int(s[0]))
	var dt := maxf(0.016, (now - first) / 1e6)
	return sum / dt


func _interrupt() -> void:
	var was := not _flight.is_empty()
	_flight = {}
	user_moved.emit()
	if was:
		target_position = position
		target_zoom = zoom.x


func _process(delta: float) -> void:
	step(delta)


## Один шаг камеры (вынесен для тестов: моделирование разного FPS).
func step(delta: float) -> void:
	var k := SmoothSettings.camera_k()
	if not _flight.is_empty():
		_step_flight(delta)
		return
	# Клавиатура двигает цель (не пока пользователь печатает в поле ввода).
	if is_inside_tree() and not (get_viewport().gui_get_focus_owner() is LineEdit):
		var dir := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
		if dir != Vector2.ZERO:
			_interrupt()
			var speed := pan_speed * (2.5 if Input.is_action_pressed("cam_fast") else 1.0)
			target_position = _clamp(target_position + dir * speed * delta / zoom.x)
		var zoom_dir := Input.get_axis("cam_zoom_out", "cam_zoom_in")
		if zoom_dir != 0.0:
			_interrupt()
			_zoom_at(pow(3.0, zoom_dir * delta), get_viewport_rect().size * 0.5)
	# Инерция после перетаскивания.
	if _drag_button == MOUSE_BUTTON_NONE and _velocity.length() > INERTIA_MIN:
		target_position = _clamp(target_position + _velocity * delta)
		position = _clamp(position + _velocity * delta)
		_velocity *= exp(-INERTIA_DECAY * delta)
	elif _drag_button == MOUSE_BUTTON_NONE:
		_velocity = Vector2.ZERO
	# Зум к курсору: точка под курсором остаётся на месте на всём пути.
	var z := SmoothSettings.damp(zoom.x, target_zoom, k, delta)
	if absf(z - target_zoom) < target_zoom * 0.0005:
		z = target_zoom
	if z != zoom.x:
		zoom = Vector2(z, z)
		if _anchor_world != Vector2.INF:
			position = _clamp(_anchor_world - (_anchor_screen - _viewport_size() * 0.5) / z)
			target_position = position
	if z == target_zoom:
		_anchor_world = Vector2.INF
	if _drag_button == MOUSE_BUTTON_NONE or not _drag_moved:
		var p := SmoothSettings.damp_v(position, target_position, k, delta)
		if p.distance_to(target_position) < 0.05 / zoom.x:
			p = target_position
		position = p


func _step_flight(delta: float) -> void:
	var f := _flight
	f.t = float(f.t) + delta
	var t := clampf(float(f.t) / float(f.dur), 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)  # плавный старт и финиш
	position = (f.from as Vector2).lerp(f.to, e)
	# Зум — в логарифмической шкале, с «провалом» к mid посередине.
	var lz := lerpf(log(float(f.z0)), log(float(f.z1)), e)
	var dip := minf(log(float(f.mid)) - minf(log(float(f.z0)), log(float(f.z1))), 0.0)
	lz += dip * sin(PI * t)
	zoom = Vector2.ONE * exp(lz)
	if t >= 1.0:
		zoom = Vector2.ONE * float(f.z1)
		position = f.to
		target_zoom = float(f.z1)
		target_position = position
		_flight = {}


## Зум с сохранением точки мира под курсором (плавно — к target_zoom).
func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	_anchor_world = _screen_to_world(screen_pos) if _anchor_world == Vector2.INF or screen_pos != _anchor_screen else _anchor_world
	_anchor_screen = screen_pos
	target_zoom = clampf(target_zoom * factor, min_zoom, max_zoom)
	if SmoothSettings.camera_k() <= 0.0:
		zoom = Vector2.ONE * target_zoom
		position = _clamp(_anchor_world - (screen_pos - _viewport_size() * 0.5) / target_zoom)
		target_position = position
		_anchor_world = Vector2.INF


func _viewport_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(1600, 900)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - _viewport_size() * 0.5) / zoom.x


func _clamp(p: Vector2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return p
	return p.clamp(bounds.position, bounds.end)
