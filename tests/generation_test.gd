extends SceneTree
## Headless-проверка генератора:
##   godot --headless --path . -s res://tests/generation_test.gd -- [out_dir]
## Генерирует карты с разными seed и размерами, проверяет инварианты,
## печатает статистику и время; при указании out_dir сохраняет PNG.

var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else ""
	BiomeDB.ensure_loaded()

	var cases := [
		[1, 1, 0.40, 4], [2, 1, 0.30, 1], [3, 1, 0.55, 7],
		[4, 0, 0.40, 3], [5, 2, 0.40, 5], [6, 3, 0.35, 6],
	]
	for c in cases:
		var s := MapSettings.new()
		s.world_seed = c[0]
		s.apply_size_preset(c[1])
		s.land_fraction = c[2]
		s.continents = c[3]
		_run_case(s, out_dir)

	_check_determinism()
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _run_case(s: MapSettings, out_dir: String) -> void:
	var t0 := Time.get_ticks_msec()
	var map := MapGenerator.new().generate(s)
	var t_gen := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var img := MapPainter.paint(map, MapMode.BIOMES)
	var t_paint := Time.get_ticks_msec() - t0

	var counts := PackedInt32Array()
	counts.resize(Biome.COUNT)
	var land := 0
	var rivers := 0
	for i in map.cell_count():
		counts[map.biome[i]] += 1
		if map.elevation[i] >= 0.0:
			land += 1
		if map.river[i] > 0:
			rivers += 1
		if map.river[i] > 0 and not map.is_land(i):
			_fail("река на воде в клетке %d" % i)
			break
	var n := float(map.cell_count())
	var parts: Array[String] = []
	for b in Biome.COUNT:
		parts.append("%s %.1f%%" % [BiomeDB.get_def(b).id, counts[b] * 100.0 / n])
	print("seed=%d %dx%d land=%.2f cont=%d | gen %d ms, paint %d ms | суша %.1f%%, реки %.1f%%"
			% [s.world_seed, s.width, s.height, s.land_fraction, s.continents, t_gen, t_paint,
				land * 100.0 / n, rivers * 100.0 / n])
	print("    ", ", ".join(parts))
	if absf(land / n - s.land_fraction) > 0.01:
		_fail("доля суши %.3f вместо %.3f" % [land / n, s.land_fraction])
	if out_dir != "":
		img.save_png(out_dir.path_join("map_%d_%dx%d.png" % [s.world_seed, s.width, s.height]))
		if s.world_seed == 1:
			for mode in [MapMode.HEIGHT, MapMode.TEMPERATURE, MapMode.MOISTURE]:
				MapPainter.paint(map, mode).save_png(out_dir.path_join("map_1_mode%d.png" % mode))


func _check_determinism() -> void:
	var s := MapSettings.new()
	s.world_seed = 777
	s.apply_size_preset(0)
	var a := MapGenerator.new().generate(s)
	var b := MapGenerator.new().generate(s)
	if a.biome != b.biome or a.river != b.river or a.elevation != b.elevation:
		_fail("генерация недетерминирована для одного seed")


func _fail(msg: String) -> void:
	_failures += 1
	printerr("FAIL: ", msg)
