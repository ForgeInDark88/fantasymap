class_name MapPainter
## Превращает данные WorldMap в Image (1 пиксель = 1 клетка).
##
## Чистая функция без состояния: можно вызывать из любого потока и из тестов.
## Цвет пишется сразу как 32-битное число в PackedInt32Array — это в разы
## быстрее, чем Image.set_pixel() для каждой клетки.

const RIVER_COLORS: Array[Color] = [
	Color(0.0, 0.0, 0.0),
	Color(0.33, 0.56, 0.76),
	Color(0.26, 0.49, 0.71),
	Color(0.20, 0.42, 0.66),
]
const SURF_COLOR := Color(0.62, 0.76, 0.84)
## Сила рельефной подсветки (свет с северо-запада).
const HILLSHADE := 3.0

static var _height_gradient: Gradient
static var _temp_gradient: Gradient
static var _moist_gradient: Gradient


static func paint(map: WorldMap, mode: int) -> Image:
	var colors := PackedInt32Array()
	colors.resize(map.cell_count())
	match mode:
		MapMode.HEIGHT:
			_paint_height(map, colors)
		MapMode.TEMPERATURE:
			_paint_scalar(map, colors, map.temperature, _get_temp_gradient())
		MapMode.MOISTURE:
			_paint_scalar(map, colors, map.moisture, _get_moist_gradient())
		_:
			_paint_biomes(map, colors)
	return Image.create_from_data(map.width, map.height, false, Image.FORMAT_RGBA8, colors.to_byte_array())


## Режимы, которым нужен не только рельеф, но и состояние мира.
static func paint_world(world: World, mode: int) -> Image:
	var map := world.map
	var colors := PackedInt32Array()
	colors.resize(map.cell_count())
	if mode == MapMode.POPULATION:
		_paint_population(world, colors)
	elif mode == MapMode.RESOURCES:
		_paint_resources(world, colors)
	else:
		return paint(map, mode)
	return Image.create_from_data(map.width, map.height, false, Image.FORMAT_RGBA8, colors.to_byte_array())


static var _density_lut := PackedInt32Array()


## Плотность населения: ёмкость клетки × заселённость её народа в государстве.
static func _paint_population(world: World, out: PackedInt32Array) -> void:
	if _density_lut.is_empty():
		var g := _make_gradient(PackedFloat32Array([0.0, 0.25, 0.55, 0.8, 1.0]),
				[Color(0.16, 0.12, 0.25), Color(0.45, 0.15, 0.4), Color(0.85, 0.3, 0.2), Color(0.98, 0.75, 0.25), Color(1.0, 1.0, 0.85)])
		_density_lut.resize(64)
		for i in 64:
			_density_lut[i] = g.sample(i / 63.0).to_abgr32()
	var map := world.map
	var fill := PackedFloat32Array()
	fill.resize(world.nations.size() * RaceDB.count())
	var races := RaceDB.count()
	for n in world.nations:
		for r in races:
			if n.capacity[r] > 0.0:
				fill[n.id * races + r] = n.pop[r] / n.capacity[r]
	var water := Color(0.06, 0.09, 0.16).to_abgr32()
	var empty := Color(0.2, 0.21, 0.22).to_abgr32()
	var owner := world.owner
	var cell_race := world.cell_race
	var cap := world.cell_cap
	for i in map.cell_count():
		var o := owner[i]
		if o < 0:
			out[i] = empty if map.is_land(i) else water
			continue
		var r := cell_race[i]
		var density := cap[i] * fill[o * races + r] if r != World.NO_RACE else 0.0
		out[i] = _density_lut[clampi(int(sqrt(density / 1500.0) * 63.0), 0, 63)]


## Ресурсы: приглушённый рельеф, лес, камень и руда оттенками, месторождения — яркими клетками.
static func _paint_resources(world: World, out: PackedInt32Array) -> void:
	var map := world.map
	var palette: Array[Color] = []
	for def in BiomeDB.all():
		var grey := def.color.get_luminance()
		palette.append(def.color.lerp(Color(grey, grey, grey), 0.75).darkened(0.35))
	var wood := Color(0.25, 0.55, 0.2)
	var stone := Color(0.65, 0.65, 0.7)
	var metal := Color(0.45, 0.55, 0.8)
	var deposits := EconomyDB.deposits()
	for i in map.cell_count():
		var col := palette[map.biome[i]]
		if map.is_land(i):
			var base := i * Goods.COUNT
			col = col.lerp(wood, clampf(world.cell_yield[base + Goods.WOOD], 0.0, 1.0) * 0.45)
			col = col.lerp(stone, clampf(world.cell_yield[base + Goods.STONE], 0.0, 1.0) * 0.35)
			col = col.lerp(metal, clampf(world.cell_yield[base + Goods.METAL] * 2.0, 0.0, 1.0) * 0.35)
			var d := world.deposit[i]
			if d > 0:
				col = deposits[d - 1].color
		out[i] = col.to_abgr32()


