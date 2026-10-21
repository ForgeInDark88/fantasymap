extends SceneTree
## Средние показатели мира по годам — эталон для калибровки баланса (этап 12):
## доля занятой суши, число государств и городов, войны и их длительность,
## население, средняя площадь государства, одиночные клетки и куски территорий.
## Площади — в базовых клетках (сырые клетки / grid_scale²), чтобы числа ×1 и ×2
## сравнивались напрямую.
##   godot --headless --path . -s res://tests/baseline_metrics.gd -- [годы] [seed,seed,…] [размеры] [файл.json]
## Пример: -- 300 1,2,3,4,5,6 0,1 user://baseline.json

const CHECKPOINTS := [50, 100, 200, 300, 400, 500]


static func measure(world: World) -> Dictionary:
	var map := world.map
	var land := 0
	for i in map.cell_count():
		if map.is_land(i):
			land += 1
	var owned := 0
	var alive := 0
	var pop := 0.0
	for n in world.nations:
		if n.alive:
			alive += 1
			owned += n.cells.size()
			pop += n.population
	var cities := 0
	for c in world.cities:
		if c.alive:
			cities += 1
	var wars := world.diplomacy.wars.size() + world.diplomacy.past_wars.size()
	var dur := 0.0
	var ended := 0
	for w in world.diplomacy.past_wars:
		if w.end_year >= 0:
			dur += w.end_year - w.start_year
			ended += 1
	var frag := fragmentation(world)
	var area := 1.0
	if world.get("grid_scale") != null:
		area = float(int(world.get("grid_scale")) * int(world.get("grid_scale")))
	return {
		"land_share": float(owned) / maxf(1.0, land),
		"nations": alive,
		"cities": cities,
		"wars": wars,
		"war_years": dur / maxf(1.0, ended),
		"population": pop,
		"mean_area": float(owned) / maxf(1.0, alive) / area,
		"isolated": frag.x,
		"pieces_per_nation": float(frag.y) / maxf(1.0, alive),
	}


## x — клетки без соседа-своего (4-связность), y — число связных кусков всех государств.
static func fragmentation(world: World) -> Vector2i:
	var map := world.map
	var w := map.width
	var n := map.cell_count()
	var owner := world.owner
	var isolated := 0
	var pieces := 0
	var seen := PackedByteArray()
	seen.resize(n)
	var queue := PackedInt32Array()
	for c in n:
		var o := owner[c]
		if o < 0:
			continue
		var x := c % w
		var lone := true
		if x > 0 and owner[c - 1] == o:
			lone = false
		elif x < w - 1 and owner[c + 1] == o:
			lone = false
		elif c >= w and owner[c - w] == o:
			lone = false
		elif c + w < n and owner[c + w] == o:
			lone = false
		if lone:
			isolated += 1
		if seen[c] != 0:
			continue
		pieces += 1
		seen[c] = 1
		queue.resize(0)
		queue.append(c)
		var qi := 0
		while qi < queue.size():
			var cur := queue[qi]
			qi += 1
			var cx := cur % w
			for k in 4:
				var nb := -1
				match k:
					0: nb = cur - 1 if cx > 0 else -1
					1: nb = cur + 1 if cx < w - 1 else -1
					2: nb = cur - w
					3: nb = cur + w
				if nb >= 0 and nb < n and seen[nb] == 0 and owner[nb] == o:
					seen[nb] = 1
					queue.append(nb)
	return Vector2i(isolated, pieces)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 300
	var seeds: Array = (args[1] if args.size() > 1 else "1,2,3").split(",")
	var sizes: Array = (args[2] if args.size() > 2 else "1").split(",")
	var out_path: String = args[3] if args.size() > 3 else ""
	var result := {}
	for size_s in sizes:
		var size := int(size_s)
		var sums := {}
		for seed_s in seeds:
			var s := MapSettings.new()
			s.world_seed = int(seed_s)
			s.apply_size_preset(size)
			var world := World.create(s)
			var sim := Simulation.new()
			for y in range(1, years + 1):
				sim.step(world)
				if CHECKPOINTS.has(y):
					var m := measure(world)
					print("size %d seed %s year %d: %s" % [size, seed_s, y, JSON.stringify(m)])
					var acc: Dictionary = sums.get(y, {})
					for k in m:
						acc[k] = float(acc.get(k, 0.0)) + float(m[k]) / seeds.size()
					sums[y] = acc
		result[str(size)] = sums
		for y in sums:
			var line := []
			for k in sums[y]:
				line.append("%s=%.3f" % [k, sums[y][k]])
			print("СРЕДНЕЕ size %d year %d: %s" % [size, y, " ".join(line)])
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(result, "  "))
	print("OK")
	quit(0)
