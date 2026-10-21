extends SceneTree
## Масштаб сетки (этап 12.A): перевод единиц GridScale; мир ×1 — побитно тот
## же, что до введения масштаба (хэш базовой линии); генерация ×2
## детерминирована и похожа на ×1 (та же доля суши, те же очертания, столько же
## регионов); мир ×2 живёт без ошибок; сохранение ×2 сжато и продолжает
## историю так же; старое сохранение без поля масштаба грузится как ×1;
## в проверяемых файлах нет «сырых» констант размера клетки.
##   godot --headless --path . -s res://tests/grid_scale_test.gd

## Хэш базовой линии этапа 12 (README): 80 лет, seed 4242, маленькая карта, ×1.
const BASELINE_HASH := "bf0c62bfea2334de65173b48116a694a5f5a8b084da5c132d7f674c8541f5421"
## Файлы и шаблоны «сырых» констант размера клетки, которых там быть не должно.
const CHECKED := ["res://scripts/render/map_overlay.gd", "res://scripts/render/map_renderer.gd",
	"res://scripts/sim/systems/tribe_system.gd", "res://scripts/sim/systems/lair_system.gd",
	"res://scripts/sim/systems/enclave_system.gd", "res://scripts/sim/systems/city_system.gd",
	"res://scripts/sim/systems/expansion_system.gd", "res://scripts/sim/systems/underground_system.gd",
	"res://scripts/sim/systems/climate_system.gd", "res://scripts/sim/systems/crisis_system.gd",
	"res://scripts/sim/world_seeder.gd", "res://scripts/sim/systems/economy_system.gd", "res://ui/nation_panel.gd"]
const FORBIDDEN := [
	"(?<!BASE_)CELL_SIZE",                              # размер клетки — MapRenderer.cell_size
	"cells\\.size\\(\\) *[<>]=? *([3-9]|[1-9][0-9]+)\\b",  # порог по числу клеток — world.gai()
	"cell_count *[<>]=? *([3-9]|[1-9][0-9]+)\\b",
	"distance_to\\([^)]*\\)\\) *<=? *[0-9]+\\.[0-9]",    # радиус в клетках — world.gd()
]

var _failures := 0


func _initialize() -> void:
	_units()
	_baseline_x1()
	_generation_x2()
	_world_x2_and_save()
	_old_save()
	_grep()
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _units() -> void:
	for v in [0.0, 1.0, 7.5, 1234.25]:
		_expect(GridScale.dist(1, v) == v and GridScale.area(1, v) == v and GridScale.per_cell(1, v) == v
				and GridScale.base(1, v) == v and GridScale.speed(1, v) == v, "×1: перевод единиц меняет %s" % v)
		_expect(is_equal_approx(GridScale.base(2, GridScale.area(2, v)), v), "×2: площадь туда-обратно %s" % v)
		_expect(is_equal_approx(GridScale.per_cell(2, v) * 4.0, v), "×2: ёмкость на клетку ÷4 %s" % v)
		_expect(is_equal_approx(GridScale.base_len(3, GridScale.dist(3, v)), v), "×3: расстояние туда-обратно %s" % v)
	_expect(GridScale.area_i(2, 90) == 360 and GridScale.dist_i(2, 6) == 12 and GridScale.base_i(2, 361) == 90, "×2: целые единицы")
	_expect(GridScale.valid(5) == 1 and GridScale.valid(2) == 2, "недопустимый масштаб → ×1")
	print("единицы: dist/area/per_cell/base — симметричны, ×1 — без изменений")


func _baseline_x1() -> void:
	var s := MapSettings.new()
	s.world_seed = 4242
	s.apply_size_preset(0)
	var world := World.create(s)
	_expect(world.grid_scale == 1 and world.map.width == 256, "по умолчанию — ×1, 256 клеток")
	var sim := Simulation.new()
	for y in 80:
		sim.step(world)
	var h := _hash(world)
	# Побитное совпадение с базовой линией проверено на этапе 12.A (коммит «12.A…»);
	# с 12.B мир ×1 иной (настоящее движение) — здесь хэш лишь печатается, а
	# детерминизм проверяет world_hash_test.
	print("×1: хэш %s (базовая линия 12.A — %s, совпадал до этапа 12.B)" % [h.left(12), BASELINE_HASH.left(12)])


static func _hash(world: World) -> String:
	return JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", true, true).sha256_text()


static func _settings(seed: int, size: int, gs: int) -> MapSettings:
	var s := MapSettings.new()
	s.world_seed = seed
	s.apply_size_preset(size)
	s.grid_scale = gs
	return s


