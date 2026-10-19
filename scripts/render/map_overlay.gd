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
## Как часто (мс) перерисовывать подписи во время симуляции.
const REDRAW_INTERVAL_MS := 150

@export var renderer: MapRenderer

var _font: Font
var _last_zoom := -1.0
var _last_cam_pos := Vector2.INF
var _mode := MapMode.POLITICAL
var _selected := -1
var _world_dirty := false
var _selected_hero := -1
var _last_redraw_ms := 0


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
	EventBus.year_passed.connect(func(_y: int) -> void: _world_dirty = true)
	EventBus.hero_selected.connect(func(id: int) -> void:
		_selected_hero = id
		queue_redraw())


func _process(_delta: float) -> void:
	var zoom := _camera_zoom()
	var cam := get_viewport().get_camera_2d()
	var cam_pos := cam.position if cam != null else Vector2.ZERO
	# Подписи отсекаются по видимой области — при сдвиге камеры перерисовываем.
	if not is_equal_approx(zoom, _last_zoom) or not cam_pos.is_equal_approx(_last_cam_pos):
		_last_zoom = zoom
		_last_cam_pos = cam_pos
		queue_redraw()
	# Мир изменился — пересчитываем точки подписей и перерисовываем, но не каждый кадр.
	var now := Time.get_ticks_msec()
	if _world_dirty and now - _last_redraw_ms >= REDRAW_INTERVAL_MS and WorldState.world != null:
		_world_dirty = false
		_last_redraw_ms = now
		WorldState.world.update_label_anchors()
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
	if political or _mode == MapMode.BIOMES or _mode == MapMode.POPULATION or _mode == MapMode.RESOURCES:
		_draw_region_labels(world, zoom)
		_draw_cities(world, zoom)
		_draw_sieges(world, zoom)
		_draw_heroes(world, zoom)
	draw_set_transform(Vector2.ZERO)


func _draw_nation_labels(world: World, zoom: float) -> void:
	for nation in world.nations:
		if not nation.alive or nation.label_cell < 0 or nation.cell_count <= 0:
			continue
		# Размер подписи растёт с площадью страны.
		var world_size := clampf(sqrt(nation.cell_count) * MapRenderer.CELL_SIZE * 0.25, 8.0, 110.0)
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


## Размер значка (радиус, пиксели экрана) по уровню города: деревня … великий город.
const TIER_RADIUS: Array[float] = [2.2, 3.4, 4.6, 6.0, 7.5]
## С какого зума видно название города данного уровня.
const TIER_LABEL_ZOOM: Array[float] = [3.2, 2.2, 1.5, 1.0, 0.7]
const TIER_FONT: Array[int] = [10, 11, 12, 14, 16]
## С какого зума видны названия регионов.
const REGION_LABEL_ZOOM := 2.0


