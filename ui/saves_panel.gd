class_name SavesPanel
extends PanelContainer
## Сохранения: запись текущего мира под именем, список сохранений,
## загрузка и удаление. F5 — быстрое сохранение, F9 — быстрая загрузка.

const QUICK_SAVE := "быстрое"

var _name_edit: LineEdit
var _list: ItemList
var _status: Label
var _load_button: Button
var _delete_button: Button
## Последнее подставленное имя по умолчанию: пока игрок его не правил, оно обновляется.
var _auto_name := ""


func _init() -> void:
	custom_minimum_size = Vector2(380, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "Сохранения"
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)

	var row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Название сохранения"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t: String) -> void: _save())
	row.add_child(_name_edit)
	var save := Button.new()
	save.text = "Сохранить"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save)
	row.add_child(save)
	box.add_child(row)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 260)
	_list.item_selected.connect(func(i: int) -> void:
		_name_edit.text = _list.get_item_metadata(i)
		_update_buttons())
	_list.item_activated.connect(func(_i: int) -> void: _load())
	box.add_child(_list)

	var actions := HBoxContainer.new()
	_load_button = Button.new()
	_load_button.text = "Загрузить"
	_load_button.focus_mode = Control.FOCUS_NONE
	_load_button.pressed.connect(_load)
	actions.add_child(_load_button)
	_delete_button = Button.new()
	_delete_button.text = "Удалить"
	_delete_button.focus_mode = Control.FOCUS_NONE
	_delete_button.pressed.connect(_delete)
	actions.add_child(_delete_button)
	box.add_child(actions)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.text = "F5 — быстрое сохранение, F9 — быстрая загрузка."
	box.add_child(_status)

	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void: _refresh())


func _refresh() -> void:
	_list.clear()
	var entries: Array = []
	for save_name in SaveSystem.list_saves():
		var path := SaveSystem.save_path(save_name)
		entries.append([FileAccess.get_modified_time(path), save_name, FileAccess.open(path, FileAccess.READ).get_length()])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for e in entries:
		var when := Time.get_datetime_string_from_unix_time(e[0] + _tz_offset(), true)
		var i := _list.add_item("%s   ·  %s  ·  %.1f МБ" % [e[1], when, e[2] / 1048576.0])
		_list.set_item_metadata(i, e[1])
	if WorldState.world != null and (_name_edit.text.is_empty() or _name_edit.text == _auto_name):
		_auto_name = _default_name()
		_name_edit.text = _auto_name
	_update_buttons()


func _update_buttons() -> void:
	var has := not _list.get_selected_items().is_empty()
	_load_button.disabled = not has
	_delete_button.disabled = not has


func _default_name() -> String:
	var w := WorldState.world
	return "Мир %d, %d год" % [w.settings.world_seed, w.year]


func _save() -> void:
	var save_name := _name_edit.text.strip_edges()
	if save_name.is_empty():
		save_name = _default_name()
	save_game(save_name)
	_refresh()


func _load() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	load_game(_list.get_item_metadata(sel[0]))


func _delete() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var save_name: String = _list.get_item_metadata(sel[0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.save_path(save_name)))
	_status.text = "Удалено: " + save_name
	_name_edit.text = ""
	_refresh()


func save_game(save_name: String) -> void:
	var err := WorldState.save_game(save_name)
	_status.text = ("Сохранено: %s (%s)" % [save_name, WorldState.world.date_text()]) if err == OK \
			else "Не удалось сохранить: %s" % error_string(err)


func load_game(save_name: String) -> void:
	if WorldState.load_game(save_name):
		_status.text = "Загрузка: %s…" % save_name
	else:
		_status.text = "Нет сохранения «%s»" % save_name


static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
