extends SceneTree
## Профилирование систем симуляции по отдельности (повторяет Simulation.step_month):
##   godot --headless --path . -s res://tests/profile_systems.gd -- [годы] [размер] [государств] [seed]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 300
	var s := MapSettings.new()
	s.world_seed = int(args[3]) if args.size() > 3 else 5
	s.apply_size_preset(int(args[1]) if args.size() > 1 else 3)
	s.nation_count = int(args[2]) if args.size() > 2 else 40
	var world := World.create(s)
	var sim := Simulation.new()
	var names := ["economy", "population", "expansion", "cities", "rulers", "unrest", "events", "diplomacy", "enclaves"]
	var systems: Array = [sim.economy, sim.population, sim.expansion, sim.cities, sim.rulers, sim.unrest, sim.events]
	var total := PackedInt64Array()
	total.resize(names.size() + 4)
	var worst := PackedInt64Array()
	worst.resize(names.size() + 4)
	for m in years * 12:
		world.month += 1
		if world.month >= 12:
			world.month = 0
			world.year += 1
			var y0 := Time.get_ticks_usec()
			sim.events.flush_pending(world)
			sim.diplomacy.tick_year(world)
			world.record_history()
			total[names.size()] += Time.get_ticks_usec() - y0
		for nation in world.nations:
			if not nation.alive or nation.id % 12 != world.month:
				continue
			for k in systems.size():
				var t0 := Time.get_ticks_usec()
				systems[k].tick(world, nation)
				var dt := Time.get_ticks_usec() - t0
				total[k] += dt
				worst[k] = maxi(worst[k], dt)
			var t1 := Time.get_ticks_usec()
			sim.diplomacy.tick_nation(world, nation)
			total[7] += Time.get_ticks_usec() - t1
			worst[7] = maxi(worst[7], Time.get_ticks_usec() - t1)
			t1 = Time.get_ticks_usec()
			sim.enclaves.tick(world, nation)
			total[8] += Time.get_ticks_usec() - t1
			worst[8] = maxi(worst[8], Time.get_ticks_usec() - t1)
		var g0 := Time.get_ticks_usec()
		sim.wars.tick_month(world)
		var g1 := Time.get_ticks_usec()
		sim.heroes.tick_month(world)
		var g2 := Time.get_ticks_usec()
		world.cleanup_dead()
		total[names.size() + 1] += g1 - g0
		total[names.size() + 2] += g2 - g1
		total[names.size() + 3] += Time.get_ticks_usec() - g2
		worst[names.size() + 1] = maxi(worst[names.size() + 1], g1 - g0)
		worst[names.size() + 2] = maxi(worst[names.size() + 2], g2 - g1)
	names.append_array(["new_year", "wars", "heroes", "cleanup"])
	var sum := 0
	for k in names.size():
		sum += total[k]
		print("%-10s %.2f мс/год, худший вызов %.1f мс" % [names[k], total[k] / 1000.0 / years, worst[k] / 1000.0])
	print("ИТОГО      %.2f мс/год" % (sum / 1000.0 / years))
	quit(0)
