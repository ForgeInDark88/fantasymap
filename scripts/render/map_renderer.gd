class_name MapRenderer
extends Node2D
## Отображение карты: базовая текстура (1 тексель = 1 клетка) на Sprite2D
## + шейдер политического слоя (владельцы клеток, границы, выделение).
##
## Почему не TileMapLayer: карта 384×240 — это ~92 тыс. клеток, а при
## симуляции владельцы клеток меняются каждый «год». Перестраивать TileMap
## на 100+ тыс. ячеек дорого по времени и памяти; здесь же база рисуется
## один раз, а смена границ — это загрузка одной текстуры owner_tex
## (World.owner_texels) без циклов в GDScript. Заливку и контуры считает шейдер.

## Размер базовой клетки в мировых единицах и текущей клетки сетки: при
## масштабе сетки (GridScale) клетка мельче, а мир на экране тот же.
const BASE_CELL_SIZE := 4.0
## Порог появления границ регионов (пикселей на базовую клетку; шейдер, region_min_px).
const REGION_MIN_PX := 2.5
static var cell_size := BASE_CELL_SIZE
const SHADER := preload("res://scripts/render/political_map.gdshader")
const PALETTE_WIDTH := 256

var world: World
var map: WorldMap
var mode := MapMode.POLITICAL
var selected_nation := -1

var _sprite: Sprite2D
var _material: ShaderMaterial
var _base_texture: ImageTexture
var _painted_base_mode := -1
var _owner_texture: ImageTexture
var _owner_version := -1
var _nation_palette: ImageTexture
var _race_palette: ImageTexture
## Когда последний раз перерисовывали «живой» режим (население), мс.
var _dynamic_painted_ms := 0
## Перерисовывать «живые» режимы не чаще (мс): это проход по всем клеткам в GDScript.
const DYNAMIC_REPAINT_MS := 1500
var _region_texture: ImageTexture
var _terrain_version := 0
## Палитра регионов для режимов «Религии», «Культура» (обновляется раз в REGION_PALETTE_MS).
var _region_palette: ImageTexture
var _region_palette_ms := -100000
const REGION_PALETTE_MS := 700

# --- Плавность (только отображение; симуляцию не трогает) ---
## Переход границ: длительность (с), прежние владельцы (что сейчас на экране).
const BORDER_TIME := 0.5
## Скорость, начиная с которой границы меняются мгновенно (индекс WorldState.SPEEDS).
const INSTANT_SPEED := 5
var _prev_texture: ImageTexture
var _shown_texels := PackedByteArray()
var _blend := 1.0
var _pending_owner := false
var _pending_since_ms := 0
## Кроссфейд режима карты: спрайт с прежней картинкой гаснет за MODE_FADE с.
const MODE_FADE := 0.25
var _fade_sprite: Sprite2D
var _fade_tween: Tween
## Оттенок эпохи и кризиса: текущий и целевой, пересчёт цели раз в TINT_MS.
const TINT_K := 0.8
const TINT_MS := 500
var _tint := Color(1, 1, 1, 0)
var _tint_target := Color(1, 1, 1, 0)
var _tint_ms := 0
## Оттенки кризисов (id CrisisDef) и пепельной зимы.
const CRISIS_TINT := {&"great_plague": Color(0.6, 0.8, 0.5, 0.16), &"ice_age": Color(0.75, 0.88, 1.05, 0.24),
	&"horde": Color(1.05, 0.6, 0.45, 0.14), &"titan": Color(0.95, 0.55, 0.45, 0.14), &"great_drought": Color(1.1, 0.9, 0.55, 0.18),
	&"star_fall": Color(0.85, 0.7, 1.05, 0.14), &"gods_war": Color(1.1, 0.95, 0.65, 0.14)}
const ASH_TINT := Color(0.7, 0.75, 0.85, 0.22)


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * cell_size
	# Пиксельная чёткость при приближении, мип-карты — без «ряби» при отдалении.
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_sprite.material = _material
	add_child(_sprite)
	_fade_sprite = Sprite2D.new()
	_fade_sprite.centered = false
	_fade_sprite.scale = _sprite.scale
	_fade_sprite.texture_filter = _sprite.texture_filter
	_fade_sprite.visible = false
	add_child(_fade_sprite)
	EventBus.world_generated.connect(_on_world_generated)
	EventBus.map_mode_changed.connect(set_mode)
	EventBus.nation_selected.connect(_on_nation_selected)


