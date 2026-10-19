class_name MapGenerator
extends RefCounted
## Процедурный генератор карты. Чистая логика: не трогает сцену и autoload-ы,
## поэтому может работать в фоновом потоке и в headless-тестах.
##
## Конвейер:
##   1. Сырая высота: «пятна» континентов (с искажением формы) + FBM-шум + хребты.
##   2. Уровень моря по перцентилю → точная доля суши; высоты нормируются по рангу.
##   3. Водоёмы: океан/море (по удалённости от берега) и замкнутые озёра.
##   4. Температура: широта + шум − высота.
##   5. Влажность: шум + близость океана + климатические пояса.
##   6. Реки: Priority-Flood (заполнение впадин) → сток → накопление → реки и озёра.
##   7. Биомы по высоте, температуре и влажности.

## Шум сэмплируется в «виртуальных» координатах ширины 512, поэтому один и тот же
## seed даёт похожие очертания на картах разного размера.
const VIRTUAL_WIDTH := 512.0
## Число корзин в очереди Priority-Flood.
const FLOOD_BUCKETS := 8192
## Минимальная глубина впадины (в единицах ранга высоты), чтобы она стала озером.
const LAKE_DEPTH := 0.03
## Порог стока для реки при river_density = 1 (в виртуальных клетках).
const RIVER_BASE_FLOW := 110.0

var _s: MapSettings
var _rng := RandomNumberGenerator.new()
var _map: WorldMap
var _w := 0
var _h := 0
var _n := 0
## Шаг виртуальных координат на одну клетку.
var _scale := 1.0


func generate(settings: MapSettings) -> WorldMap:
	_s = settings
	_w = settings.width
	_h = settings.height
	_n = _w * _h
	_scale = VIRTUAL_WIDTH / float(_w)
	_rng.seed = hash(settings.world_seed)
	_map = WorldMap.new(_w, _h)
	_map.settings = settings

	var raw := _generate_raw_elevation()
	_normalize_elevation(raw)
	_classify_water()
	_compute_temperature()
	_compute_moisture()
	_compute_rivers()
	_assign_biomes()
	return _map


# ---------------------------------------------------------------------------
# 1. Высота
# ---------------------------------------------------------------------------

