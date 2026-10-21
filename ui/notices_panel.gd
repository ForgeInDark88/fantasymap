class_name NoticesPanel
extends PanelContainer
## Уведомления (этап 11.F): записи летописи о державах и героях, за которыми
## вы следите (кнопка «Следить» в карточке государства и окне героя), и мировые
## потрясения — всплывают уведомлением и копятся здесь (последние 60).

const LIMIT := 60

var _text: RichTextLabel
var _items: Array[String] = []


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(420, 0)
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -440.0
	offset_right = -20.0
	offset_top = 90.0
	var box := VBoxContainer.new()
	add_child(box)
	var row := HBoxContainer.new()
	var title := Label.new()
	title.text = "Уведомления"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: UiAnim.hide(self))
	row.add_child(close)
	box.add_child(row)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.custom_minimum_size = Vector2(400, 320)
	_text.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(_text)
	UiAnim.attach(self, Vector2(0, -8))
	EventBus.notices_requested.connect(func() -> void:
		visible = not visible
		_redraw())
	EventBus.world_event.connect(_on_event)
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void:
		_items.clear()
		_redraw())


func _on_event(what: StringName, data: Dictionary) -> void:
	var world := WorldState.world
	if what != &"log" or world == null or not Notices.matters(world, data):
		return
	var line := "[color=#8a90a0]%d г.[/color] %s" % [world.year, data.text]
	_items.push_front(line)
	if _items.size() > LIMIT:
		_items.resize(LIMIT)
	EventBus.toast_requested.emit("🔔 " + String(data.text))
	if visible:
		_redraw()


func _redraw() -> void:
	var world := WorldState.world
	var head := ""
	if world != null:
		var names: Array[String] = []
		for id in world.watch_nations:
			if id < world.nations.size():
				names.append(world.nations[id].short_name)
		for id in world.watch_heroes:
			if id < world.heroes.size():
				names.append(world.heroes[id].name)
		head = "Следите за: %s\n\n" % (", ".join(names) if not names.is_empty() else "никем (кнопка «Следить» в карточке державы или окне героя)")
	_text.text = head + ("\n".join(_items) if not _items.is_empty() else "[color=#8a90a0]Пока тихо.[/color]")
