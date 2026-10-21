extends SceneTree
## Headless-проверка этапа 11.F (удобство):
##   • локализация: перевод на английский без пустых строк и повторов; все
##     обязательные надписи (режимы карты, инструменты Бога, команды героя)
##     переведены; «битых» ключей нет — каждая строка таблицы встречается в коде;
##   • справочник: все разделы не пусты, docs/REFERENCE.md не устарел;
##   • снимки истории: восстановленная ветвь без вмешательства повторяет историю;
##   • экспорт карты: PNG (обычный и пергамент) и SVG-легенда;
##   • уведомления: важные записи о державах, за которыми следят.
##   godot --headless --path . -s res://tests/usability_test.gd

var _failures := 0


func _initialize() -> void:
	_localization()
	_reference()
	_snapshots_and_export()
	if _failures > 0:
		printerr("FAILED: %d проверок не прошли" % _failures)
		quit(1)
	else:
		print("OK: все проверки пройдены")
		quit(0)


func _localization() -> void:
	var f := FileAccess.open("res://data/locale/en.txt", FileAccess.READ)
	_expect(f != null, "нет перевода на английский")
	if f == null:
		return
	var seen := {}
	var n := 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split("\t")
		_expect(parts.size() == 2 and not parts[0].strip_edges().is_empty() and not parts[1].strip_edges().is_empty(), "битая строка перевода: «%s»" % line)
		if parts.size() == 2:
			_expect(not seen.has(parts[0]), "повтор ключа «%s»" % parts[0])
			seen[parts[0]] = parts[1]
		n += 1
	var en := Loc.table("en")
	_expect(en.size() == seen.size() and en.size() > 100, "таблица перевода не читается")
	var must: Array[String] = []
	must.append_array(MapMode.NAMES)
	for t in GodToolList.TOOLS:
		must.append(t[1])
	for c in PlayerSystem.COMMANDS:
		must.append(c[1])
	for s in must:
		_expect(en.has(s), "нет перевода: «%s»" % s)
	# Битые ключи: строка таблицы, которой нет ни в одном скрипте (опечатка или удалённая надпись).
	var code := ""
	for dir in ["res://ui/", "res://scripts/sim/", "res://scripts/render/", "res://scripts/core/", "res://scripts/autoload/", "res://scripts/sim/systems/"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd"):
				code += FileAccess.get_file_as_string(dir + file)
	code += FileAccess.get_file_as_string("res://ui/hud.tscn") + FileAccess.get_file_as_string("res://ui/nation_panel.tscn")
	for k in en:
		_expect(code.contains("\"%s\"" % k) or code.contains("\"%s " % k) or code.contains("text = \"%s\"" % k), "битый ключ перевода (нет в коде): «%s»" % k)
	Loc.init()
	Loc.set_locale("en", false)
	_expect(TranslationServer.translate("Политика") == "Politics" and Loc.t("Политика") == "Politics", "английский не включается")
	Loc.set_locale("ru", false)
	# Надписи Godot переводит сам (auto_translate) — по-русски без перевода
	# не должно подставляться запасное английское.
	_expect(Loc.t("Политика") == "Политика" and TranslationServer.translate("Политика") == "Политика", "русский не возвращается")
	print("перевод: %d строк" % n)


func _reference() -> void:
	var sections := Reference.sections()
	_expect(sections.size() >= 20, "мало разделов справочника")
	for s in sections:
		_expect(not (s.entries as Array).is_empty(), "пустой раздел справочника «%s»" % s.title)
	var doc := FileAccess.get_file_as_string(Reference.DOC)
	_expect(doc == Reference.to_markdown(), "docs/REFERENCE.md устарел — пересоберите: tests/gen_reference.gd")


func _snapshots_and_export() -> void:
	var s := MapSettings.new()
	s.world_seed = 31
	s.apply_size_preset(0)
	var world := World.create(s)
	var sim := Simulation.new()
	for y in 30:
		sim.step(world)
	var snaps := Snapshots.new()
	snaps.take(world)
	snaps.maybe_auto(world)
	for y in 20:
		sim.step(world)
	var branch := snaps.restore(0)
	_expect(branch != null and branch.branch == 1 and int(branch.branch_from.year) == 30, "ветвь не создана")
	var sim2 := Simulation.new()
	for y in 20:
		sim2.step(branch)
	_expect(branch.owner == world.owner and branch.year == world.year, "ветвь без вмешательства разошлась с историей")
	var pop_a := 0.0
	var pop_b := 0.0
	for n in world.nations:
		pop_a += n.population
	for n in branch.nations:
		pop_b += n.population
	_expect(is_equal_approx(pop_a, pop_b), "население ветви разошлось")
	# Экспорт карты.
	var img := MapExport.image(world, false, 2)
	_expect(img.get_width() == world.map.width * 2 and img.get_height() == world.map.height * 2, "размер PNG неверен")
	var p1 := MapExport.save_png(world, false, "user://test_map.png")
	var p2 := MapExport.save_png(world, true, "user://test_map_parchment.png")
	_expect(FileAccess.file_exists(p1) and FileAccess.file_exists(p2), "PNG не сохранён")
	var svg := MapExport.legend_svg(world)
	var biggest: Nation = null
	for n in world.nations:
		if n.alive and (biggest == null or n.cell_count > biggest.cell_count):
			biggest = n
	_expect(svg.begins_with("<svg") and svg.contains(MapExport._xml(biggest.name)), "SVG-легенда без держав")
	_expect(not MapExport.save_svg(world, "user://test_legend.svg").is_empty(), "SVG не сохранён")
	# Уведомления.
	Notices.toggle_nation(world, biggest.id)
	_expect(Notices.matters(world, {"kind": &"war", "text": "x", "nations": PackedInt32Array([biggest.id])}), "нет уведомления о державе под наблюдением")
	_expect(not Notices.matters(world, {"kind": &"city", "text": "x", "nations": PackedInt32Array([-5])}), "лишнее уведомление")
	_expect(Notices.matters(world, {"kind": &"crisis", "text": "x", "nations": PackedInt32Array()}), "мировой кризис без уведомления")
	print("снимки и экспорт: ветвь %d с %d г., PNG %dx%d" % [branch.branch, int(branch.branch_from.year), img.get_width(), img.get_height()])


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", msg)
