class_name ChroniclesWindow
extends Control
## Окно «Хроники»: связные истории летописца (Chronicler) — эпохи, войны,
## герои, державы и династии, веры, организации. Фильтры по виду, державе,
## эпохе, расе, вере, герою; поиск; ключевые события и закладки; экспорт
## выбранной истории в Markdown (user://chronicles/). Имена в тексте —
## ссылки: клик показывает державу или героя.

var _list: ItemList
var _text: RichTextLabel
var _status: Label
var _search: LineEdit
var _topic: OptionButton
var _nation: OptionButton
var _era: OptionButton
var _race: OptionButton
var _religion: OptionButton
var _hero: OptionButton
var _export: Button
var _stories: Array[Dictionary] = []
var _shown: Array[Dictionary] = []
## Что открыто справа: &"keys", &"bookmarks" или индекс истории в _shown.
var _view: Variant = &"keys"
var _events: Array[Dictionary] = []
## Значения фильтров-списков (параллельно пунктам OptionButton).
var _nation_ids: Array[int] = []
var _religion_ids: Array[int] = []
var _hero_ids: Array[int] = []
var _race_ids: Array[StringName] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1280, 720)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Хроники мира"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: visible = false)
	header.add_child(close)
	box.add_child(header)
	var filters := HBoxContainer.new()
	_topic = _option(filters, "Вид")
	_nation = _option(filters, "Держава")
	_era = _option(filters, "Эпоха")
	_race = _option(filters, "Раса")
	_religion = _option(filters, "Вера")
	_hero = _option(filters, "Герой")
	_search = LineEdit.new()
	_search.placeholder_text = "поиск по тексту"
	_search.custom_minimum_size = Vector2(200, 0)
	_search.text_submitted.connect(func(_t: String) -> void: _apply_filters())
	filters.add_child(_search)
	var find := Button.new()
	find.text = "Найти"
	find.focus_mode = Control.FOCUS_NONE
	find.pressed.connect(_apply_filters)
	filters.add_child(find)
	box.add_child(filters)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	box.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(420, 560)
	_list.add_theme_font_size_override("font_size", 12)
	_list.item_selected.connect(_on_item)
	body.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 14)
	_text.meta_clicked.connect(_on_meta)
	right.add_child(_text)
	var row := HBoxContainer.new()
	_export = Button.new()
	_export.text = "Экспорт в Markdown"
	_export.focus_mode = Control.FOCUS_NONE
	_export.pressed.connect(_export_story)
	row.add_child(_export)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	right.add_child(row)
	EventBus.chronicles_window_requested.connect(open_window)
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void: visible = false)


func _option(parent: Control, label: String) -> OptionButton:
	var o := OptionButton.new()
	o.tooltip_text = label
	o.custom_minimum_size = Vector2(150, 0)
	o.fit_to_longest_item = false
	o.item_selected.connect(func(_i: int) -> void: _apply_filters())
	parent.add_child(o)
	return o


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and key.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()


func open_window() -> void:
	var world := WorldState.world
	if world == null:
		return
	visible = true
	_stories = Chronicler.stories(world)
	_fill_filters(world)
	_view = &"keys"
	_apply_filters()


func _fill_filters(world: World) -> void:
	_topic.clear()
	_topic.add_item("Все истории")
	for t in Chronicler.TOPIC_NAMES:
		_topic.add_item(Chronicler.TOPIC_NAMES[t])
	_nation.clear()
	_nation_ids = [-1]
	_nation.add_item("Все державы")
	var nations := world.nations.duplicate()
	nations.sort_custom(func(a: Nation, b: Nation) -> bool: return a.name < b.name)
	for n in nations:
		if _stories.any(func(s: Dictionary) -> bool: return (s.nations as PackedInt32Array).has(n.id) and s.topic == &"nation"):
			_nation.add_item(n.name + ("" if n.alive else " †"))
			_nation_ids.append(n.id)
	_era.clear()
	_era.add_item("Все эпохи")
	for e in world.eras:
		_era.add_item(String(e.name))
	_race.clear()
	_race_ids = [&""]
	_race.add_item("Все расы")
	for r in RaceDB.all():
		_race.add_item(r.display_name)
		_race_ids.append(r.id)
	_religion.clear()
	_religion_ids = [-1]
	_religion.add_item("Все веры")
	for r in world.religions:
		_religion.add_item(r.name)
		_religion_ids.append(r.id)
	_hero.clear()
	_hero_ids = [-1]
	_hero.add_item("Все герои")
	for s in _stories:
		if s.topic == &"hero":
			_hero.add_item(world.heroes[int(s.ref)].display_name())
			_hero_ids.append(int(s.ref))


