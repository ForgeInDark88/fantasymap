class_name BattleField
extends Control
## Поле боя как отдельная карта (этап 12.E): местность вокруг места столкновения
## (биомы, реки, рельеф — из карты мира) и сам бой поверх неё. Битва — полки
## сторон сходятся, линия фронта гнётся к проигравшему, полки тают по потерям,
## побеждённые отходят, на поле остаются павшие; поединок — двое кружат и бьют,
## проигравший падает или бежит; встреча — двое сходятся у костра. Ход — по
## шагам пересказа (BattleReplay): progress — номер шага с долей (0..число шагов).
## Всё — только отображение: свой ГСЧ с зерном записи, мир не меняется.

## Клеток мира по ширине и высоте поля.
const FIELD_W := 28
const FIELD_H := 16

## Участок поля (клеток): битва — шире, поединок и встреча — ближе.
var _fw := FIELD_W
var _fh := FIELD_H
var record: BattleRecord
var steps: Array[Dictionary] = []
var progress := 0.0

var _bg: ImageTexture
var _blocks: Array[Dictionary] = []  # {side, slot, row, w, h, jitter}
var _dead: Array[Vector2] = []  # места павших (доли поля 0..1)
var _sparks: Array[Vector3] = []  # (x, y, фаза)
var _cols := [Color(0.85, 0.3, 0.25), Color(0.25, 0.45, 0.85)]


func setup(r: BattleRecord, s: Array[Dictionary], world: World) -> void:
	record = r
	steps = s
	progress = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = r.replay_seed ^ 0x5bd1e995
	for k in 2:
		if k < r.sides.size() and world != null:
			var n := int(r.sides[k].nation)
			if n >= 0 and n < world.nations.size():
				_cols[k] = world.nations[n].color
	# Цвета держав бывают близки (или сливаются с травой) — вторую сторону
	# сдвигаем по оттенку, чтобы полки различались.
	if _dist(_cols[0], _cols[1]) < 0.5:
		_cols[1] = Color.from_hsv(fmod(_cols[0].h + 0.5, 1.0), maxf(0.6, _cols[0].s), maxf(0.75, _cols[0].v))
	_fw = FIELD_W if r.kind == &"battle" else FIELD_W / 2
	_fh = FIELD_H if r.kind == &"battle" else FIELD_H / 2
	_bg = _terrain(world, r.cell, _fw, _fh)
	# Полки: по силе стороны (3–8), в две линии.
	_blocks.clear()
	if r.kind == &"battle":
		var pw := [float(r.sides[0].power), float(r.sides[1].power)]
		var top := maxf(1.0, maxf(pw[0], pw[1]))
		for side in 2:
			var count := clampi(roundi(3.0 + 5.0 * pw[side] / top), 3, 8)
			for i in count:
				_blocks.append({"side": side, "slot": (i + 0.5) / count, "row": i % 2, "w": rng.randf_range(0.8, 1.15),
					"jitter": rng.randf_range(0.0, TAU)})
	_dead.clear()
	var fallen_marks := clampi(int(sqrt(maxf(0.0, r.fallen)) / 6.0), 0, 60) if r.kind == &"battle" else 0
	for i in fallen_marks:
		_dead.append(Vector2(rng.randf_range(0.35, 0.65) + rng.randfn(0.0, 0.05), rng.randf_range(0.1, 0.9)))
	_sparks.clear()
	for i in 24:
		_sparks.append(Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(0.12, 0.88), rng.randf_range(0.0, TAU)))
	queue_redraw()


static func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _init() -> void:
	# Местность — клетками, как на карте мира (без размытия).
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Местность: клетки мира вокруг cell, цвет — биом, тень — высота, реки — синим.
static func _terrain(world: World, cell: int, fw: int, fh: int) -> ImageTexture:
	var img := Image.create_empty(fw, fh, false, Image.FORMAT_RGBA8)
	if world == null or cell < 0:
		img.fill(Color(0.35, 0.45, 0.3))
		return ImageTexture.create_from_image(img)
	var map := world.map
	var c := map.cell_pos(cell)
	for y in fh:
		for x in fw:
			var wx := clampi(c.x - fw / 2 + x, 0, map.width - 1)
			var wy := clampi(c.y - fh / 2 + y, 0, map.height - 1)
			var i := map.index_of(wx, wy)
			var col := BiomeDB.get_def(map.biome[i]).color
			col = col.darkened(clampf(-map.elevation[i] * 0.5, 0.0, 0.5)) if map.elevation[i] < 0.0 else col.lightened(clampf((map.elevation[i] - 0.3) * 0.4, 0.0, 0.3))
			if map.river[i] > 0 and map.is_land(i):
				col = col.lerp(Color(0.3, 0.5, 0.85), 0.6)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	return tex


func _phase_at(p: float) -> StringName:
	var i := clampi(int(p), 0, maxi(0, steps.size() - 1))
	return steps[i].phase if not steps.is_empty() else &""