static func _paint_biomes(map: WorldMap, out: PackedInt32Array) -> void:
	var w := map.width
	var h := map.height
	var elev := map.elevation
	var biome := map.biome
	var river := map.river
	var palette: Array[Color] = []
	for def in BiomeDB.all():
		palette.append(def.color)
	for y in h:
		for x in w:
			var i := y * w + x
			var b := biome[i]
			var col := palette[b]
			if Biome.is_water(b):
				if b == Biome.OCEAN:
					col = col.darkened(clampf(-elev[i] - 0.3, 0.0, 0.7) * 0.5)
				elif b == Biome.SEA:
					col = col.darkened(clampf(-elev[i], 0.0, 1.0) * 0.25)
				if _touches_land(map, x, y):
					col = col.lerp(SURF_COLOR, 0.35)
			else:
				if river[i] > 0:
					col = RIVER_COLORS[river[i]]
				else:
					col = _shade(col, _slope(map, x, y))
			out[i] = col.to_abgr32()


static func _paint_height(map: WorldMap, out: PackedInt32Array) -> void:
	var grad := _get_height_gradient()
	var w := map.width
	var elev := map.elevation
	var river := map.river
	for y in map.height:
		for x in w:
			var i := y * w + x
			var e := elev[i]
			var col: Color
			if not map.is_land(i):
				col = Color(0.04, 0.09, 0.22).lerp(Color(0.32, 0.52, 0.76), clampf(e + 1.0, 0.0, 1.0))
			elif river[i] > 0:
				col = RIVER_COLORS[river[i]]
			else:
				col = _shade(grad.sample(e), _slope(map, x, y))
			out[i] = col.to_abgr32()


static func _paint_scalar(map: WorldMap, out: PackedInt32Array, values: PackedFloat32Array, grad: Gradient) -> void:
	for i in map.cell_count():
		var col := grad.sample(values[i])
		if not map.is_land(i):
			col = col.darkened(0.55)
		out[i] = col.to_abgr32()


static func _touches_land(map: WorldMap, x: int, y: int) -> bool:
	var w := map.width
	var i := y * w + x
	if x > 0 and map.is_land(i - 1):
		return true
	if x < w - 1 and map.is_land(i + 1):
		return true
	if y > 0 and map.is_land(i - w):
		return true
	if y < map.height - 1 and map.is_land(i + w):
		return true
	return false


## Перепад высот вдоль диагонали СЗ→ЮВ (вода считается уровнем моря).
static func _slope(map: WorldMap, x: int, y: int) -> float:
	var w := map.width
	var x0 := maxi(x - 1, 0)
	var y0 := maxi(y - 1, 0)
	var x1 := mini(x + 1, w - 1)
	var y1 := mini(y + 1, map.height - 1)
	var a := maxf(map.elevation[y0 * w + x0], 0.0)
	var b := maxf(map.elevation[y1 * w + x1], 0.0)
	return a - b


static func _shade(col: Color, slope: float) -> Color:
	var s := clampf(slope * HILLSHADE, -0.3, 0.3)
	return col.lightened(s) if s > 0.0 else col.darkened(-s)


static func _get_height_gradient() -> Gradient:
	if _height_gradient == null:
		_height_gradient = _make_gradient(
				PackedFloat32Array([0.0, 0.35, 0.65, 0.82, 0.94, 1.0]),
				[Color(0.30, 0.55, 0.32), Color(0.55, 0.68, 0.38), Color(0.80, 0.74, 0.47),
					Color(0.62, 0.48, 0.33), Color(0.52, 0.45, 0.42), Color(0.97, 0.97, 0.98)])
	return _height_gradient


static func _get_temp_gradient() -> Gradient:
	if _temp_gradient == null:
		_temp_gradient = _make_gradient(
				PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0]),
				[Color(0.25, 0.30, 0.85), Color(0.35, 0.75, 0.90), Color(0.45, 0.80, 0.40),
					Color(0.95, 0.80, 0.30), Color(0.85, 0.25, 0.15)])
	return _temp_gradient


static func _get_moist_gradient() -> Gradient:
	if _moist_gradient == null:
		_moist_gradient = _make_gradient(
				PackedFloat32Array([0.0, 0.35, 0.65, 1.0]),
				[Color(0.80, 0.62, 0.35), Color(0.75, 0.75, 0.45), Color(0.30, 0.65, 0.35),
					Color(0.15, 0.35, 0.80)])
	return _moist_gradient


static func _make_gradient(offsets: PackedFloat32Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	return g
