extends SceneTree
## Записи боёв (этап 12.E): битвы, поединки и встречи попадают в журнал с
## клеткой на карте; реплик не меньше 150; пересказ детерминирован (то же зерно —
## тот же текст, разные бои — разный), без незаполненных подстановок, не трогает
## мир; журнал ограничен и переживает сохранение.
##   godot --headless --path . -s res://tests/battle_record_test.gd

var _failures := 0


func _initialize() -> void:
	var total := BattleReplay.total_lines()
	print("реплик в data/battle_lines: %d" % total)
	_expect(total >= 150, "реплик меньше 150: %d" % total)
	for ph in [&"opening", &"clash", &"turn", &"victory", &"rout", &"aftermath", &"duel_open", &"duel_exchange",
			&"duel_kill", &"duel_spare", &"meet_open", &"meet_friend", &"meet_rival", &"meet_talk"]:
		_expect(not BattleReplay.lines(ph).is_empty(), "нет реплик фазы %s" % ph)
	var s := MapSettings.new()
	s.world_seed = 4242
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 80:
		sim.step(world)
	var kinds := {}
	for r in world.battle_log:
		kinds[r.kind] = kinds.get(r.kind, 0) + 1
		_expect(r.cell >= 0 and r.cell < world.map.cell_count(), "запись без клетки")
		_expect(r.sides.size() == 2, "у записи не две стороны")
	print("журнал: %d записей (всего было %d), по видам %s" % [world.battle_log.size(), world.battle_serial, kinds])
	_expect(kinds.get(&"battle", 0) > 0, "в журнале нет битв")
	_expect(kinds.get(&"duel", 0) + kinds.get(&"meeting", 0) > 0, "в журнале нет поединков и встреч")
	_expect(world.battle_log.size() <= BattleLog.LIMIT, "журнал без предела")
	# Пересказ: детерминирован, разный у разных боёв, без «{…}», мир не меняется.
	var before := _hash(world)
	var texts := {}
	var bad := 0
	for r in world.battle_log:
		var a := BattleReplay.script(r, world)
		var b := BattleReplay.script(r, world)
		if JSON.stringify(a) != JSON.stringify(b):
			bad += 1
		for st in a:
			if String(st.text).contains("{") or String(st.text).is_empty():
				_expect(false, "незаполненная реплика: %s" % st.text)
				break
		texts[JSON.stringify(a.map(func(x: Dictionary) -> String: return x.text))] = true
	_expect(bad == 0, "пересказ не детерминирован (%d записей)" % bad)
	_expect(texts.size() * 2 >= world.battle_log.size(), "пересказы слишком однообразны: %d разных из %d" % [texts.size(), world.battle_log.size()])
	_expect(_hash(world) == before, "просмотр изменил мир")
	var sample := BattleReplay.script(world.battle_log[world.battle_log.size() - 1], world)
	print("пример: %s" % " / ".join(sample.map(func(x: Dictionary) -> String: return x.text)))
	# Сохранение: журнал и пересказы те же.
	var text := JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", false, true)
	var loaded := SaveSystem.from_dict(SaveSystem.unexact(JSON.parse_string(text)))
	_expect(loaded.battle_log.size() == world.battle_log.size() and loaded.battle_serial == world.battle_serial, "журнал не сохранился")
	var same := true
	for i in world.battle_log.size():
		if JSON.stringify(BattleReplay.script(world.battle_log[i], world)) != JSON.stringify(BattleReplay.script(loaded.battle_log[i], loaded)):
			same = false
			break
	_expect(same, "после загрузки пересказ другой")
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _hash(world: World) -> String:
	world.update_label_anchors()
	return JSON.stringify(SaveSystem.exact(SaveSystem.to_dict(world)), "", true, true).sha256_text()


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