func _process(delta: float) -> void:
	_animate(delta)
	# Границы обновляются не чаще раза за кадр, сколько бы тиков ни прошло.
	if world != null and world.terrain_version != _terrain_version:
		# Рельеф изменён панелью Бога: перерисовать базу и обновить регионы.
		_terrain_version = world.terrain_version
		_painted_base_mode = -1
		_upload_regions()
		redraw()
	if world != null and world.ownership_version != _owner_version:
		_owner_changed()
	if world != null and MapMode.is_region_mode(mode) and Time.get_ticks_msec() - _region_palette_ms > REGION_PALETTE_MS:
		refresh_region_palette()
	if world != null and MapMode.is_dynamic(mode) and _painted_base_mode == mode:
		_repaint_dynamic()


## Перерисовка динамического режима полосами (этап 12.D): не дольше
## DYNAMIC_SLICE_MS за кадр в свой буфер; проход кончился — одна заливка
## текстуры. Новый проход — не чаще DYNAMIC_REPAINT_MS и только когда время идёт.
const DYNAMIC_SLICE_MS := 4
var _dyn_colors := PackedInt32Array()
var _dyn_pos := -1


func _repaint_dynamic() -> void:
	var n := map.cell_count()
	if _dyn_pos < 0:
		if Time.get_ticks_msec() - _dynamic_painted_ms <= DYNAMIC_REPAINT_MS or WorldState.speed_index <= 0:
			return
		if _dyn_colors.size() != n:
			_dyn_colors.resize(n)
		_dyn_pos = 0
	var t0 := Time.get_ticks_usec()
	var rows := maxi(1, 16384 / map.width)
	while _dyn_pos < n and Time.get_ticks_usec() - t0 < DYNAMIC_SLICE_MS * 1000:
		var to := mini(n, _dyn_pos + rows * map.width)
		MapPainter.paint_dynamic_rows(world, mode, _dyn_colors, _dyn_pos, to)
		_dyn_pos = to
	if _dyn_pos < n:
		return
	_dyn_pos = -1
	_dynamic_painted_ms = Time.get_ticks_msec()
	var img := Image.create_from_data(map.width, map.height, false, Image.FORMAT_RGBA8, _dyn_colors.to_byte_array())
	img.generate_mipmaps()
	if _base_texture != null and Vector2i(_base_texture.get_size()) == img.get_size() and not _fade_sprite.visible:
		_base_texture.update(img)


func set_mode(new_mode: int) -> void:
	if new_mode == mode:
		return
	_start_mode_fade()
	_dyn_pos = -1
	mode = new_mode
	if MapMode.is_region_mode(mode):
		refresh_region_palette()
	redraw()


const DANGER_LOW := Color(1.0, 0.85, 0.3)
const DANGER_HIGH := Color(0.75, 0.05, 0.1)


## Цвет каждого региона в режимах по регионам: вера большинства (альфа — её доля).
func refresh_region_palette() -> void:
	if world == null:
		return
	_region_palette_ms = Time.get_ticks_msec()
	var colors := PackedColorArray()
	colors.resize(world.regions.size())
	var danger := LairSystem.danger_map(world) if mode == MapMode.DANGER else PackedFloat32Array()
	for region in world.regions:
		var c := Color(0, 0, 0, 0)
		match mode:
			MapMode.RELIGION:
				var r := region.main_faith()
				if r >= 0:
					c = world.religions[r].color
					c.a = 0.35 + 0.65 * region.faith[r]
			MapMode.CULTURE:
				if region.culture >= 0:
					c = world.cultures[region.culture].color
					# Культура владельца — ярко, чужая (ассимилируется) — бледнее.
					var ctrl := region.controller()
					c.a = 0.9 if ctrl < 0 or world.nations[ctrl].culture == region.culture else 0.45 + 0.3 * region.assim
			MapMode.DANGER:
				# Тихо — прозрачно; опасно — от жёлтого к багровому.
				var d := danger[region.id]
				if d > 0.0:
					c = DANGER_LOW.lerp(DANGER_HIGH, d)
					c.a = 0.25 + 0.65 * d
			MapMode.GOODS:
				# Главный товар края (по стоимости); бледнее — ничьи края.
				var gi := MarketSystem.main_good(world, region.id)
				if gi >= 0:
					c = (MarketDB.all()[gi] as GoodDef).color
					c.a = 0.85 if region.controller() >= 0 else 0.4
			MapMode.LANGUAGE:
				if region.language >= 0:
					c = world.languages[region.language].color
					var ctrl := region.controller()
					c.a = 0.9 if ctrl < 0 or world.nations[ctrl].language == region.language else 0.45 + 0.3 * region.lang_assim
		colors[region.id] = c
	_region_palette = _make_palette(colors, _region_palette)
	_material.set_shader_parameter("region_palette_tex", _region_palette)


