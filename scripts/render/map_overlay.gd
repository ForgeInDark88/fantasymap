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
	var map_like := political or _mode == MapMode.BIOMES or _mode == MapMode.POPULATION or _mode == MapMode.RESOURCES \
			or MapMode.is_region_mode(_mode) or _mode == MapMode.TRADE
	if _mode == MapMode.UNDERGROUND:
		_draw_caves(world, zoom)
		_draw_cities(world, zoom)
	if map_like:
		_draw_scars(world, zoom)
		_draw_roads(world, zoom)
		_draw_ruins(world, zoom)
		_draw_titan(world, zoom)
	if map_like:
		_draw_region_labels(world, zoom)
		_draw_cities(world, zoom)
		_draw_sieges(world, zoom)
		_draw_landmarks(world, zoom)
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


const SCAR_COLORS := {"ash": Color(0.35, 0.33, 0.33, 0.45), "flood": Color(0.3, 0.55, 0.95, 0.4),
	"fire": Color(0.85, 0.35, 0.15, 0.4), "drought": Color(0.85, 0.7, 0.35, 0.35)}


## Следы бедствий (пепел, затопления, гари, засуха) и вулканы.
func _draw_scars(world: World, zoom: float) -> void:
	draw_set_transform(Vector2.ZERO)
	for s in world.scars:
		var pos := renderer.cell_center(int(s.cell))
		var col: Color = SCAR_COLORS.get(s.kind, Color(0.5, 0.5, 0.5, 0.3))
		var left := clampf((int(s.until) - world.year) / 5.0, 0.25, 1.0)
		col.a *= left
		var r: float = s.radius * MapRenderer.CELL_SIZE
		draw_circle(pos, r, col)
		draw_arc(pos, r, 0.0, TAU, 32, Color(col, minf(1.0, col.a * 1.6)), 1.5 / zoom)
	if zoom < 0.6:
		return
	var inv := Vector2.ONE / zoom
	for v in world.volcanoes:
		var pos := renderer.cell_center(v)
		draw_set_transform(pos, 0.0, inv)
		var hot := world.ash_until > world.year
		var pts := PackedVector2Array([Vector2(-6, 4), Vector2(0, -6), Vector2(6, 4)])
		draw_colored_polygon(pts, Color(0.45, 0.2, 0.15) if not hot else Color(0.9, 0.3, 0.1))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.08, 0.06, 0.06), 1.5)
		draw_circle(Vector2(0, -6), 1.8, Color(1.0, 0.55, 0.2))
	draw_set_transform(Vector2.ZERO)


const CAVE_COLORS := {&"cavern": Color(0.6, 0.55, 0.5), &"mithril": Color(0.75, 0.9, 1.0), &"gems": Color(0.85, 0.4, 0.9),
	&"lair": Color(0.85, 0.25, 0.2), &"ruins": Color(0.85, 0.75, 0.45)}