func _generation_x2() -> void:
	var m1 := MapGenerator.new().generate(_settings(77, 0, 1))
	var m2 := MapGenerator.new().generate(_settings(77, 0, 2))
	var m2b := MapGenerator.new().generate(_settings(77, 0, 2))
	_expect(m2.width == 512 and m2.height == 320, "×2: размер сетки 512×320")
	_expect(m2.biome == m2b.biome and m2.elevation == m2b.elevation and m2.river == m2b.river, "×2: один seed — разные карты")
	var land1 := 0
	var land2 := 0
	for i in m1.cell_count():
		if m1.is_land(i):
			land1 += 1
	for i in m2.cell_count():
		if m2.is_land(i):
			land2 += 1
	_expect(absf(land2 / 4.0 - land1) / land1 < 0.01, "×2: доля суши %d/4 ≠ %d" % [land2, land1])
	# Очертания те же: суша/вода блоков 2×2 совпадает с клеткой ×1 в подавляющем большинстве.
	var same := 0
	for y in m1.height:
		for x in m1.width:
			var votes := 0
			for k in 4:
				if m2.is_land(m2.index_of(x * 2 + k % 2, y * 2 + k / 2)):
					votes += 1
			if (votes >= 2) == m1.is_land(m1.index_of(x, y)):
				same += 1
	var share := float(same) / m1.cell_count()
	_expect(share > 0.95, "×2: очертания суши разошлись с ×1 (совпадение %.1f%%)" % (share * 100.0))
	var r1 := 0
	var r2 := 0
	for i in m1.cell_count():
		if m1.river[i] > 0:
			r1 += 1
	for i in m2.cell_count():
		if m2.river[i] > 0:
			r2 += 1
	# Реки те же, но в клетках тоньше: длина в клетках ×2, а не площадь ×4.
	_expect(r2 > r1 * 1.4 and r2 < r1 * 3.0, "×2: реки «разбухли» или пропали (%d против %d)" % [r2, r1])
	print("×2: генерация детерминирована, суша %.1f%% совпадает с ×1, клеток рек %d против %d" % [share * 100.0, r2, r1])


func _world_x2_and_save() -> void:
	var w1 := World.create(_settings(5, 0, 1))
	var w2 := World.create(_settings(5, 0, 2))
	_expect(w2.grid_scale == 2, "×2: мир не знает масштаба")
	_expect(absf(w2.regions.size() - w1.regions.size()) / w1.regions.size() < 0.2, "×2: регионов %d против %d" % [w2.regions.size(), w1.regions.size()])
	var cap1 := 0.0
	var cap2 := 0.0
	for n in w1.nations:
		cap1 += n.total_capacity() / maxf(1.0, n.base_area)
	for n in w2.nations:
		cap2 += n.total_capacity() / maxf(1.0, n.base_area)
	_expect(absf(cap2 / maxf(1.0, cap1) - 1.0) < 0.25, "×2: ёмкость земли на базовую клетку разошлась (%.0f против %.0f)" % [cap2, cap1])
	var sim := Simulation.new()
	for y in 20:
		sim.step(w2)
	var alive := 0
	for n in w2.nations:
		if n.alive:
			alive += 1
	_expect(alive > 0, "×2: все государства пали за 20 лет")
	var data := SaveSystem.to_dict(w2)
	_expect(int(data.settings.get("grid_scale", 1)) == 2, "×2: масштаб не записан в сохранение")
	_expect(str(data.cells.owner).begins_with("z:"), "×2: массив владельцев не сжат")
	# Как в файле сохранения: точные числа (exact/unexact), JSON.
	var text := JSON.stringify(SaveSystem.exact(data), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded.grid_scale == 2 and loaded.map.width == 512, "×2: загрузка потеряла масштаб")
	var sim_a := Simulation.new()
	var sim_b := Simulation.new()
	for y in 5:
		sim_a.step(w2)
		sim_b.step(loaded)
	# Точки подписей — для интерфейса (обновляет оверлей), в истории не участвуют.
	w2.update_label_anchors()
	loaded.update_label_anchors()
	var same := _hash(w2) == _hash(loaded)
	_expect(same, "×2: после загрузки история пошла иначе")
	print("×2: мир живёт, сохранение %.1f МБ (сжатое), продолжение после загрузки %s" % [text.length() / 1048576.0, "совпадает" if same else "РАЗОШЛОСЬ"])


func _old_save() -> void:
	var w := World.create(_settings(9, 0, 1))
	var data := SaveSystem.to_dict(w)
	_expect(not data.settings.has("grid_scale"), "×1: в сохранении лишнее поле масштаба (меняет формат)")
	_expect(not str(data.cells.owner).begins_with("z:"), "×1: массивы сжаты (меняет формат)")
	var loaded := SaveSystem.from_dict(JSON.parse_string(JSON.stringify(data)))
	_expect(loaded.grid_scale == 1 and loaded.map.width == 256, "старое сохранение (без поля) — не ×1")
	print("старые сохранения: без поля масштаба — ×1")


func _grep() -> void:
	var bad := 0
	for path in CHECKED:
		var text := FileAccess.get_file_as_string(path)
		var lines := text.split("\n")
		for pat in FORBIDDEN:
			var re := RegEx.create_from_string(pat)
			for i in lines.size():
				var line: String = lines[i]
				if line.strip_edges().begins_with("#") or line.strip_edges().begins_with("##"):
					continue
				if re.search(line) != null:
					bad += 1
					_expect(false, "%s:%d — «сырая» константа размера клетки: %s" % [path, i + 1, line.strip_edges()])
	print("поиск «сырых» констант: %d файлов, нарушений %d" % [CHECKED.size(), bad])


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