## Доля пути по сценарию: где на шкале шагов начинается фаза (первое вхождение).
func _first(phase: StringName) -> float:
	for i in steps.size():
		if steps[i].phase == phase:
			return float(i)
	return -1.0


func _strength(side: int) -> float:
	if steps.is_empty():
		return 1.0
	var i := clampi(int(progress), 0, steps.size() - 1)
	var j := clampi(i + 1, 0, steps.size() - 1)
	var f := progress - floorf(progress)
	var key := "a" if side == 0 else "b"
	return lerpf(float(steps[i][key]), float(steps[j][key]), f) if progress < steps.size() else float(steps[steps.size() - 1][key])


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if _bg != null:
		draw_texture_rect(_bg, rect, false)
	# Лёгкая сетка клеток — видно, что это карта.
	var cw := size.x / _fw
	var ch := size.y / _fh
	for x in _fw + 1:
		draw_line(Vector2(x * cw, 0), Vector2(x * cw, size.y), Color(0, 0, 0, 0.06), 1.0)
	for y in _fh + 1:
		draw_line(Vector2(0, y * ch), Vector2(size.x, y * ch), Color(0, 0, 0, 0.06), 1.0)
	if record == null:
		return
	# Имена сторон — по краям поля, в цвет стороны.
	var font := get_theme_default_font()
	for k in mini(2, record.sides.size()):
		var nm := str(record.sides[k].name)
		var pos := Vector2(10, 20) if k == 0 else Vector2(size.x - 10 - font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, 20)
		draw_string(font, pos + Vector2(1, 1), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.8))
		draw_string(font, pos, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, (_cols[k] as Color).lightened(0.25))
	match record.kind:
		&"battle":
			_draw_battle()
		&"duel":
			_draw_duel()
		_:
			_draw_meeting()
	draw_rect(rect, Color(0, 0, 0, 0.6), false, 2.0)


func _draw_battle() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var clash_at := maxf(1.0, _first(&"clash"))
	var turn_at := _first(&"turn")
	var rout_at := _first(&"rout")
	var win := record.winner
	# Сближение: от краёв к середине до первой сечи.
	var approach := clampf(progress / clash_at, 0.0, 1.0)
	approach = approach * approach * (3.0 - 2.0 * approach)
	# Фронт: середина, к проигравшему — по ходу сечи и перелома.
	var push := 0.0
	if progress > clash_at:
		push = clampf((progress - clash_at) / maxf(1.0, (turn_at if turn_at > 0.0 else steps.size()) - clash_at + 1.0), 0.0, 1.0) * 0.08
	if turn_at > 0.0 and progress > turn_at:
		push += clampf(progress - turn_at, 0.0, 1.0) * 0.07
	var front := 0.5 + (push if win == 0 else -push)
	# Отход проигравших.
	var rout := clampf(progress - rout_at, 0.0, 2.0) / 2.0 if rout_at > 0.0 else 0.0
	# Павшие — по мере сечи.
	var dead_share := clampf((progress - clash_at) / maxf(1.0, steps.size() - clash_at), 0.0, 1.0)
	for k in int(_dead.size() * dead_share):
		var d := _dead[k]
		var p := Vector2((d.x - 0.5 + front) * size.x, d.y * size.y)
		draw_line(p + Vector2(-4, -4), p + Vector2(4, 4), Color(0.35, 0.05, 0.05, 0.85), 2.5)
		draw_line(p + Vector2(4, -4), p + Vector2(-4, 4), Color(0.35, 0.05, 0.05, 0.85), 2.5)
	var fighting := progress >= clash_at and (rout_at < 0.0 or progress < rout_at + 0.5)
	for b in _blocks:
		var side: int = b.side
		var strength := _strength(side)
		var lost := side != win
		var dir := 1.0 if side == 0 else -1.0
		var start_x := 0.12 if side == 0 else 0.88
		var line_x := front - dir * (0.035 + 0.06 * int(b.row))
		var x := lerpf(start_x - dir * 0.06 * int(b.row), line_x, approach)
		if fighting:
			x += sin(t * 6.0 + float(b.jitter)) * 0.004
		if lost:
			x -= dir * rout * 0.45
		var y := 0.12 + float(b.slot) * 0.76
		var w := size.x * 0.05 * float(b.w) * (0.45 + 0.55 * strength)
		var h := size.y * 0.09 * (0.5 + 0.5 * strength)
		var alpha := 1.0 - (rout * 0.8 if lost else 0.0)
		var col: Color = _cols[side]
		col.a = alpha
		var r := Rect2(Vector2(x * size.x - w * 0.5, y * size.y - h * 0.5), Vector2(w, h))
		draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(0, 0, 0, 0.35 * alpha))
		draw_rect(r, col)
		draw_rect(Rect2(r.position, Vector2(w, 2.0)), Color(1, 1, 1, 0.45 * alpha))
		draw_rect(r.grow(-3.0), Color(1, 1, 1, 0.35 * alpha), false, 1.0)
		draw_rect(r, Color(0.05, 0.04, 0.04, 0.95 * alpha), false, 3.0)
		# Знамя полка.
		var pole := r.position + Vector2(w * 0.5, 0)
		draw_line(pole, pole + Vector2(0, -h * 0.55), Color(0.2, 0.15, 0.1, alpha), 1.5)
		draw_colored_polygon(PackedVector2Array([pole + Vector2(0, -h * 0.55), pole + Vector2(dir * 7.0, -h * 0.45), pole + Vector2(0, -h * 0.35)]),
			col.lightened(0.3))
	# Сеча: искры по линии фронта.
	if fighting:
		for s in _sparks:
			var ph := fmod(t * 3.0 + s.z, TAU)
			if sin(ph) > 0.6:
				var p := Vector2((front + s.x) * size.x, s.y * size.y)
				draw_circle(p, 2.0 + sin(ph) * 1.5, Color(1.0, 0.9, 0.5, 0.85))


