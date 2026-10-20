class_name AudioPanel
extends PanelContainer
## Настройки звука: общая громкость, музыка и эффекты (с отключением).
## Сохраняются в user://settings.cfg (AudioManager).


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Звук"
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	if AudioManager.disabled:
		var l := Label.new()
		l.text = "Звук недоступен (нет аудиоустройства)."
		box.add_child(l)
		return
	_slider(box, "Общая громкость", "master", "")
	_slider(box, "Музыка", "music", "music_on")
	_slider(box, "Эффекты", "sfx", "sfx_on")


func _slider(box: Control, label: String, key: String, toggle: String) -> void:
	var row := HBoxContainer.new()
	if toggle.is_empty():
		var l := Label.new()
		l.text = label
		l.custom_minimum_size = Vector2(120, 0)
		row.add_child(l)
	else:
		var c := CheckBox.new()
		c.text = label
		c.custom_minimum_size = Vector2(120, 0)
		c.focus_mode = Control.FOCUS_NONE
		c.button_pressed = AudioManager.get(toggle)
		c.toggled.connect(func(on: bool) -> void: AudioManager.set_enabled(toggle, on))
		row.add_child(c)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = AudioManager.get(key)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void: AudioManager.set_volume(key, v))
	row.add_child(s)
	box.add_child(row)