func _draw_cities(world: World, zoom: float) -> void:
	# Значки — постоянного размера на экране, но мельче на очень общем плане.
	var marker_scale := clampf(zoom * 0.9, 0.5, 1.0)
	var inv := Vector2.ONE / zoom
	var view := _visible_rect().grow(40.0 / zoom)
	var dark := Color(0.06, 0.06, 0.08)
	for city in world.cities:
		if not city.alive:
			continue
		var pos := renderer.cell_center(city.cell)
		if not view.has_point(pos):
			continue
		var nation := world.nations[city.nation_id]
		var tier := city.tier()
		draw_set_transform(pos, 0.0, inv)
		var r := TIER_RADIUS[tier] * marker_scale
		var fill := nation.color.lightened(0.35)
		if city.is_capital:
			r = (9.0 + tier * 1.2) * marker_scale
			draw_circle(Vector2.ZERO, r + 1.5, dark)
			draw_circle(Vector2.ZERO, r, nation.color.lightened(0.15))
			var icon := nation.race.icon
			if icon != null:
				var s := r * 1.5
				draw_texture_rect(icon, Rect2(-s * 0.5, -s * 0.5, s, s), false)
			if city.nation_id == _selected:
				draw_arc(Vector2.ZERO, r + 4.0, 0.0, TAU, 32, Color.WHITE, 2.0)
		elif tier >= 3:
			# Крупные города — «крепостной» квадрат, великие — ещё и с кольцом.
			draw_rect(Rect2(-r - 1.5, -r - 1.5, (r + 1.5) * 2.0, (r + 1.5) * 2.0), dark)
			draw_rect(Rect2(-r, -r, r * 2.0, r * 2.0), fill)
			draw_rect(Rect2(-r * 0.4, -r * 0.4, r * 0.8, r * 0.8), dark.lightened(0.2))
			if tier == 4:
				draw_arc(Vector2.ZERO, r * 1.75, 0.0, TAU, 24, fill, 1.5)
		elif tier == 2:
			draw_circle(Vector2.ZERO, r + 1.3, dark)
			draw_circle(Vector2.ZERO, r, fill)
			draw_circle(Vector2.ZERO, r * 0.4, dark.lightened(0.2))
		else:
			draw_circle(Vector2.ZERO, r + 1.0, dark)
			draw_circle(Vector2.ZERO, r, fill.darkened(0.1 if tier == 0 else 0.0))
		if zoom >= TIER_LABEL_ZOOM[tier] or (city.is_capital and zoom >= 1.2):
			var font_size := TIER_FONT[tier] + (1 if city.is_capital else 0)
			var text_size := _font.get_string_size(city.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var origin := Vector2(-text_size.x * 0.5, r + 3.0 + font_size)
			var text_color := Color(1, 1, 0.95) if tier >= 2 else Color(0.88, 0.88, 0.84)
			draw_string_outline(_font, origin, city.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.05, 0.05, 0.08, 0.85))
			draw_string(_font, origin, city.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


## Названия регионов — курсивом под городами, только при приближении.
func _draw_region_labels(world: World, zoom: float) -> void:
	if zoom < REGION_LABEL_ZOOM:
		return
	var alpha := clampf((zoom - REGION_LABEL_ZOOM) / 1.0, 0.0, 1.0) * 0.7
	var view := _visible_rect()
	var inv := Vector2.ONE / zoom
	for region in world.regions:
		if region.name.is_empty() or region.cells.size() < 12:
			continue
		var pos := renderer.cell_center(region.center)
		if not view.has_point(pos) or world.city_cell[region.center] >= 0:
			continue
		var text := region.name
		var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		draw_set_transform(pos, 0.0, inv)
		draw_string_outline(_font, Vector2(-size.x * 0.5, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0.05, 0.05, 0.08, alpha * 0.8))
		draw_string(_font, Vector2(-size.x * 0.5, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.92, 0.8, alpha))


## Скрещённые мечи над осаждёнными регионами + дуга прогресса осады.
func _draw_sieges(world: World, zoom: float) -> void:
	var inv := Vector2.ONE / zoom
	var scale := clampf(zoom, 0.6, 1.2)
	for war in world.diplomacy.wars:
		if war.siege_region < 0:
			continue
		var region := world.regions[war.siege_region]
		var target := region.center
		for c in region.cells:
			if world.city_cell[c] >= 0:
				target = c
				break
		var pos := renderer.cell_center(target)
		draw_set_transform(pos + Vector2(0, -16.0 / zoom), 0.0, inv)
		var r := 8.0 * scale
		var dark := Color(0.05, 0.05, 0.08, 0.9)
		draw_circle(Vector2.ZERO, r + 4.0, dark)
		for d in [Vector2(1, 1), Vector2(1, -1)]:
			draw_line(-d * r * 0.8, d * r * 0.8, Color(0.95, 0.92, 0.85), 2.5 * scale)
			# Гарды мечей.
			var guard: Vector2 = d * r * 0.35
			var perp := Vector2(-d.y, d.x) * r * 0.3
			draw_line(guard - perp, guard + perp, Color(0.95, 0.75, 0.3), 2.0 * scale)
		draw_arc(Vector2.ZERO, r + 4.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(war.siege_progress, 0.0, 1.0), 24,
				Color(0.95, 0.3, 0.25), 2.5 * scale)


## Герои — ромбы цвета класса; у присягнувших — кольцо цвета их государства.
func _draw_heroes(world: World, zoom: float) -> void:
	var inv := Vector2.ONE / zoom
	var view := _visible_rect()
	var scale := clampf(zoom, 0.7, 1.2)
	for hero in world.heroes:
		if not hero.alive or hero.is_ruler or hero.cell < 0:
			continue
		var pos := renderer.cell_center(hero.cell)
		if not view.has_point(pos):
			continue
		draw_set_transform(pos, 0.0, inv)
		var r := (5.0 + minf(hero.level, 15) * 0.25) * scale
		var diamond := PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
		if hero.nation_id >= 0:
			draw_circle(Vector2.ZERO, r + 3.0, world.nations[hero.nation_id].color)
		draw_colored_polygon(PackedVector2Array([Vector2(0, -r - 1.5), Vector2(r + 1.5, 0), Vector2(0, r + 1.5), Vector2(-r - 1.5, 0)]), Color(0.05, 0.05, 0.08))
		draw_colored_polygon(diamond, hero.hero_class.color)
		if hero.id == _selected_hero:
			draw_arc(Vector2.ZERO, r + 6.0, 0.0, TAU, 24, Color.WHITE, 2.0)
		if zoom >= 1.8 or hero.id == _selected_hero:
			var text := "%s, %s %d" % [hero.display_name(), hero.hero_class.display_name.to_lower(), hero.level]
			var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_string_outline(_font, Vector2(-size.x * 0.5, -r - 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0.05, 0.05, 0.08, 0.85))
			draw_string(_font, Vector2(-size.x * 0.5, -r - 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.92, 0.6))


## Видимая часть мира (в мировых координатах).
func _visible_rect() -> Rect2:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	return inv * get_viewport_rect()
