class_name LineChart
extends Control
## Простой линейный график: несколько серий, оси, сетка и легенда.
## Серия: {name: String, color: Color, points: PackedVector2Array (x — год, y — значение)}.

var series: Array[Dictionary] = []
var y_format := "%.0f"
var _font: Font
## Плавный масштаб: максимум оси y «доезжает» до нового значения.
var _shown := Vector3(-1, -1, -1)
var _goal := Vector3.ZERO


func _ready() -> void:
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(480, 330)


func set_series(new_series: Array[Dictionary]) -> void:
	series = new_series
	queue_redraw()


func _process(delta: float) -> void:
	if _shown.x < 0.0 or _shown.is_equal_approx(_goal):
		return
	_shown = _shown.lerp(_goal, SmoothSettings.factor(8.0, delta)) if SmoothSettings.ui_anim else _goal
	if _shown.distance_to(_goal) < maxf(0.001, _goal.z * 0.001):
		_shown = _goal
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2(56, 10), size - Vector2(70, 60))
	draw_rect(rect, Color(0.04, 0.05, 0.07, 0.6))
	var x_min := INF
	var x_max := -INF
	var y_max := 0.0
	for s in series:
		for p in s.points:
			x_min = minf(x_min, p.x)
			x_max = maxf(x_max, p.x)
			y_max = maxf(y_max, p.y)
	if x_min == INF or x_max <= x_min or y_max <= 0.0:
		draw_string(_font, rect.position + Vector2(10, 24), "Пока мало данных — история пишется каждые %d лет." % World.HISTORY_STEP,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.72, 0.8))
		return
	_goal = Vector3(x_min, x_max, y_max)
	if _shown.x < 0.0 or not SmoothSettings.ui_anim:
		_shown = _goal
	# Ось x — точно (точки не выходят за край), ось y «доезжает»: график не прыгает.
	y_max = maxf(_shown.z, y_max * 0.999) if _shown.z < y_max else _shown.z
	# Сетка и подписи осей.
	for k in 5:
		var t := k / 4.0
		var y := rect.end.y - rect.size.y * t
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(1, 1, 1, 0.08))
		draw_string(_font, Vector2(4, y + 4), _fmt(y_max * t), HORIZONTAL_ALIGNMENT_LEFT, 50, 11, Color(0.7, 0.72, 0.8))
		var x := rect.position.x + rect.size.x * t
		draw_string(_font, Vector2(x - 18, rect.end.y + 16), "%d" % roundi(lerpf(x_min, x_max, t)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.72, 0.8))
	for s in series:
		var pts := PackedVector2Array()
		for p in s.points:
			pts.append(Vector2(rect.position.x + (p.x - x_min) / (x_max - x_min) * rect.size.x,
					rect.end.y - p.y / y_max * rect.size.y))
		if pts.size() >= 2:
			draw_polyline(pts, s.color, 2.0, true)
	# Легенда в две колонки под графиком.
	var lx := rect.position.x
	var ly := rect.end.y + 34
	for i in series.size():
		var s: Dictionary = series[i]
		var pos := Vector2(lx + (i % 4) * (rect.size.x / 4.0), ly + (i / 4) * 16)
		draw_rect(Rect2(pos + Vector2(0, -9), Vector2(10, 10)), s.color)
		draw_string(_font, pos + Vector2(14, 0), s.name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x / 4.0 - 16, 11, Color(0.85, 0.87, 0.92))


func _fmt(v: float) -> String:
	if v >= 1_000_000.0:
		return "%.1fм" % (v / 1_000_000.0)
	if v >= 1000.0:
		return "%.0fк" % (v / 1000.0)
	return y_format % v