## Подземный мир: ходы (чем глубже — тем темнее), узлы по виду и хозяину, входы.
func _draw_caves(world: World, zoom: float) -> void:
	draw_set_transform(Vector2.ZERO)
	for c in world.caves:
		var pa := renderer.cell_center(c.cell)
		for nb in c.neighbors:
			if nb < c.id:
				continue
			var o := world.caves[nb]
			var shade := 0.85 - 0.12 * maxf(c.depth, o.depth)
			draw_line(pa, renderer.cell_center(o.cell), Color(shade, shade * 0.85, shade * 0.6, 0.8), 2.0 / zoom, true)
	var inv := Vector2.ONE / zoom
	for c in world.caves:
		draw_set_transform(renderer.cell_center(c.cell), 0.0, inv)
		var r := 4.0 + 2.0 * c.depth
		var fill: Color = CAVE_COLORS.get(c.kind, Color.GRAY)
		draw_circle(Vector2.ZERO, r + 2.0, Color(0.05, 0.04, 0.04))
		draw_circle(Vector2.ZERO, r, fill)
		if c.owner >= 0:
			draw_arc(Vector2.ZERO, r + 3.0, 0.0, TAU, 20, world.nations[c.owner].color.lightened(0.2), 2.5)
		if c.city:
			draw_rect(Rect2(-r * 0.45, -r * 0.45, r * 0.9, r * 0.9), Color(1, 0.95, 0.8))
		if c.entrance:
			draw_arc(Vector2(0, -r - 5.0), 4.0, PI, TAU, 10, Color(0.95, 0.9, 0.8), 2.0)
		if zoom >= 1.5:
			var text := c.name
			var size := 11
			var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			draw_string_outline(_font, Vector2(-w * 0.5, r + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
			draw_string(_font, Vector2(-w * 0.5, r + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.95, 0.92, 0.85))
	draw_set_transform(Vector2.ZERO)


## Титан мирового кризиса — огромная тень с пылающими глазами.
func _draw_titan(world: World, zoom: float) -> void:
	if world.crisis.is_empty() or int(world.crisis.get("titan_cell", -1)) < 0:
		return
	var pos := renderer.cell_center(int(world.crisis.titan_cell))
	draw_set_transform(pos, 0.0, Vector2.ONE / zoom)
	var r := clampf(14.0 * zoom, 14.0, 30.0)
	draw_circle(Vector2.ZERO, r + 3.0, Color(0.05, 0.03, 0.03, 0.9))
	draw_circle(Vector2.ZERO, r, Color(0.45, 0.12, 0.08))
	draw_circle(Vector2(-r * 0.35, -r * 0.15), r * 0.16, Color(1.0, 0.7, 0.2))
	draw_circle(Vector2(r * 0.35, -r * 0.15), r * 0.16, Color(1.0, 0.7, 0.2))
	var label := str(world.crisis.titan_name)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string_outline(_font, Vector2(-w * 0.5, r + 16.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
	draw_string(_font, Vector2(-w * 0.5, r + 16.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.75, 0.55))
	draw_set_transform(Vector2.ZERO)


## Руины: обломок колонны (исчерпанные — бледнее, проклятые — с лиловым ореолом).
func _draw_ruins(world: World, zoom: float) -> void:
	if zoom < 0.9:
		return
	var view := _visible_rect().grow(20.0 / zoom)
	var inv := Vector2.ONE / zoom
	for r in world.ruins:
		if r.cell < 0 or r.revived:
			continue
		var pos := renderer.cell_center(r.cell)
		if not view.has_point(pos):
			continue
		draw_set_transform(pos, 0.0, inv)
		var a := 0.45 if r.depleted() else 0.95
		if r.cursed:
			draw_circle(Vector2.ZERO, 8.0, Color(0.6, 0.3, 0.8, 0.35))
		var stone := Color(0.78, 0.74, 0.68, a)
		var dark := Color(0.08, 0.07, 0.06, a)
		draw_rect(Rect2(-5.5, 3.0, 11.0, 3.0), dark)
		draw_rect(Rect2(-4.5, 3.5, 9.0, 2.0), stone)
		draw_rect(Rect2(-4.0, -5.0, 3.0, 8.0), stone)
		draw_rect(Rect2(1.0, -2.0, 3.0, 5.0), stone)
		if r.kind == &"tomb":
			draw_rect(Rect2(-1.0, -9.0, 2.0, 5.0), stone)
			draw_rect(Rect2(-3.0, -7.5, 6.0, 1.6), stone)
	draw_set_transform(Vector2.ZERO)


## Дороги и морские пути — линии между городами. Подробность по зуму: на
## общем плане — только пути между крупными городами; в режиме «Торговля» —
## все, толщина по обороту.
func _draw_roads(world: World, zoom: float) -> void:
	var trade := _mode == MapMode.TRADE
	if not trade and zoom < 0.7:
		return
	var view := _visible_rect().grow(60.0 / zoom)
	var max_traffic := 1.0
	if trade:
		for r in world.roads:
			if r.alive:
				max_traffic = maxf(max_traffic, r.traffic)
	draw_set_transform(Vector2.ZERO)
	for r in world.roads:
		if not r.alive:
			continue
		var ca := world.cities[r.a]
		var cb := world.cities[r.b]
		if not ca.alive or not cb.alive:
			continue
		if not trade and zoom < 1.4 and (ca.tier() < 2 or cb.tier() < 2):
			continue
		var pa := renderer.cell_center(ca.cell)
		var pb := renderer.cell_center(cb.cell)
		if not view.has_point(pa) and not view.has_point(pb):
			continue
		var px := 1.2
		var col := Color(0.82, 0.72, 0.5, 0.75)
		if r.sea:
			col = Color(0.55, 0.78, 0.95, 0.7)
		if trade:
			var k := sqrt(r.traffic / max_traffic)
			px = 1.0 + 4.0 * k
			col = Color(0.95, 0.75, 0.3, 0.45 + 0.5 * k) if not r.sea else Color(0.5, 0.8, 1.0, 0.45 + 0.5 * k)
			if r.safety < 0.6:
				col = col.lerp(Color(0.9, 0.3, 0.25, col.a), 0.6)  # разбой и пираты
		if r.sea:
			draw_dashed_line(pa, pb, col, px / zoom, 6.0 / zoom)
		else:
			draw_line(pa, pb, col, px / zoom, true)


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
	for hero in world.wandering_heroes():
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
		if hero.id == world.player:
			draw_arc(Vector2.ZERO, r + 9.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.3), 2.5)
		if zoom >= 1.8 or hero.id == _selected_hero or hero.id == world.player:
			var text := "%s, %s %d" % [hero.display_name(), hero.hero_class.display_name.to_lower(), hero.level]
			var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_string_outline(_font, Vector2(-size.x * 0.5, -r - 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0.05, 0.05, 0.08, 0.85))
			draw_string(_font, Vector2(-size.x * 0.5, -r - 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.92, 0.6))


## Источники силы, Врата бездны, пустые троны, чудеса света.
func _draw_landmarks(world: World, zoom: float) -> void:
	var inv := Vector2.ONE / zoom
	var view := _visible_rect()
	var scale := clampf(zoom, 0.7, 1.3)
	var t := Time.get_ticks_msec() / 1000.0
	var dark := Color(0.05, 0.05, 0.08)
	for lm in world.landmarks:
		var pos := renderer.cell_center(lm.cell)
		if not view.has_point(pos):
			continue
		draw_set_transform(pos, 0.0, inv)
		var r := 9.0 * scale
		match lm.kind:
			&"source":
				var col := Color(0.4, 1.0, 0.95) if lm.active else Color(0.4, 0.5, 0.5)
				for k in 8:
					var a := k * TAU / 8.0 + t * 0.3
					draw_line(Vector2.from_angle(a) * r * 0.9, Vector2.from_angle(a) * r * 1.7, Color(col, 0.7), 2.0)
				draw_circle(Vector2.ZERO, r + 1.5, dark)
				draw_circle(Vector2.ZERO, r, col)
				draw_circle(Vector2.ZERO, r * 0.45, Color.WHITE)
			&"portal":
				var col := Color(0.9, 0.15, 0.1) if lm.active else Color(0.4, 0.3, 0.3)
				draw_circle(Vector2.ZERO, r + 2.0, dark)
				draw_circle(Vector2.ZERO, r, Color(0.25, 0.0, 0.05))
				for k in 3:
					var a := t * 1.5 + k * TAU / 3.0
					draw_arc(Vector2.ZERO, r * (0.4 + 0.2 * k), a, a + PI * 1.2, 16, col, 2.0)
			&"throne":
				var col := Color(0.75, 0.6, 0.25) if lm.active else Color(0.4, 0.38, 0.35)
				var w := r * 0.9
				draw_rect(Rect2(-w - 1.5, -r * 1.3 - 1.5, w * 2 + 3, r * 2.4 + 3), dark)
				draw_rect(Rect2(-w, -r * 1.3, w * 2, r * 1.0), col)          # спинка
				draw_rect(Rect2(-w, -r * 0.2, w * 2, r * 0.5), col.darkened(0.2))  # сиденье
				draw_rect(Rect2(-w, r * 0.3, w * 0.4, r * 0.8), col)          # ножки
				draw_rect(Rect2(w * 0.6, r * 0.3, w * 0.4, r * 0.8), col)
				if lm.active:
					draw_circle(Vector2(0, -r * 0.8), r * 0.25, Color(0.9, 0.2, 0.2))
			&"wonder":
				var pts := PackedVector2Array()
				for k in 10:
					var rr := r * (1.3 if k % 2 == 0 else 0.55)
					pts.append(Vector2.from_angle(-PI / 2 + k * TAU / 10.0) * rr)
				draw_colored_polygon(pts, Color(1.0, 0.85, 0.3))
				draw_polyline(pts + PackedVector2Array([pts[0]]), dark, 1.5)
		if zoom >= 1.2:
			var text := lm.name
			var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_string_outline(_font, Vector2(-size.x * 0.5, r * 1.6 + 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0.05, 0.05, 0.08, 0.85))
			draw_string(_font, Vector2(-size.x * 0.5, r * 1.6 + 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.92, 0.75))


## Видимая часть мира (в мировых координатах).
func _visible_rect() -> Rect2:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	return inv * get_viewport_rect()
