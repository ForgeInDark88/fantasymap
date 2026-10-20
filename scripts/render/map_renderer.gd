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

## Размер клетки в мировых единицах.
const CELL_SIZE := 4.0
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


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * CELL_SIZE
	# Пиксельная чёткость при приближении, мип-карты — без «ряби» при отдалении.
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_sprite.material = _material
	add_child(_sprite)
	EventBus.world_generated.connect(_on_world_generated)
	EventBus.map_mode_changed.connect(set_mode)
	EventBus.nation_selected.connect(_on_nation_selected)


func _process(_delta: float) -> void:
	# Границы обновляются не чаще раза за кадр, сколько бы тиков ни прошло.
	if world != null and world.terrain_version != _terrain_version:
		# Рельеф изменён панелью Бога: перерисовать базу и обновить регионы.
		_terrain_version = world.terrain_version
		_painted_base_mode = -1
		_upload_regions()
		redraw()
	if world != null and world.ownership_version != _owner_version:
		refresh_political()
	if world != null and MapMode.is_region_mode(mode) and Time.get_ticks_msec() - _region_palette_ms > REGION_PALETTE_MS:
		refresh_region_palette()
	if world != null and MapMode.is_dynamic(mode) and Time.get_ticks_msec() - _dynamic_painted_ms > DYNAMIC_REPAINT_MS \
			and WorldState.speed_index > 0:
		_painted_base_mode = -1
		redraw()


func set_mode(new_mode: int) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	if MapMode.is_region_mode(mode):
		refresh_region_palette()
	redraw()


## Цвет каждого региона в режимах по регионам: вера большинства (альфа — её доля).
func refresh_region_palette() -> void:
	if world == null:
		return
	_region_palette_ms = Time.get_ticks_msec()
	var colors := PackedColorArray()
	colors.resize(world.regions.size())
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
		if _base_texture != null and Vector2i(_base_texture.get_size()) == img.get_size():
			_base_texture.update(img)
		else:
			_base_texture = ImageTexture.create_from_image(img)
			_sprite.texture = _base_texture
		_painted_base_mode = base
	_apply_mode_uniforms()


## Загружает в GPU текущих владельцев клеток и палитры государств.
func refresh_political() -> void:
	if world == null:
		return
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
	return Rect2(global_position, Vector2(map.width, map.height) * CELL_SIZE)


## Индекс клетки под точкой мира или -1.
func cell_at(world_pos: Vector2) -> int:
	if map == null:
		return -1
	var p := (to_local(world_pos) / CELL_SIZE).floor()
	if not map.in_bounds(int(p.x), int(p.y)):
		return -1
	return map.index_of(int(p.x), int(p.y))


## Центр клетки в мировых координатах.
func cell_center(cell: int) -> Vector2:
	var p := map.cell_pos(cell)
	return global_position + (Vector2(p) + Vector2(0.5, 0.5)) * CELL_SIZE


func _apply_mode_uniforms() -> void:
	var political := mode == MapMode.POLITICAL or mode == MapMode.RACES
	_material.set_shader_parameter("show_fill", political)
	_material.set_shader_parameter("region_fill", MapMode.is_region_mode(mode))
	# В режимах биомов, населения, ресурсов и по регионам оставляем тонкие границы — видно, кто где живёт.
	_material.set_shader_parameter("show_borders", political or mode == MapMode.BIOMES
			or mode == MapMode.POPULATION or mode == MapMode.RESOURCES or MapMode.is_region_mode(mode) or mode == MapMode.TRADE or mode == MapMode.UNDERGROUND)
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
	map = new_world.map
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
