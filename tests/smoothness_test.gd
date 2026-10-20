extends SceneTree
## Headless-проверка этапа 11.A (плавность):
##   • настройки плавности пишутся и читаются (user://settings.cfg, раздел smooth);
##   • настройки не меняют мир: хэш после N лет одинаков при «Мгновенно» и
##     «Максимально плавно», а также при разной «нарезке» дней по кадрам (FPS);
##   • сглаживание не зависит от FPS: камера при delta 1/30 и 1/144 за одно время
##     приходит в одну точку, цели сходятся за конечное время, перелёт завершается;
##   • растянутые бедствия дают те же итоговые потери, что мгновенные.
##   godot --headless --path . -s res://tests/smoothness_test.gd -- [годы]

const CFG := "user://_test_smooth.cfg"
var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 40
	_settings()
	_camera()
	_stages()
	_world_independent(years)
	SmoothSettings.apply_preset("soft")
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _settings() -> void:
	DirAccess.remove_absolute(CFG)
	SmoothSettings.apply_preset("max")
	SmoothSettings.ui_anim = false
	SmoothSettings.save_settings(CFG)
	SmoothSettings.apply_preset("instant")
	_expect(SmoothSettings.camera == 0 and not SmoothSettings.border_anim, "пресет «Мгновенно» не применился")
	SmoothSettings.load_settings(CFG)
	_expect(SmoothSettings.camera == 2 and not SmoothSettings.ui_anim and SmoothSettings.border_anim and SmoothSettings.event_fx,
		"настройки плавности не прочитались")
	# Чужие разделы файла не трогаются.
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("audio", "music", 0.25)
	cfg.save(CFG)
	SmoothSettings.save_settings(CFG)
	cfg = ConfigFile.new()
	cfg.load(CFG)
	_expect(is_equal_approx(float(cfg.get_value("audio", "music", 0.0)), 0.25), "сохранение плавности стёрло настройки звука")
	DirAccess.remove_absolute(CFG)
	# Сглаживание: доля пути не зависит от нарезки времени.
	var a := 0.0
	for i in 30:
		a = SmoothSettings.damp(a, 1.0, 10.0, 1.0 / 30.0)
	var b := 0.0
	for i in 144:
		b = SmoothSettings.damp(b, 1.0, 10.0, 1.0 / 144.0)
	_expect(absf(a - b) < 1e-6 and absf(a - (1.0 - exp(-10.0))) < 1e-6, "сглаживание зависит от FPS (%.6f ≠ %.6f)" % [a, b])
	_expect(SmoothSettings.factor(0.0, 0.016) == 1.0, "мгновенный режим сглаживает")


func _camera_run(fps: float, seconds: float, setup: Callable) -> Array:
	var cam := MapCamera.new()
	root.add_child(cam)
	cam.bounds = Rect2(0, 0, 4000, 3000)
	cam.position = Vector2(500, 500)
	cam.target_position = cam.position
	cam.zoom = Vector2.ONE
	cam.target_zoom = 1.0
	setup.call(cam)
	var frames := int(round(seconds * fps))
	for i in frames:
		cam.step(1.0 / fps)
	var res := [cam.position, cam.zoom.x, cam.is_flying()]
	cam.queue_free()
	return res


