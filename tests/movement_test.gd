extends SceneTree
class_name MovementTest
## Реальное движение (этап 12.B):
##   • «без телепортов»: за сутки ни один юнит (армия, флот, пираты, герой,
##     караван, племя, чудовище, гонец, наёмники) не смещается дальше
##     MovementSystem.max_cells своего профиля — кроме допустимых телепортов
##     из data/teleports (они записаны в World.teleports);
##   • пути идут по проходимым клеткам (суша / вода по профилю);
##   • юниты не стоят вечно с непустым путём (застрявшие — баг);
##   • армии бьются там, где встретились (поле боя — рядом с обеими сторонами);
##   • сохранение → загрузка посреди марша: та же история;
##   • производительность: огромная карта, 50 государств, много войн.
##   godot --headless --path . -s res://tests/movement_test.gd -- [годы]

var _failures := 0
var _stuck_days := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 100
	_no_teleports(years)
	_save_mid_march()
	_performance()
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


## Все движущиеся юниты мира: [объект, Mover, подпись].
static func units(world: World) -> Array:
	var res: Array = []
	for a in world.armies:
		if a.alive:
			res.append([a, a.m, "армия %s" % a.kind])
	for h in world.wandering_heroes():
		if h.alive and not h.is_ruler:
			res.append([h, h.m, "герой"])
	for c in world.caravans:
		if c.alive:
			res.append([c, c.m, "караван"])
	for t in world.tribes:
		if t.alive:
			res.append([t, t.m, "племя"])
	for l in world.lairs:
		if l.alive:
			res.append([l, l.m, "чудовище"])
	for g in world.agents:
		if g.alive:
			res.append([g, g.m, "гонец"])
	for x in world.mercs:
		if x.alive:
			res.append([x, x.m, "наёмники"])
	for x in world.settlers:
		if x.alive:
			res.append([x, x.m, "поселенцы"])
	return res


func _no_teleports(years: int) -> void:
	var s := MapSettings.new()
	# Мир с войнами, торговлей и посольствами (seed 9: много войн уже к 50-му году).
	s.world_seed = 9
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	var last := {}
	var bad := 0
	var checked := 0
	var bad_path := 0
	var stuck := 0
	var battles_seen := world.recent_battles.size()
	var battle_bad := 0
	var battles_checked := 0
	var teleports_seen := 0
	var max_moved := {}
	for d in years * 360:
		var tp_before := world.teleports.size()
		sim.step_day(world)
		# Допустимые телепорты этих суток: куда (клетка) — и только из реестра.
		var allowed := {}
		for i in range(mini(tp_before, world.teleports.size()), world.teleports.size()):
			var e: Dictionary = world.teleports[i]
			_expect(MoveDB.teleport(StringName(e.kind)) != null, "телепорт вне реестра: %s" % e.kind)
			allowed[int(e.to)] = true
			teleports_seen += 1
		var now := {}
		for u in units(world):
			var key: int = (u[0] as Object).get_instance_id()
			var m: Mover = u[1]
			now[key] = m.cell
			if last.has(key) and m.cell >= 0 and int(last[key]) >= 0:
				var a := world.map.cell_pos(int(last[key]))
				var b := world.map.cell_pos(m.cell)
				var dist := maxi(absi(a.x - b.x), absi(a.y - b.y))
				var limit := MovementSystem.max_cells(world, m.profile)
				checked += 1
				max_moved[m.profile] = maxi(int(max_moved.get(m.profile, 0)), dist)
				if dist > limit and not allowed.has(m.cell):
					bad += 1
					if bad <= 5:
						_expect(false, "телепорт: %s прыгнул на %d клеток за сутки (предел %d)" % [u[2], dist, limit])
			# Застрял: путь есть, а клетка не меняется месяцами (армии в затворе ждут — до 60 суток).
			if m.walking() and m.moved == 0:
				_stuck_days[key] = int(_stuck_days.get(key, 0)) + 1
				if int(_stuck_days[key]) == 90:
					stuck += 1
					var extra := ""
					if u[0] is Army:
						var ar: Army = u[0]
						extra = " (состояние %s, blocked %s, standoff %d, путь %d, следующая клетка суша %s, война %d)" % [ar.state, ar.blocked, ar.standoff, ar.m.remaining(),
							world.map.is_land(ar.m.next_cell()), ar.war]
					_expect(false, "застрял: %s стоит 90 суток с непустым путём%s" % [u[2], extra])
			else:
				_stuck_days.erase(key)
			# Путь — по проходимым клеткам.
			if d % 30 == 0 and m.walking():
				var prof := MoveDB.profile(m.profile)
				for c in m.ahead():
					var land := world.map.is_land(c)
					if (prof.water_only and land) or (not prof.water_only and not land and not prof.can_sail):
						bad_path += 1
						break
		last = now
		# Битвы — там, где сошлись армии сторон.
		if world.recent_battles.size() != battles_seen:
			var b: Dictionary = world.recent_battles[world.recent_battles.size() - 1]
			battles_seen = world.recent_battles.size()
			var cell := int(b.get("cell", -1))
			if cell >= 0:
				battles_checked += 1
				var near := 0
				var cp := world.map.cell_pos(cell)
				for a in world.armies:
					if a.alive and a.war == int(b.war) and a.kind == &"land":
						var ap := world.map.cell_pos(a.cell)
						if maxi(absi(ap.x - cp.x), absi(ap.y - cp.y)) <= world.gd(ArmySystem.CONTACT) + 2:
							near += 1
				if near < 2:
					battle_bad += 1
	print("без телепортов: проверено %d юнито-суток, прыжков %d, допустимых телепортов %d; наибольший шаг за сутки %s" % [checked, bad, teleports_seen, max_moved])
	print("пути по негодным клеткам: %d; застрявших: %d; битв проверено %d, вдали от армий %d" % [bad_path, stuck, battles_checked, battle_bad])
	_expect(checked > 10000, "мало юнитов в пути — проверка ничего не проверила")
	for p in [&"army", &"hero", &"caravan"]:
		_expect(max_moved.has(p), "в проверке нет юнитов «%s»" % p)
	_expect(bad == 0, "юниты прыгают дальше своей скорости")
	_expect(bad_path == 0, "пути через непроходимые клетки")
	_expect(battles_checked == 0 or battle_bad * 5 <= battles_checked, "битвы не там, где встретились армии")