func _figure(p: Vector2, col: Color, alpha: float, lean: float, fallen := false) -> void:
	# Фигура в масштабе поля (рисуется в своих координатах ×k).
	var k := size.y / 110.0
	draw_set_transform(p, 0.0, Vector2(k, k))
	p = Vector2.ZERO
	var ink := Color(0.1, 0.08, 0.08, alpha)
	col.a = alpha
	if fallen:
		draw_line(p + Vector2(-9, 4), p + Vector2(9, 4), ink, 5.0)
		draw_line(p + Vector2(-9, 4), p + Vector2(9, 4), col, 3.0)
		draw_circle(p + Vector2(-11, 3), 4.0, col)
		draw_set_transform(Vector2.ZERO)
		return
	draw_circle(p + Vector2(lean, -16), 5.0, col)
	draw_line(p + Vector2(lean, -11), p, ink, 5.0)
	draw_line(p + Vector2(lean, -11), p, col, 3.0)
	draw_line(p, p + Vector2(-4, 10), ink, 2.5)
	draw_line(p, p + Vector2(4, 10), ink, 2.5)
	draw_set_transform(Vector2.ZERO)


func _draw_duel() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var c := size * 0.5
	var end_at := float(steps.size() - 1)
	var near := clampf(progress, 0.0, 1.0)
	var gap := lerpf(size.x * 0.3, size.x * 0.08, near)
	var ang := progress * 0.9  # кружат
	var pa := c + Vector2(cos(ang), sin(ang) * 0.4) * -gap
	var pb := c + Vector2(cos(ang), sin(ang) * 0.4) * gap
	var ended := progress >= end_at
	var lunge := sin(t * 5.0) * 6.0 * size.y / 110.0 if not ended and progress > 1.0 else 0.0
	_figure(pa + Vector2(lunge, 0), _cols[0], 1.0, 3.0)
	var flee := clampf(progress - end_at, 0.0, 1.0)
	if ended and record.killed:
		_figure(pb, _cols[1], 1.0, 0.0, true)
	else:
		_figure(pb + Vector2(flee * size.x * 0.35, 0) - Vector2(lunge, 0), _cols[1], 1.0 - flee * 0.7, -3.0)
	# Клинки и вспышки ударов.
	var k := size.y / 110.0
	# Клинок — из руки первого (рука — у плеча фигуры, с выпадом).
	var blade_a := pa + Vector2(lunge, 0) + Vector2(5, -10) * k
	draw_line(blade_a, blade_a + Vector2(14, -6) * k, Color(0.9, 0.9, 0.95), 2.0 * k)
	if not ended and progress > 1.0 and sin(t * 5.0) > 0.85:
		draw_circle((pa + pb) * 0.5 + Vector2(0, -10) * k, 6.0 * k, Color(1.0, 0.9, 0.5, 0.9))


func _draw_meeting() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var c := size * 0.5 + Vector2(0, 10)
	var end_at := float(steps.size() - 1)
	var near := clampf(progress, 0.0, 1.0)
	var apart := clampf(progress - end_at, 0.0, 1.0) * (1.0 if record.outcome == &"rival" else 0.15)
	var gap := lerpf(size.x * 0.32, size.x * 0.07, near) + apart * size.x * 0.3
	# Костёр.
	if near > 0.6:
		var flick := 0.7 + 0.3 * sin(t * 9.0)
		draw_circle(c + Vector2(0, 8), 7.0 * flick, Color(1.0, 0.55, 0.15, 0.85))
		draw_circle(c + Vector2(0, 6), 3.5 * flick, Color(1.0, 0.9, 0.4, 0.9))
	_figure(c - Vector2(gap, 0), _cols[0], 1.0, 2.0)
	_figure(c + Vector2(gap, 0), _cols[1], 1.0, -2.0)
	if progress >= end_at:
		var sym := "♥" if record.outcome == &"friend" else ("⚔" if record.outcome == &"rival" else "…")
		draw_string(get_theme_default_font(), c + Vector2(-6, -34), sym, HORIZONTAL_ALIGNMENT_CENTER, -1, 18,
			Color(1.0, 0.85, 0.85) if record.outcome == &"friend" else Color(1.0, 0.95, 0.8))
