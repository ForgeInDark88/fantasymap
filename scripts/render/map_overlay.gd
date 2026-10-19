class_name MapOverlay
extends Node2D
## Значки городов и подписи поверх карты (рисуются через _draw).
##
## Названия государств живут в «мировом» масштабе (крупнее у больших стран,
## как на бумажной карте), значки и названия городов — постоянного размера
## на экране и появляются при приближении.

## Зум, начиная с которого видны названия городов.
const CITY_LABEL_ZOOM := 1.4
## Базовый размер шрифта, относительно которого масштабируются подписи стран.
const NATION_FONT := 48

@export var renderer: MapRenderer

var _font: Font
var _last_zoom := -1.0
var _mode := MapMode.POLITICAL
var _selected := -1


func _ready() -> void:
	_font = ThemeDB.fallback_font
	z_index = 1
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void:
		_selected = -1
		queue_redraw())
	EventBus.map_mode_changed.connect(func(m: int) -> void:
		_mode = m
		queue_redraw())
	EventBus.nation_selected.connect(func(id: int) -> void:
		_selected = id
		queue_redraw())


func _process(_delta: float) -> void:
	var zoom := _camera_zoom()
	if not is_equal_approx(zoom, _last_zoom):
		_last_zoom = zoom
		queue_redraw()


func _camera_zoom() -> float:
	var cam := get_viewport().get_camera_2d()
	return cam.zoom.x if cam != null else 1.0


func _draw() -> void:
	var world := WorldState.world
	if world == null or renderer == null or renderer.map == null:
		return
	var zoom := _camera_zoom()
	var political := _mode == MapMode.POLITICAL or _mode == MapMode.RACES
	if political:
		_draw_nation_labels(world, zoom)
	if political or _mode == MapMode.BIOMES:
		_draw_cities(world, zoom)
	draw_set_transform(Vector2.ZERO)


func _draw_nation_labels(world: World, zoom: float) -> void:
	for nation in world.nations:
		if not nation.alive or nation.label_cell < 0 or nation.cell_count <= 0:
			continue
		# Размер подписи растёт с площадью страны.
		var world_size := clampf(sqrt(nation.cell_count) * MapRenderer.CELL_SIZE * 0.32, 8.0, 140.0)
		var screen_size := world_size * zoom
		if screen_size < 9.0 or screen_size > 56.0:
			continue
		# Проявляется при отдалении, гаснет при сильном приближении (там важнее города).
		var alpha := clampf((screen_size - 9.0) / 6.0, 0.0, 1.0) * clampf((56.0 - screen_size) / 20.0, 0.0, 1.0)
		var text := nation.short_name.to_upper()
		var scale := world_size / NATION_FONT
		var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NATION_FONT)
		var pos := renderer.cell_center(nation.label_cell)
		# Если подпись легла на столицу — поднимаем её над значком.
		if nation.capital_city >= 0:
			var cap_pos := renderer.cell_center(world.cities[nation.capital_city].cell)
			var marker := 14.0 / zoom
			if absf(pos.y - cap_pos.y) < world_size * 0.5 + marker and absf(pos.x - cap_pos.x) < text_size.x * scale * 0.5 + marker:
				pos.y = cap_pos.y - marker - world_size * 0.45
		draw_set_transform(pos, 0.0, Vector2.ONE * scale)
		var origin := Vector2(-text_size.x * 0.5, NATION_FONT * 0.35)
		var outline := Color(0.05, 0.05, 0.08, 0.75 * alpha)
		draw_string_outline(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NATION_FONT, 10, outline)
		var col := nation.color.lightened(0.55)
		col.a = 0.95 * alpha
		draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NATION_FONT, col)


func _draw_cities(world: World, zoom: float) -> void:
	# Значки — постоянного размера на экране, но мельче на очень общем плане.
	var marker_scale := clampf(zoom * 0.9, 0.45, 1.0)
	var show_labels := zoom >= CITY_LABEL_ZOOM
	var inv := Vector2.ONE / zoom
	for city in world.cities:
		if not city.alive:
			continue
		var nation := world.nations[city.nation_id]
		var pos := renderer.cell_center(city.cell)
		draw_set_transform(pos, 0.0, inv)
		var highlighted := city.nation_id == _selected
		if city.is_capital:
			var r := 10.0 * marker_scale
			draw_circle(Vector2.ZERO, r + 1.5, Color(0.06, 0.06, 0.08))
			draw_circle(Vector2.ZERO, r, nation.color.lightened(0.15))
			var icon := nation.race.icon
			if icon != null:
				var s := r * 1.5
				draw_texture_rect(icon, Rect2(-s * 0.5, -s * 0.5, s, s), false)
			if highlighted:
				draw_arc(Vector2.ZERO, r + 4.0, 0.0, TAU, 32, Color.WHITE, 2.0)
		else:
			var r := 4.5 * marker_scale
			draw_circle(Vector2.ZERO, r + 1.5, Color(0.06, 0.06, 0.08))
			draw_circle(Vector2.ZERO, r, nation.color.lightened(0.35))
		if show_labels:
			var font_size := 14 if city.is_capital else 12
			var text_size := _font.get_string_size(city.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var origin := Vector2(-text_size.x * 0.5, (14.0 if city.is_capital else 9.0) * marker_scale + font_size)
			draw_string_outline(_font, origin, city.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.05, 0.05, 0.08, 0.85))
			draw_string(_font, origin, city.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 0.95))
