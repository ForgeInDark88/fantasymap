class_name AchievementsWindow
extends Control
## Окно «Достижения» (прогресс по каждому; скрытые — «???» до получения) и
## всплывающие уведомления о новых достижениях в правом верхнем углу.

const TOAST_SECONDS := 5.0

var _window: Control
var _list: VBoxContainer
var _summary: Label
var _toasts: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window = Control.new()
	_window.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.visible = false
	add_child(_window)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_window.visible = false)
	_window.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 640)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Достижения"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_summary = Label.new()
	header.add_child(_summary)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: _window.visible = false)
	header.add_child(close)
	box.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toasts.position = Vector2(-360, 90)
	_toasts.custom_minimum_size = Vector2(340, 0)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	EventBus.achievements_window_requested.connect(open_window)
	EventBus.achievement_unlocked.connect(_toast)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _window.visible and key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_window.visible = false
		get_viewport().set_input_as_handled()


func open_window() -> void:
	_window.visible = true
	refresh()


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var tr: AchievementTracker = Achievements.tracker
	var done := 0
	for d in tr.defs:
		var got := tr.is_unlocked(d.id)
		if got:
			done += 1
		var row := VBoxContainer.new()
		var name := Label.new()
		name.text = ("✔ " if got else "○ ") + (d.title if got or not d.hidden else "???")
		name.add_theme_font_size_override("font_size", 15)
		name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if got else Color(0.8, 0.82, 0.88))
		row.add_child(name)
		var desc := Label.new()
		desc.text = d.description if got or not d.hidden else "Скрытое достижение: откроется, когда случится."
		if got:
			desc.text += "  (получено в %d г. мира, %s)" % [int(tr.unlocked[String(d.id)].year), str(tr.unlocked[String(d.id)].date).left(10)]
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
		row.add_child(desc)
		if not got and not d.hidden:
			var bar := ProgressBar.new()
			bar.max_value = 1.0
			bar.value = tr.get_progress(d)
			bar.custom_minimum_size = Vector2(700, 10)
			bar.show_percentage = false
			row.add_child(bar)
		_list.add_child(row)
	_summary.text = "%d из %d   " % [done, tr.defs.size()]


func _toast(d: AchievementDef) -> void:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var t := Label.new()
	t.text = "🏆 Достижение: " + d.title
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(t)
	var desc := Label.new()
	desc.text = d.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(320, 0)
	desc.add_theme_font_size_override("font_size", 12)
	box.add_child(desc)
	_toasts.add_child(panel)
	get_tree().create_timer(TOAST_SECONDS).timeout.connect(panel.queue_free)
	if _window.visible:
		refresh()