func redraw() -> void:
	if map == null:
		return
	var base := MapMode.base_mode(mode)
	if base != _painted_base_mode:
		var img := MapPainter.paint_world(world, base) if world != null else MapPainter.paint(map, base)
		_dynamic_painted_ms = Time.get_ticks_msec()
		img.generate_mipmaps()
		# Во время кроссфейда старая текстура ещё на экране — новую не пишем поверх неё.
		if _base_texture != null and Vector2i(_base_texture.get_size()) == img.get_size() and not _fade_sprite.visible:
			_base_texture.update(img)
		else:
			_base_texture = ImageTexture.create_from_image(img)
			_sprite.texture = _base_texture
		_painted_base_mode = base
	_apply_mode_uniforms()


## Владельцы клеток изменились: плавный переход, если позволяют настройки,
## скорость и бюджет анимаций (иначе — мгновенно). Новые изменения во время
## перехода ждут его конца (не дольше 1,5 перехода).
func _owner_changed() -> void:
	var changed := world.ownership_version - _owner_version
	var smooth := SmoothSettings.border_anim and WorldState.speed_index < INSTANT_SPEED and _owner_texture != null \
			and changed <= SmoothSettings.border_budget and _shown_texels.size() == world.owner_texels.size()
	if not smooth:
		_blend = 1.0
		_material.set_shader_parameter("blend", 1.0)
		refresh_political()
		return
	var now := Time.get_ticks_msec()
	if _blend < 1.0:
		if not _pending_owner:
			_pending_owner = true
			_pending_since_ms = now
		if now - _pending_since_ms < BORDER_TIME * 1500.0:
			return
	_pending_owner = false
	var img := Image.create_from_data(map.width, map.height, false, Image.FORMAT_RGBA8, _shown_texels)
	if _prev_texture != null and Vector2i(_prev_texture.get_size()) == img.get_size():
		_prev_texture.update(img)
	else:
		_prev_texture = ImageTexture.create_from_image(img)
		_material.set_shader_parameter("prev_owner_tex", _prev_texture)
	_blend = 0.0
	_material.set_shader_parameter("blend", 0.0)
	refresh_political()


## Загружает в GPU текущих владельцев клеток и палитры государств.
func refresh_political() -> void:
	if world == null:
		return
	_shown_texels = world.owner_texels.duplicate()
	var img := Image.create_from_data(map.width, map.height, false, Image.FORMAT_RGBA8, world.owner_texels)
	if _owner_texture != null and Vector2i(_owner_texture.get_size()) == img.get_size():
		_owner_texture.update(img)
	else:
		_owner_texture = ImageTexture.create_from_image(img)
		_material.set_shader_parameter("owner_tex", _owner_texture)
	_owner_version = world.ownership_version
	refresh_palettes()


func refresh_palettes() -> void:
	var nation_colors := PackedColorArray()
	var race_colors := PackedColorArray()
	for nation in world.nations:
		# Вассалы — в оттенке сюзерена: видно, кто чья держава.
		var col := nation.color
		if nation.overlord >= 0:
			col = col.lerp(world.nations[nation.overlord].color, 0.45)
		nation_colors.append(col)
		race_colors.append(nation.race.color)
	_nation_palette = _make_palette(nation_colors, _nation_palette)
	_race_palette = _make_palette(race_colors, _race_palette)
	_apply_mode_uniforms()


## Прямоугольник карты в мировых координатах.
func get_map_rect() -> Rect2:
	if map == null:
		return Rect2()
	return Rect2(global_position, Vector2(map.width, map.height) * cell_size)


## Индекс клетки под точкой мира или -1.
func cell_at(world_pos: Vector2) -> int:
	if map == null:
		return -1
	var p := (to_local(world_pos) / cell_size).floor()
	if not map.in_bounds(int(p.x), int(p.y)):
		return -1
	return map.index_of(int(p.x), int(p.y))


## Центр клетки в мировых координатах.
func cell_center(cell: int) -> Vector2:
	var p := map.cell_pos(cell)
	return global_position + (Vector2(p) + Vector2(0.5, 0.5)) * cell_size


func _apply_mode_uniforms() -> void:
	var political := mode == MapMode.POLITICAL or mode == MapMode.RACES
	_material.set_shader_parameter("show_fill", political)
	_material.set_shader_parameter("region_fill", MapMode.is_region_mode(mode))
	# В режимах биомов, населения, ресурсов и по регионам оставляем тонкие границы — видно, кто где живёт.
	_material.set_shader_parameter("show_borders", political or mode == MapMode.BIOMES
			or mode == MapMode.POPULATION or mode == MapMode.RESOURCES or MapMode.is_region_mode(mode) or mode == MapMode.TRADE or mode == MapMode.UNDERGROUND or mode == MapMode.INFLUENCE)
	_material.set_shader_parameter("darken", 0.62 if mode == MapMode.UNDERGROUND else 0.0)
	# «Торговля»: приглушённая карта, на ней ярче видны пути.
	_material.set_shader_parameter("unowned_desaturate", 0.6 if mode == MapMode.TRADE else (0.35 if political else 0.0))
	_material.set_shader_parameter("fill_alpha", 0.55 if mode == MapMode.RACES else 0.45)
	_material.set_shader_parameter("unowned_desaturate", 0.35 if political else 0.0)
	_material.set_shader_parameter("palette_tex", _race_palette if mode == MapMode.RACES else _nation_palette)
	_material.set_shader_parameter("selected_id", selected_nation)