func _make_noise(salt: int, frequency: float, octaves: int,
		fractal: FastNoiseLite.FractalType = FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = hash(str(_s.world_seed) + ":" + str(salt)) & 0x7fffffff
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise


func _generate_raw_elevation() -> PackedFloat32Array:
	var warp := _make_noise(1, 0.006, 3)
	var detail := _make_noise(2, 0.008, 6)
	var ridges := _make_noise(3, 0.007, 5, FastNoiseLite.FRACTAL_RIDGED)
	var warp_amp := 95.0

	# Искажённые координаты считаем один раз: они нужны и для континентов.
	var wx := PackedFloat32Array()
	var wy := PackedFloat32Array()
	wx.resize(_n)
	wy.resize(_n)
	for y in _h:
		var vy := y * _scale
		for x in _w:
			var vx := x * _scale
			var i := y * _w + x
			wx[i] = vx + warp.get_noise_2d(vx, vy) * warp_amp
			wy[i] = vy + warp.get_noise_2d(vx + 731.0, vy - 419.0) * warp_amp

	var continent := _rasterize_continents(wx, wy, warp_amp)

	var raw := PackedFloat32Array()
	raw.resize(_n)
	var edge_w := float(_w) * 0.07
	var edge_h := float(_h) * 0.09
	for y in _h:
		var vy := y * _scale
		var ey := minf(y, _h - 1 - y) / edge_h
		for x in _w:
			var vx := x * _scale
			var i := y * _w + x
			# Маска суши: плато внутри континента, плавный спуск к шельфу.
			var c := continent[i]
			var mask := clampf((c + 0.35) / 0.8, 0.0, 1.0)
			mask = mask * mask * (3.0 - 2.0 * mask)
			var e := (mask - 0.5) + detail.get_noise_2d(vx, vy) * 0.62
			# Горы — гребни ridged-шума, только на суше: так получаются хребты, а не «шапки».
			var r := (ridges.get_noise_2d(wx[i], wy[i]) + 1.0) * 0.5
			e += r * r * 0.55 * mask
			# У краёв карты — океан.
			var edge := clampf(minf(minf(x, _w - 1 - x) / edge_w, ey), 0.0, 1.0)
			edge = edge * edge * (3.0 - 2.0 * edge)
			raw[i] = lerpf(-1.2, e, edge)
	return raw


## Континенты — «пятна» с центрами, разнесёнными методом лучшего кандидата.
## Значение 1 в центре, 0 на радиусе, отрицательное снаружи (до -1).
func _rasterize_continents(wx: PackedFloat32Array, wy: PackedFloat32Array, warp_amp: float) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	field.resize(_n)
	field.fill(-1.0)

	var count := _s.continents
	var vw := VIRTUAL_WIDTH
	var vh := VIRTUAL_WIDTH * float(_h) / float(_w)
	var base_r := sqrt(vw * vh * _s.land_fraction / (count * PI)) * 1.15
	var centers: Array[Vector3] = []
	for c in count:
		var best := Vector2(vw * 0.5, vh * 0.5)
		var best_d := -1.0
		var attempts := 1 if count == 1 else 40
		for attempt in attempts:
			var p := Vector2(_rng.randf_range(vw * 0.18, vw * 0.82), _rng.randf_range(vh * 0.2, vh * 0.8))
			if count == 1:
				p = p.lerp(Vector2(vw, vh) * 0.5, 0.6)
			var d := INF
			for e in centers:
				d = minf(d, p.distance_to(Vector2(e.x, e.y)))
			if d > best_d:
				best_d = d
				best = p
		centers.append(Vector3(best.x, best.y, base_r * _rng.randf_range(0.75, 1.25)))

	for ct in centers:
		var r := ct.z
		var reach := (r * 2.0 + warp_amp) / _scale
		var x0 := maxi(0, int((ct.x / _scale) - reach))
		var x1 := mini(_w - 1, int((ct.x / _scale) + reach))
		var y0 := maxi(0, int((ct.y / _scale) - reach))
		var y1 := mini(_h - 1, int((ct.y / _scale) + reach))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var i := y * _w + x
				var dx := wx[i] - ct.x
				var dy := wy[i] - ct.y
				var v := 1.0 - sqrt(dx * dx + dy * dy) / r
				if v > field[i]:
					field[i] = v
	return field


## Уровень моря выбирается так, чтобы доля суши точно равнялась настройке.
## Затем высоты суши и глубины воды заменяются на их ранг (0..1) — после этого
## пороги холмов/гор не зависят от seed и формы шума.
func _normalize_elevation(raw: PackedFloat32Array) -> void:
	var sorted := raw.duplicate()
	sorted.sort()
	var sea_idx := clampi(int((1.0 - _s.land_fraction) * _n), 1, _n - 1)
	var sea_level := sorted[sea_idx]
	var land_count := float(_n - sea_idx)
	var water_count := float(sea_idx)
	var elev := _map.elevation
	for i in _n:
		var v := raw[i]
		var rank := sorted.bsearch(v, true)
		if rank >= sea_idx:
			elev[i] = (rank - sea_idx + 1) / land_count
		else:
			elev[i] = rank / water_count - 1.0
	_map.elevation = elev
	# Уровень моря нужен только тут; оставим на будущее в метаданных.
	_map.set_meta("raw_sea_level", sea_level)


# ---------------------------------------------------------------------------
# 2. Вода
# ---------------------------------------------------------------------------

## Связные водные области: касающиеся края или большие — океан, остальные — озёра.
## Океан рядом с сушей становится морем (мелководьем).
func _classify_water() -> void:
	var elev := _map.elevation
	var biome := _map.biome
	var label := PackedInt32Array()
	label.resize(_n)
	label.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(_n)
	var lake_max_size := maxi(int(_n * 0.004), 12)

	for start in _n:
		if elev[start] >= 0.0 or label[start] != -1:
			continue
		# BFS по одной водной области.
		var head := 0
		var tail := 0
		queue[tail] = start
		tail += 1
		label[start] = start
		var touches_edge := false
		while head < tail:
			var c := queue[head]
			head += 1
			var cx := c % _w
			var cy := c / _w
			if cx == 0 or cy == 0 or cx == _w - 1 or cy == _h - 1:
				touches_edge = true
			for k in 4:
				var nb := _neighbor(c, cx, cy, k)
				if nb >= 0 and label[nb] == -1 and elev[nb] < 0.0:
					label[nb] = start
					queue[tail] = nb
					tail += 1
		var is_lake := not touches_edge and tail <= lake_max_size
		var b := Biome.LAKE if is_lake else Biome.OCEAN
		for q in tail:
			biome[queue[q]] = b

	for i in _n:
		if elev[i] >= 0.0:
			biome[i] = Biome.PLAINS  # временно, уточнится в _assign_biomes

	# Мелководье: расстояние от суши по воде (BFS) + относительно небольшая глубина.
	var coast_width := maxi(2, roundi(_w / 160.0))
	var dist := _distance_from(func(i: int) -> bool: return elev[i] >= 0.0,
			func(i: int) -> bool: return biome[i] == Biome.OCEAN, coast_width + 1)
	for i in _n:
		if biome[i] == Biome.OCEAN and (dist[i] <= coast_width or elev[i] > -0.22):
			biome[i] = Biome.SEA
	_map.biome = biome


# ---------------------------------------------------------------------------
# 3. Климат
# ---------------------------------------------------------------------------

func _latitude(y: int) -> float:
	# 0 — экватор (середина карты), 1 — полюс.
	return absf((y + 0.5) / _h - 0.5) * 2.0


func _compute_temperature() -> void:
	var noise := _make_noise(10, 0.006, 3)
	var temp := _map.temperature
	var elev := _map.elevation
	for y in _h:
		var lat := _latitude(y)
		var base := 1.0 - pow(lat, 1.25)
		var vy := y * _scale
		for x in _w:
			var i := y * _w + x
			var t := base + noise.get_noise_2d(x * _scale, vy) * 0.18 + _s.temperature_bias
			if elev[i] > 0.45:
				t -= (elev[i] - 0.45) * 0.75  # чем выше, тем холоднее
			temp[i] = clampf(t, 0.0, 1.0)
	_map.temperature = temp


func _compute_moisture() -> void:
	var noise := _make_noise(20, 0.007, 4)
	var elev := _map.elevation
	var biome := _map.biome
	var moist := _map.moisture
	var max_d := int(140.0 / _scale)
	var ocean_dist := _distance_from(
			func(i: int) -> bool: return biome[i] == Biome.OCEAN or biome[i] == Biome.SEA,
			func(i: int) -> bool: return elev[i] >= 0.0, max_d)
	for y in _h:
		var lat := _latitude(y)
		# Пояса: влажный экватор, сухие субтропики (~30°), влажные умеренные широты, сухие полюса.
		var band := 0.5 + 0.5 * cos(lat * PI * 3.0)
		var vy := y * _scale
		for x in _w:
			var i := y * _w + x
			if elev[i] < 0.0:
				moist[i] = 1.0
				continue
			var n := clampf(0.5 + noise.get_noise_2d(x * _scale, vy) * 0.9, 0.0, 1.0)
			var coast := exp(-ocean_dist[i] * _scale / 55.0)
			moist[i] = clampf(n * 0.45 + coast * 0.25 + band * 0.38 - 0.08, 0.0, 1.0)
	_map.moisture = moist


# ---------------------------------------------------------------------------
# 4. Реки и озёра
# ---------------------------------------------------------------------------

## Priority-Flood (Barnes et al.) с корзинной очередью: обходим сушу от воды
## вверх по высоте. Каждая клетка «стекает» в ту, из которой была достигнута, —
## получается дерево стока без бессточных впадин. Глубокие заполненные впадины
## превращаются в озёра, клетки с большим накопленным стоком — в реки.
func _compute_rivers() -> void:
	var elev := _map.elevation
	var biome := _map.biome
	var moist := _map.moisture

	var filled := elev.duplicate()
	var receiver := PackedInt32Array()
	receiver.resize(_n)
	receiver.fill(-1)
	var visited := PackedByteArray()
	visited.resize(_n)
	var nxt := PackedInt32Array()
	nxt.resize(_n)
	nxt.fill(-1)
	var head := PackedInt32Array()
	head.resize(FLOOD_BUCKETS)
	head.fill(-1)
	var tail := PackedInt32Array()
	tail.resize(FLOOD_BUCKETS)
	tail.fill(-1)
	var bscale := (FLOOD_BUCKETS - 1) * 0.5
	# Небольшой гладкий шум в ПРИОРИТЕТЕ обхода (не в высоте): в ровных заполненных
	# впадинах фронт обхода идёт по изолиниям шума, и реки петляют, а не идут по линейке.
	var jitter_noise := _make_noise(30, 0.03, 2)

	# Источники очереди — вся вода (океан, моря, озёра).
	for i in _n:
		if Biome.is_water(biome[i]):
			visited[i] = 1
			var b := clampi(int((elev[i] + 1.0) * bscale), 0, FLOOD_BUCKETS - 1)
			if tail[b] == -1:
				head[b] = i
			else:
				nxt[tail[b]] = i
			tail[b] = i

	var order := PackedInt32Array()
	order.resize(_n)
	var order_len := 0
	var bucket := 0
	while bucket < FLOOD_BUCKETS:
		var c := head[bucket]
		if c == -1:
			bucket += 1
			continue
		head[bucket] = nxt[c]
		if head[bucket] == -1:
			tail[bucket] = -1
		order[order_len] = c
		order_len += 1
		var fc := filled[c]
		var cx := c % _w
		var cy := c / _w
		for k in 4:
			var nb := _neighbor(c, cx, cy, k)
			if nb < 0 or visited[nb] == 1:
				continue
			visited[nb] = 1
			receiver[nb] = c
			var f := maxf(elev[nb], fc + 0.00001)
			filled[nb] = f
			var jitter := jitter_noise.get_noise_2d((nb % _w) * _scale, (nb / _w) * _scale) * 0.006
			var b := clampi(int((f + jitter + 1.0) * bscale), bucket, FLOOD_BUCKETS - 1)
			nxt[nb] = -1
			if tail[b] == -1:
				head[b] = nb
			else:
				nxt[tail[b]] = nb
			tail[b] = nb

	# Озёра во впадинах.
	for i in _n:
		if not Biome.is_water(biome[i]) and filled[i] - elev[i] > LAKE_DEPTH:
			biome[i] = Biome.LAKE

	# Накопление стока: обратный порядок обхода гарантирует, что приёмник
	# каждой клетки обрабатывается после неё.
	var flow := PackedFloat32Array()
	flow.resize(_n)
	for i in _n:
		if not Biome.is_water(biome[i]):
			flow[i] = 0.25 + moist[i]
	for k in range(order_len - 1, -1, -1):
		var c := order[k]
		var r := receiver[c]
		if r >= 0:
			flow[r] += flow[c]

	# Порог растёт медленнее площади клетки: на больших картах рек больше и они детальнее.
	var threshold := RIVER_BASE_FLOW / _scale / maxf(_s.river_density, 0.05)
	var river := _map.river
	for i in _n:
		if Biome.is_water(biome[i]):
			continue
		var f := flow[i]
		if f >= threshold * 25.0:
			river[i] = 3
		elif f >= threshold * 5.0:
			river[i] = 2
		elif f >= threshold:
			river[i] = 1

	# Реки и озёра увлажняют окрестности.
	for i in _n:
		if river[i] == 0 and biome[i] != Biome.LAKE:
			continue
		var cx := i % _w
		var cy := i / _w
		var boost := 0.1 + 0.04 * river[i]
		for dy in range(-2, 3):
			var y := cy + dy
			if y < 0 or y >= _h:
				continue
			for dx in range(-2, 3):
				var x := cx + dx
				if x < 0 or x >= _w:
					continue
				var j := y * _w + x
				var falloff := 1.0 / (1.0 + absi(dx) + absi(dy))
				moist[j] = minf(1.0, moist[j] + boost * falloff * 0.5)

	_map.biome = biome
	_map.river = river
	_map.moisture = moist


# ---------------------------------------------------------------------------
# 5. Биомы
# ---------------------------------------------------------------------------

func _assign_biomes() -> void:
	var biome := _map.biome
	var elev := _map.elevation
	var temp := _map.temperature
	var moist := _map.moisture
	for i in _n:
		if Biome.is_water(biome[i]):
			continue
		biome[i] = classify_land(elev[i], temp[i], moist[i])
	_map.biome = biome


## Классификация суши — вынесена отдельно, чтобы её мог вызывать и «режим бога»
## при подъёме земли.
static func classify_land(e: float, t: float, m: float) -> int:
	if e >= WorldMap.MOUNTAIN_LEVEL:
		return Biome.SNOW if t < 0.24 else Biome.MOUNTAINS
	if t < 0.12:
		return Biome.SNOW
	if t < 0.27:
		return Biome.TUNDRA
	if e >= WorldMap.HILL_LEVEL:
		return Biome.HILLS
	if m > 0.78 and e < 0.25 and t > 0.4:
		return Biome.SWAMP
	if t > 0.7:
		if m < 0.33:
			return Biome.DESERT
		if m > 0.6:
			return Biome.JUNGLE
		return Biome.PLAINS if m > 0.45 else Biome.STEPPE
	if m < 0.26:
		return Biome.DESERT if t > 0.5 else Biome.STEPPE
	if m < 0.4:
		return Biome.STEPPE
	if m < 0.55:
		return Biome.PLAINS
	return Biome.FOREST


# ---------------------------------------------------------------------------
# Утилиты
# ---------------------------------------------------------------------------

## k-й из 4 соседей клетки c (или -1 за краем карты).
func _neighbor(c: int, cx: int, cy: int, k: int) -> int:
	match k:
		0:
			return c - 1 if cx > 0 else -1
		1:
			return c + 1 if cx < _w - 1 else -1
		2:
			return c - _w if cy > 0 else -1
		_:
			return c + _w if cy < _h - 1 else -1


## Мульти-источниковый BFS: расстояние (в клетках, 4-связность) от клеток is_source
## по клеткам can_pass, не дальше max_dist. Недостижимые получают max_dist + 1.
func _distance_from(is_source: Callable, can_pass: Callable, max_dist: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(_n)
	dist.fill(max_dist + 1)
	var queue := PackedInt32Array()
	queue.resize(_n)
	var head := 0
	var tail := 0
	for i in _n:
		if is_source.call(i):
			dist[i] = 0
			queue[tail] = i
			tail += 1
	while head < tail:
		var c := queue[head]
		head += 1
		var d := dist[c] + 1
		if d > max_dist:
			continue
		var cx := c % _w
		var cy := c / _w
		for k in 4:
			var nb := _neighbor(c, cx, cy, k)
			if nb >= 0 and dist[nb] > d and can_pass.call(nb):
				dist[nb] = d
				queue[tail] = nb
				tail += 1
	return dist