func _camera() -> void:
	for level in [1, 2]:
		SmoothSettings.camera = level
		var pan := func(cam: MapCamera) -> void:
			cam.target_position = Vector2(2600, 1800)
			cam.target_zoom = 3.0
		var a := _camera_run(30.0, 1.0, pan)
		var b := _camera_run(144.0, 1.0, pan)
		_expect((a[0] as Vector2).distance_to(b[0]) < 0.5 and absf(float(a[1]) - float(b[1])) < 0.01,
			"камера зависит от FPS: %s/%.3f ≠ %s/%.3f" % [a[0], a[1], b[0], b[1]])
		var c := _camera_run(60.0, 4.0, pan)
		_expect((c[0] as Vector2).distance_to(Vector2(2600, 1800)) < 0.5 and absf(float(c[1]) - 3.0) < 0.01, "камера не дошла до цели за 4 с")
		# Перелёт по дуге завершается за конечное время при любом FPS.
		var fly := func(cam: MapCamera) -> void: cam.fly_to(Vector2(3500, 2500), 2.0)
		for fps in [24.0, 60.0, 240.0]:
			var f := _camera_run(fps, MapCamera.FLIGHT_MAX * 1.4 + 0.1, fly)
			_expect(not bool(f[2]) and (f[0] as Vector2).distance_to(Vector2(3500, 2500)) < 0.01 and absf(float(f[1]) - 2.0) < 0.001,
				"перелёт не завершился (fps %d): %s" % [fps, f])
	# «Мгновенно» — сразу на месте.
	SmoothSettings.camera = 0
	var i := _camera_run(60.0, 1.0 / 60.0, func(cam: MapCamera) -> void: cam.fly_to(Vector2(1000, 900), 4.0))
	_expect((i[0] as Vector2).distance_to(Vector2(1000, 900)) < 0.01 and absf(float(i[1]) - 4.0) < 0.001, "мгновенная камера не мгновенна")
	SmoothSettings.camera = 1


func _stages() -> void:
	var s := MapSettings.new()
	s.world_seed = 3
	s.apply_size_preset(0)
	var world := World.create(s)
	var a := world.nations[0]
	var b := world.nations[1]
	var pop_a := a.pop.duplicate()
	var pop_b := b.pop.duplicate()
	StageSystem.hit(world, a, 0.12, 0.0, 0.0, 0.0, 0.0)
	StageSystem.push(world, b, 6, 0.12, 0.0, 0.0, 0.0, 0.0, &"plague")
	var first := b.pop[b.race.index]
	_expect(first < pop_b[b.race.index] and first > pop_b[b.race.index] * 0.88, "растянутый удар ударил сразу целиком или не ударил")
	for m in 7:
		StageSystem.tick_month(world)
	_expect(world.staged_effects.is_empty(), "удар не закончился")
	var ra := a.pop[a.race.index] / pop_a[a.race.index]
	var rb := b.pop[b.race.index] / pop_b[b.race.index]
	_expect(absf(ra - rb) < 1e-4 and absf(ra - 0.88) < 1e-4, "итог растянутого удара ≠ мгновенного (%.5f, %.5f)" % [ra, rb])
	var total := 0.0
	for i in 6:
		total += StageSystem.weight(i, 6)
	_expect(absf(total - 1.0) < 1e-6 and StageSystem.weight(1, 6) > StageSystem.weight(5, 6), "кривая удара неверна")


func _hash(world: World) -> String:
	return JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", true, true).sha256_text()


func _world_independent(years: int) -> void:
	var s := MapSettings.new()
	s.world_seed = 2468
	s.apply_size_preset(0)
	SmoothSettings.apply_preset("instant")
	var w1 := World.create(s)
	var sim1 := Simulation.new()
	for y in years:
		sim1.step(w1)
	SmoothSettings.apply_preset("max")
	var w2 := World.create(s)
	var sim2 := Simulation.new()
	# Разная «нарезка» дней по кадрам — как при плавной скорости и разном FPS.
	var vis := RandomNumberGenerator.new()
	vis.seed = 99
	var days := years * Simulation.MONTHS * Simulation.DAYS
	while days > 0:
		var chunk := mini(days, vis.randi_range(1, 37))
		for d in chunk:
			sim2.step_day(w2)
		days -= chunk
	var h1 := _hash(w1)
	var h2 := _hash(w2)
	print("хэш при «Мгновенно»: %s…, при «Максимально плавно»: %s…" % [h1.left(12), h2.left(12)])
	_expect(h1 == h2, "настройки плавности или нарезка кадров изменили мир")


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
