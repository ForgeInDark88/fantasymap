extends SceneTree
## Headless-проверка этапа 10.5: синтез без внешних файлов — темы всех
## контекстов и лейтмотивы рас (длина петли, без перегрузки, повторяемость,
## разные расы звучат по-разному), звуки событий; выбор контекста по миру;
## AudioManager в headless выключен и не падает; настройки в settings.cfg.
##   godot --headless --path . -s res://tests/audio_test.gd

const CFG := "user://_test_settings.cfg"
var _failures := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var a := Synth.render_theme(Synth.theme(&"peace", &"elves"))
	var ms := Time.get_ticks_msec() - t0
	var t := Synth.theme(&"peace", &"elves")
	var expect := int(Synth.BARS * 4 * 60.0 / t.bpm * Synth.RATE) * 2
	_expect(a.size() == expect, "длина петли %d ≠ %d" % [a.size(), expect])
	_expect(_peak(a) < 32001 and _peak(a) > 3000, "громкость темы вне нормы (%d)" % _peak(a))
	_expect(Synth.render_theme(Synth.theme(&"peace", &"elves")) == a, "тема неповторяема")
	_expect(Synth.render_theme(Synth.theme(&"peace", &"orcs")) != a, "лейтмотивы рас не различаются")
	_expect(Synth.theme(&"dark", &"humans").scale == &"minor" and Synth.theme(&"peace", &"humans").scale == &"major", "мрачная тема не в миноре")
	for ctx in Synth.CONTEXTS:
		for race in Synth.RACE_MOTIFS:
			var th := Synth.theme(ctx, race)
			_expect(Synth.SCALES.has(th.scale), "нет лада %s" % th.scale)
	for race in RaceDB.all():
		_expect(Synth.RACE_MOTIFS.has(race.id), "у расы %s нет лейтмотива" % race.id)
	for id in Synth.SFX:
		var s := Synth.render_sfx(id)
		_expect(s.size() > 200 and _peak(s) > 1000, "звук %s пуст" % id)
	var stream := Synth.make_stream(a, true)
	_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and is_equal_approx(stream.get_length(), a.size() / 2.0 / Synth.RATE), "поток собран неверно")
	print("тема за %d мс, %.1f с звука" % [ms, a.size() / 2.0 / Synth.RATE])
	# Контекст музыки по миру.
	var s2 := MapSettings.new()
	s2.world_seed = 5
	s2.apply_size_preset(0)
	var world := World.create(s2)
	var am: Node = root.get_node_or_null("AudioManager")
	_expect(am != null and am.get("disabled") == true, "в headless звук не выключен")
	var pick: Callable = am.pick_context
	world.diplomacy.wars.clear()
	_expect(pick.call(world, false) == &"peace", "мирный мир — не мирная тема")
	_expect(pick.call(world, true) == &"heroic", "подвиг — не героическая тема")
	world.crisis = {"id": &"great_plague", "start": 0}
	_expect(pick.call(world, false) == &"crisis", "кризис — не тема кризиса")
	world.crisis = {}
	_expect(RaceDB.get_race(am.leading_race(world)) != null, "нет ведущей расы")
	# Вызовы в headless не падают.
	am.play_sfx(&"war")
	am.apply_volumes()
	# Настройки.
	am.set("music", 0.3)
	am.set("sfx_on", false)
	am.save_settings(CFG)
	am.set("music", 0.9)
	am.set("sfx_on", true)
	am.load_settings(CFG)
	_expect(is_equal_approx(am.get("music"), 0.3) and am.get("sfx_on") == false, "настройки звука не сохранились")
	DirAccess.remove_absolute(CFG)
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _peak(pcm: PackedByteArray) -> int:
	var p := 0
	for i in range(0, pcm.size(), 2):
		p = maxi(p, absi(pcm.decode_s16(i)))
	return p


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