func _make_palette(colors: PackedColorArray, existing: ImageTexture) -> ImageTexture:
	var rows := maxi(1, ceili(colors.size() / float(PALETTE_WIDTH)))
	var img := Image.create_empty(PALETTE_WIDTH, rows, false, Image.FORMAT_RGBA8)
	for i in colors.size():
		img.set_pixel(i % PALETTE_WIDTH, i / PALETTE_WIDTH, colors[i])
	if existing != null and Vector2i(existing.get_size()) == img.get_size():
		existing.update(img)
		return existing
	return ImageTexture.create_from_image(img)


func _on_world_generated(new_world: World, _elapsed_ms: int) -> void:
	world = new_world
	# Новый или загруженный мир — без переходов.
	_blend = 1.0
	_pending_owner = false
	_material.set_shader_parameter("blend", 1.0)
	_tint = _tint_for(new_world)
	_tint_target = _tint
	_material.set_shader_parameter("tint", _tint)
	map = new_world.map
	cell_size = BASE_CELL_SIZE / new_world.grid_scale
	_sprite.scale = Vector2.ONE * cell_size
	_fade_sprite.scale = _sprite.scale
	# Границы регионов появляются при том же зуме, что и на ×1 (порог — в пикселях на базовую клетку).
	_material.set_shader_parameter("region_min_px", REGION_MIN_PX / new_world.grid_scale)
	selected_nation = -1
	_painted_base_mode = -1
	_terrain_version = world.terrain_version
	_upload_regions()
	redraw()
	refresh_political()


## Регионы меняются только вместе с рельефом (панель Бога) — загружаем при создании мира и при правке.
func _upload_regions() -> void:
	var img := Image.create_from_data(map.width, map.height, false, Image.FORMAT_RGBA8, world.region_texels)
	if _region_texture != null and Vector2i(_region_texture.get_size()) == img.get_size():
		_region_texture.update(img)
	else:
		_region_texture = ImageTexture.create_from_image(img)
		_material.set_shader_parameter("region_tex", _region_texture)


func _on_nation_selected(nation_id: int) -> void:
	selected_nation = nation_id
	_material.set_shader_parameter("selected_id", nation_id)


# ---------------------------------------------------------------------------
# Плавность отображения
# ---------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / BORDER_TIME)
		_material.set_shader_parameter("blend", _blend)
		if _blend >= 1.0 and _pending_owner:
			_owner_changed()
	if world == null:
		return
	var now := Time.get_ticks_msec()
	if now - _tint_ms > TINT_MS:
		_tint_ms = now
		_tint_target = _tint_for(world) if SmoothSettings.event_fx else Color(1, 1, 1, 0)
	if not _tint.is_equal_approx(_tint_target):
		_tint = _tint.lerp(_tint_target, SmoothSettings.factor(TINT_K, delta)) if SmoothSettings.border_anim else _tint_target
		_material.set_shader_parameter("tint", _tint)


## Оттенок мира: пепельная зима, мировой кризис, «золотой век».
static func _tint_for(w: World) -> Color:
	if w == null:
		return Color(1, 1, 1, 0)
	if not w.crisis.is_empty():
		return CRISIS_TINT.get(StringName(w.crisis.get("id", "")), Color(0.9, 0.85, 0.85, 0.1))
	if w.ash_until > w.year:
		return ASH_TINT
	if not w.eras.is_empty() and String(w.eras[w.eras.size() - 1].name).contains("Золот"):
		return Color(1.1, 0.98, 0.75, 0.08)
	return Color(1, 1, 1, 0)


## Кроссфейд режима: прежняя картинка (база + слой) гаснет поверх новой.
func _start_mode_fade() -> void:
	if not SmoothSettings.border_anim or _base_texture == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_sprite.texture = _base_texture
	_fade_sprite.material = _material.duplicate()
	_fade_sprite.modulate.a = 1.0
	_fade_sprite.visible = true
	_painted_base_mode = -1  # новая база — в новую текстуру
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_sprite, "modulate:a", 0.0, MODE_FADE)
	_fade_tween.tween_callback(func() -> void:
		_fade_sprite.visible = false
		_fade_sprite.texture = null
		_fade_sprite.material = null)
