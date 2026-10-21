class_name ReferenceWindow
extends WindowBase
## Окно «Справочник» (этап 11.F): разделы, собранные из данных игры
## (Reference), и поиск по всем статьям.

var _list: ItemList
var _text: RichTextLabel
var _search: LineEdit
var _sections: Array = []


func _init() -> void:
	build("Справочник", Vector2(1180, 680))
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск по справочнику"
	_search.custom_minimum_size = Vector2(280, 0)
	_search.text_changed.connect(func(_t: String) -> void: _show(_list.get_selected_items()[0] if not _list.get_selected_items().is_empty() else 0))
	header.add_child(_search)
	add_close()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(260, 600)
	_list.item_selected.connect(_show)
	row.add_child(_list)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(880, 600)
	_text.add_theme_font_size_override("normal_font_size", 13)
	row.add_child(_text)
	EventBus.reference_window_requested.connect(open_window)


func open_window() -> void:
	visible = true
	if _sections.is_empty():
		_sections = Reference.sections()
		for s in _sections:
			_list.add_item("%s (%d)" % [s.title, (s.entries as Array).size()])
	_list.select(0)
	_show(0)


func _show(index: int) -> void:
	var q := _search.text.strip_edges().to_lower()
	var lines: Array[String] = []
	var pool: Array = _sections if not q.is_empty() else [_sections[clampi(index, 0, _sections.size() - 1)]]
	for s in pool:
		var hits: Array[String] = []
		for e in s.entries:
			if q.is_empty() or String(e.name).to_lower().contains(q) or String(e.text).to_lower().contains(q):
				hits.append("[b]%s[/b]%s" % [e.name, (" — " + String(e.text)) if not String(e.text).is_empty() else ""])
		if not hits.is_empty():
			lines.append("[font_size=17][b]%s[/b][/font_size]" % s.title)
			lines.append_array(hits)
			lines.append("")
	_text.text = "\n".join(lines) if not lines.is_empty() else "[color=#8a90a0]Ничего не найдено.[/color]"
