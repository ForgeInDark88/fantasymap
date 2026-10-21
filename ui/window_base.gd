class_name WindowBase
extends Control
## Основа полноэкранных окон (этап 11.F): затемнение, панель по центру,
## заголовок и «Закрыть», Esc закрывает, плавное появление (UiAnim).

var content: VBoxContainer
var header: HBoxContainer


func build(title_text: String, size: Vector2) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	UiAnim.attach(self, Vector2.ZERO)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	center.add_child(panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	header = HBoxContainer.new()
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	content.add_child(header)
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void: visible = false)


## Кнопка «Закрыть» — последней в заголовке (после своих кнопок окна).
func add_close() -> void:
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: UiAnim.hide(self))
	header.add_child(close)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and key.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