func _filter() -> Dictionary:
	var topics := Chronicler.TOPIC_NAMES.keys()
	return {"topic": topics[_topic.selected - 1] if _topic.selected > 0 else &"",
		"nation": _nation_ids[maxi(0, _nation.selected)], "era": _era.selected - 1,
		"race": _race_ids[maxi(0, _race.selected)], "religion": _religion_ids[maxi(0, _religion.selected)],
		"hero": _hero_ids[maxi(0, _hero.selected)], "text": _search.text}


func _apply_filters() -> void:
	var world := WorldState.world
	if world == null:
		return
	var f := _filter()
	_shown.clear()
	for s in _stories:
		if Chronicler.matches(world, s, f):
			_shown.append(s)
	_list.clear()
	_list.add_item("★ Ключевые события")
	_list.add_item("🔖 Закладки (%d)" % world.bookmarks.size())
	for s in _shown:
		_list.add_item("%s — %s (%d—%d)" % [Chronicler.TOPIC_SHORT.get(s.topic, ""), s.title, s.start, s.end])
		_list.set_item_tooltip(_list.item_count - 1, "значимость %.1f" % s.significance)
	_status.text = "Историй: %d из %d" % [_shown.size(), _stories.size()]
	_show()


func _on_item(index: int) -> void:
	_view = &"keys" if index == 0 else (&"bookmarks" if index == 1 else index - 2)
	_show()


func _show() -> void:
	var world := WorldState.world
	if world == null:
		return
	_export.disabled = not (_view is int)
	if _view is int:
		var s: Dictionary = _shown[int(_view)]
		var body := Chronicler.text(world, s)
		for e in Chronicler.entities(world, s):
			body = body.replace(e[2], "[url=%s:%d]%s[/url]" % [e[0], e[1], e[2]])
		_text.text = "[font_size=20][b]%s[/b][/font_size]\n[color=#8a90a0]%d—%d гг. · %s · значимость %.1f[/color]\n\n%s" % [
			s.title, s.start, s.end, Chronicler.TOPIC_NAMES.get(s.topic, ""), s.significance, body]
		return
	_events = Chronicler.key_events(world) if _view == &"keys" else world.bookmarks.duplicate()
	var f := _filter()
	var lines: Array[String] = ["[font_size=20][b]%s[/b][/font_size]\n" % ("Ключевые события" if _view == &"keys" else "Закладки")]
	var q := String(f.text).strip_edges().to_lower()
	for i in _events.size():
		var e: Dictionary = _events[i]
		if not q.is_empty() and not String(e.text).to_lower().contains(q):
			continue
		if int(f.nation) >= 0 and e.has("nations") and not (e.nations as PackedInt32Array).has(int(f.nation)):
			continue
		var mark := "★" if Chronicler.is_bookmarked(world, e) else "☆"
		lines.append("[url=bm:%d]%s[/url] [color=#8a90a0]%d г.[/color] %s" % [i, mark, int(e.year), e.text])
	if lines.size() == 1:
		lines.append("[color=#8a90a0]Пока пусто. Звёздочка у события — поставить закладку.[/color]")
	_text.text = "\n".join(lines)


func _on_meta(meta: Variant) -> void:
	var world := WorldState.world
	var parts := str(meta).split(":")
	if world == null or parts.size() < 2:
		return
	var id := int(parts[1])
	match parts[0]:
		"bm":
			Chronicler.toggle_bookmark(world, _events[id])
			_list.set_item_text(1, "🔖 Закладки (%d)" % world.bookmarks.size())
			_show()
		"nation":
			visible = false
			EventBus.nation_selected.emit(id)
			if world.nations[id].alive and world.nations[id].capital_city >= 0:
				EventBus.focus_cell.emit(world.cities[world.nations[id].capital_city].cell)
		"hero":
			visible = false
			EventBus.hero_window_requested.emit(id)


func _export_story() -> void:
	var world := WorldState.world
	if world == null or not (_view is int):
		return
	var path := Chronicler.export_markdown(world, _shown[int(_view)])
	_status.text = ("Сохранено: " + ProjectSettings.globalize_path(path)) if not path.is_empty() else "Не удалось записать файл"
