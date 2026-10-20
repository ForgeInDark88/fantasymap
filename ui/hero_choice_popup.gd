class_name HeroChoicePopup
extends Control
## Всплывающее окно выбора героя игрока (событие пути, встреча, Чертоги
## Судьбы). Пока выбор не сделан, мир стоит (WorldState не шагает).

var _panel: PanelContainer
var _title: Label
var _text: RichTextLabel
var _options: VBoxContainer
var _result: Label
var _shown := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560, 0)
	_panel.visible = false
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(540, 0)
	box.add_child(_text)
	_options = VBoxContainer.new()
	box.add_child(_options)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(540, 0)
	_result.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	box.add_child(_result)


func _process(_delta: float) -> void:
	var world := WorldState.world
	var choice: Dictionary = world.player_choice if world != null else {}
	if choice.is_empty():
		_panel.visible = false
		_shown = ""
		return
	var key := "%s|%s" % [choice.title, choice.text]
	if key == _shown:
		return
	_shown = key
	_panel.visible = true
	_title.text = choice.title
	_text.text = choice.text
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()
	var opts: Array = choice.options
	for i in opts.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, opts[i].text]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		var index := i
		var act := String(opts[i].act)
		b.pressed.connect(func() -> void:
			_result.text = PlayerSystem.choose(WorldState.world, index)
			if act == "pick":
				EventBus.my_hero_requested.emit(false))
		_options.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _panel.visible and key != null and key.pressed and key.keycode >= KEY_1 and key.keycode <= KEY_4:
		var i := key.keycode - KEY_1
		if i < _options.get_child_count():
			(_options.get_child(i) as Button).pressed.emit()
			get_viewport().set_input_as_handled()
