class_name GodPanel
extends PanelContainer
## Панель Бога: выбор инструмента вмешательства. Сам клик по карте
## обрабатывает main.gd через GodTools; ПКМ или Esc — снять инструмент.

const TOOLS := [
	[&"create_nation", "Создать государство", "Клик по суше: в этом регионе возникнет государство выбранной расы (чужой регион отделится)."],
	[&"event", "Вызвать событие", "Клик по государству: с ним случится выбранное событие."],
	[&"war", "Объявить войну", "Сначала выберите государство-агрессора (обычным кликом), затем включите инструмент и кликните по жертве."],
	[&"rebellion", "Поднять мятеж", "Клик по региону: его народ восстаёт и провозглашает своё государство."],
	[&"hero", "Призвать героя", "Клик по государству: в этом регионе появится герой."],
	[&"source", "Источник силы", "Клик по суше: здесь забьёт источник силы (не больше двух в мире)."],
	[&"portal", "Открыть Врата бездны", "Клик по суше: из портала хлынут демоны, воюющие со всеми."],
	[&"religion", "Основать религию", "Клик по государству: пророк приносит новую веру, она становится государственной."],
	[&"heresy", "Вызвать ересь", "Клик по государству: в его дальних регионах рождается ересь (возможен раскол)."],
	[&"insight", "Озарение", "Клик по государству: его учёные мгновенно завершают текущее исследование."],
	[&"assimilate", "Слияние культур", "Клик по региону: его жители перенимают культуру владельца."],
	[&"raise", "Поднять землю", "Клик: земля поднимается (вода становится сушей, равнины — холмами и горами)."],
	[&"lower", "Опустить землю", "Клик: земля опускается (может уйти под воду вместе с городами)."],
]

var _buttons: Dictionary[StringName, Button] = {}
var _race: OptionButton
var _event: OptionButton
var _radius: HSlider
var _hint: Label
var _tool: StringName = &""


func _init() -> void:
	custom_minimum_size = Vector2(320, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "Панель Бога"
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for t in TOOLS:
		var b := Button.new()
		b.text = t[1]
		b.tooltip_text = t[2]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.toggled.connect(func(on: bool) -> void: _select(t[0] if on else &""))
		box.add_child(b)
		_buttons[t[0]] = b
		if t[0] == &"create_nation":
			_race = OptionButton.new()
			_race.add_theme_constant_override("icon_max_width", 18)
			for race in RaceDB.all():
				_race.add_icon_item(race.icon, race.display_name)
			_race.item_selected.connect(func(_i: int) -> void: _emit())
			box.add_child(_race)
		elif t[0] == &"event":
			_event = OptionButton.new()
			for e in EconomyDB.events():
				_event.add_item(e.display_name)
			_event.item_selected.connect(func(_i: int) -> void: _emit())
			box.add_child(_event)
		elif t[0] == &"lower":
			var row := HBoxContainer.new()
			var l := Label.new()
			l.text = "Кисть"
			row.add_child(l)
			_radius = HSlider.new()
			_radius.min_value = 1
			_radius.max_value = 8
			_radius.value = 3
			_radius.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_radius.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_radius.value_changed.connect(func(_v: float) -> void: _emit())
			row.add_child(_radius)
			box.add_child(row)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_hint.custom_minimum_size = Vector2(300, 0)
	box.add_child(_hint)
	_hint.text = "Выберите инструмент. ПКМ или Esc — отмена."
	# Сброс инструмента извне (ПКМ по карте) — отжимаем кнопку.
	EventBus.god_tool_changed.connect(func(tool: StringName, _p: Dictionary) -> void:
		if tool == &"" and _tool != &"":
			_tool = &""
			for b in _buttons.values():
				b.set_pressed_no_signal(false)
			_hint.text = "Выберите инструмент. ПКМ или Esc — отмена.")
	visibility_changed.connect(func() -> void:
		if not visible and _tool != &"":
			EventBus.god_tool_changed.emit(&"", {}))


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE and _tool != &"":
		EventBus.god_tool_changed.emit(&"", {})
		get_viewport().set_input_as_handled()


func _select(tool: StringName) -> void:
	_tool = tool
	for t in TOOLS:
		if t[0] == tool:
			_hint.text = t[2]
	_emit()


func _emit() -> void:
	if _tool == &"":
		EventBus.god_tool_changed.emit(&"", {})
		return
	var params := {
		"race": RaceDB.all()[_race.selected],
		"event": EconomyDB.events()[_event.selected],
		"radius": int(_radius.value),
	}
	EventBus.god_tool_changed.emit(_tool, params)
