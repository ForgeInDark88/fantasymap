extends SceneTree
## Хэш мира: один seed → одна история. Мир на фиксированном seed живёт N лет
## дважды (в двух независимых симуляциях); хэш полного сохранения (точные
## числа) должен совпасть. Печатает хэш — по нему сверяется рефакторинг
## (до и после — одинаковый хэш).
##   godot --headless --path . -s res://tests/world_hash_test.gd -- [годы] [seed] [размер] [ожидаемый хэш]

var _failures := 0


static func world_hash(world: World) -> String:
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", true, true)
	return text.sha256_text()


static func run(years: int, seed: int, size: int) -> String:
	var s := MapSettings.new()
	s.world_seed = seed
	s.apply_size_preset(size)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in years:
		sim.step(world)
	return world_hash(world)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 80
	var seed := int(args[1]) if args.size() > 1 else 4242
	var size := int(args[2]) if args.size() > 2 else 0
	var a := run(years, seed, size)
	var b := run(years, seed, size)
	if a.is_empty():
		_failures += 1
		printerr("FAIL: хэш мира не посчитан")
	if args.size() > 3 and args[3] != a:
		_failures += 1
		printerr("FAIL: хэш %s ≠ ожидаемого %s" % [a, args[3]])
	print("world hash (%d лет, seed %d, размер %d): %s" % [years, seed, size, a])
	if a != b:
		_failures += 1
		printerr("FAIL: один seed дал разные истории: %s ≠ %s" % [a, b])
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)