func _hash(world: World) -> String:
	world.update_label_anchors()
	return JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", true, true).sha256_text()


## Сохранение посреди пути: армии, герои, караваны в дороге — продолжение то же.
func _save_mid_march() -> void:
	var s := MapSettings.new()
	s.world_seed = 9
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	var found := false
	for m in 2400:
		sim.step_month(world)
		var walking := 0
		for u in units(world):
			if (u[1] as Mover).walking():
				walking += 1
		if walking >= 3 and world.armies.any(func(a: Army) -> bool: return a.alive and a.m.walking()):
			found = true
			break
	_expect(found, "не нашлось армий и героев в пути")
	for d in 3:
		sim.step_day(world)
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	ArmySystem.compact(world)
	var sim2 := Simulation.new()
	for d in 360 * 2:
		sim.step_day(world)
		sim2.step_day(loaded)
	var same := _hash(world) == _hash(loaded)
	_expect(same, "после загрузки посреди марша история разошлась")
	print("сохранение посреди пути: продолжение %s" % ("совпадает" if same else "РАЗОШЛОСЬ"))


## Огромная карта, 50 государств, много войн: худшие сутки и средний месяц.
func _performance() -> void:
	var s := MapSettings.new()
	s.world_seed = 11
	s.apply_size_preset(3)
	s.nation_count = 50
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 60:
		sim.step(world)
	# Войны между соседями — много армий в поле.
	var declared := 0
	for n in world.nations:
		if declared >= 20 or not n.alive:
			continue
		for o in n.borders:
			if world.nations[o].alive and world.diplomacy.war_between(n.id, o) == null:
				world.diplomacy.declare_war(world, n.id, o, &"territory")
				declared += 1
				break
	var worst := 0
	var total := 0
	var days := 360 * 2
	for d in days:
		var t0 := Time.get_ticks_usec()
		sim.step_day(world)
		var dt := Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
	var walking := 0
	for u in units(world):
		if (u[1] as Mover).walking():
			walking += 1
	print("огромная карта, 50 государств, %d войн: месяц %.1f мс, худшие сутки %.1f мс, юнитов в пути %d" % [world.diplomacy.wars.size(),
		total / 1000.0 / (days / 30.0), worst / 1000.0, walking])
	_expect(worst < 50000, "сутки симуляции дольше 50 мс")
	# Этап 12.C: державы растут цельными пятнами — общих границ больше, и из 20
	# объявленных войн к концу идут ~25 (было ~8), армий в поле ~60: бюджет месяца
	# 45 мс (≈8 мкс на армию в сутки; ускорение армий — этап 12.F).
	_expect(total / 1000.0 / (days / 30.0) < 45.0, "месяц симуляции дольше 45 мс")


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
