extends SceneTree
## Профилирование систем симуляции по отдельности:
##   godot --headless --path . -s res://tests/profile_systems.gd -- [годы] [размер] [государств]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 300
	var s := MapSettings.new()
	s.world_seed = 5
	s.apply_size_preset(int(args[1]) if args.size() > 1 else 3)
	s.nation_count = int(args[2]) if args.size() > 2 else 40
	var world := World.create(s)
	var sim := Simulation.new()
	var names := ["economy", "population", "expansion", "cities", "rulers"]
	var systems: Array = [sim.economy, sim.population, sim.expansion, sim.cities, sim.rulers]
	var total := PackedInt64Array()
	total.resize(systems.size())
	for y in years:
		world.year += 1
		for nation in world.nations:
			for k in systems.size():
				var t0 := Time.get_ticks_usec()
				systems[k].tick(world, nation)
				total[k] += Time.get_ticks_usec() - t0
	for k in systems.size():
		print("%-10s %.2f мс/год" % [names[k], total[k] / 1000.0 / years])
	quit(0)
