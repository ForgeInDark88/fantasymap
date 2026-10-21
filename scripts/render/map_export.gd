class_name MapExport
## Экспорт карты (этап 11.F): PNG всей карты (рельеф и биомы, державы
## полупрозрачной заливкой, границы, города; масштаб — пикселей на клетку),
## стиль «пергамент» (сепия, выцветание к краям, крапинки старой бумаги) и SVG-
## легенда (державы по размеру — цвет и имя; дата мира). Без сцены и шейдеров —
## считается на процессоре из данных мира; работает и без экрана.

const DIR := "user://exports/"
const SCALE := 3


static func image(world: World, parchment: bool = false, scale: int = SCALE) -> Image:
	var map := world.map
	var base := MapPainter.paint(map, MapMode.BIOMES)
	var w := map.width
	var hgt := map.height
	var img := Image.create_empty(w * scale, hgt * scale, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = world.settings.world_seed
	for y in hgt:
		for x in w:
			var i := y * w + x
			var c := base.get_pixel(x, y)
			var o := world.owner[i]
			if o >= 0:
				c = c.lerp(world.nations[o].color, 0.45)
				# Граница: сосед — другой владелец.
				var edge := (x > 0 and world.owner[i - 1] != o) or (x < w - 1 and world.owner[i + 1] != o) \
						or (y > 0 and world.owner[i - w] != o) or (y < hgt - 1 and world.owner[i + w] != o)
				if edge:
					c = c.darkened(0.45)
			if parchment:
				c = _sepia(c)
				var dx := float(x) / w - 0.5
				var dy := float(y) / hgt - 0.5
				c = c.darkened(clampf((dx * dx + dy * dy) * 1.4 - 0.05, 0.0, 0.45))
				c = c.darkened(rng.randf() * 0.06)
			img.fill_rect(Rect2i(x * scale, y * scale, scale, scale), c)
	# Города — точки (столицы крупнее).
	for city in world.cities:
		if not city.alive:
			continue
		var p := map.cell_pos(city.cell) * scale + Vector2i(scale / 2, scale / 2)
		var r := scale + (1 if city.is_capital else 0)
		var col := Color(0.25, 0.15, 0.08) if parchment else Color(0.05, 0.05, 0.05)
		img.fill_rect(Rect2i(p.x - r / 2, p.y - r / 2, r, r), col)
	return img


static func _sepia(c: Color) -> Color:
	var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
	return Color(0.94, 0.85, 0.66).lerp(Color(0.35, 0.24, 0.13), 1.0 - l).lerp(c, 0.18)


static func save_png(world: World, parchment: bool = false, path: String = "") -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	if path.is_empty():
		path = DIR + "map_%d_%d%s.png" % [world.settings.world_seed, world.year, "_parchment" if parchment else ""]
	var err := image(world, parchment).save_png(path)
	return path if err == OK else ""


## SVG-легенда: крупнейшие державы (до 24) — цвет, имя, раса, клетки.
static func legend_svg(world: World) -> String:
	var alive := world.nations.filter(func(n: Nation) -> bool: return n.alive)
	alive.sort_custom(func(a: Nation, b: Nation) -> bool: return a.cell_count > b.cell_count)
	alive = alive.slice(0, 24)
	var hgt := 60 + alive.size() * 24
	var lines: Array[String] = ['<svg xmlns="http://www.w3.org/2000/svg" width="420" height="%d" font-family="serif">' % hgt,
		'<rect width="420" height="%d" fill="#f1e4c3" stroke="#6b4f2a" stroke-width="3"/>' % hgt,
		'<text x="20" y="34" font-size="20" fill="#3b2a14">Державы мира — %s</text>' % _xml(world.date_text())]
	for i in alive.size():
		var n: Nation = alive[i]
		var y := 56 + i * 24
		lines.append('<rect x="20" y="%d" width="18" height="14" fill="#%s" stroke="#3b2a14"/>' % [y, n.color.to_html(false)])
		lines.append('<text x="46" y="%d" font-size="14" fill="#3b2a14">%s (%s, %d кл.)</text>' % [y + 12, _xml(n.name), _xml(n.race.display_name), n.cell_count])
	lines.append("</svg>")
	return "\n".join(lines)


static func save_svg(world: World, path: String = "") -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	if path.is_empty():
		path = DIR + "legend_%d_%d.svg" % [world.settings.world_seed, world.year]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(legend_svg(world))
	f.close()
	return path


static func _xml(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
