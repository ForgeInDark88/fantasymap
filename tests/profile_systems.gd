extends SceneTree
## Профилирование систем симуляции (среднее за год и худший вызов):
##   godot --headless --path . -s res://tests/profile_systems.gd -- [годы] [размер] [государств] [seed]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 300
	var s := MapSettings.new()
	s.apply_size_preset(int(args[1]) if args.size() > 1 else 3)
	s.nation_count = int(args[2]) if args.size() > 2 else 40
	s.world_seed = int(args[3]) if args.size() > 3 else 5
	var world := World.create(s)
	var sim := Simulation.new()
	sim.profile = true
	var t0 := Time.get_ticks_usec()
	for y in years:
		sim.step(world)
	var sum := 0
	for name in sim.timings:
		var e: Array = sim.timings[name]
		sum += e[0]
		print("%-10s %.2f мс/год, худший вызов %.1f мс" % [name, e[0] / 1000.0 / years, e[1] / 1000.0])
	print("системы  %.2f мс/год; всего с накладными %.2f мс/год" % [sum / 1000.0 / years, (Time.get_ticks_usec() - t0) / 1000.0 / years])
	quit(0)
