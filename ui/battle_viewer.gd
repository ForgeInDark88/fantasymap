class_name BattleViewer
extends PanelContainer
## Просмотр боя, поединка или встречи (этап 12.E): клик по значку столкновения
## на карте. Реплики (data/battle_lines) появляются по одной, полосы показывают
## силы сторон; пересказ детерминирован (BattleReplay, зерно записи) и не
## трогает мир.

const STEP_SEC := 1.1

var _record: BattleRecord
var _steps: Array[Dictionary] = []
var _shown := 0
var _timer := 0.0
var _title: Label
var _text: RichTextLabel
var _bar_a: ColorRect
var _bar_b: ColorRect
var _name_a: Label
var _name_b: Label


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(380, 0)
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -190.0
	offset_right = 190.0
	offset_top = 110.0
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	for k in 2:
		var row := HBoxContainer.new()
		var name := Label.new()
		name.custom_minimum_size = Vector2(120, 0)
		name.clip_text = true
		row.add_child(name)
		var back := ColorRect.new()
		back.color = Color(0.15, 0.15, 0.18)
		back.custom_minimum_size = Vector2(230, 10)
		back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bar := ColorRect.new()
		bar.size = Vector2(230, 10)
		back.add_child(bar)
		row.add_child(back)
		box.add_child(row)
		if k == 0:
			_name_a = name
			_bar_a = bar
		else:
			_name_b = name
			_bar_b = bar
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(360, 0)
	_text.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(_text)
	var row := HBoxContainer.new()
	for spec in [["Сначала", _restart], ["Сразу всё", _skip], ["К месту", _focus], ["Закрыть", func() -> void: EventBus.battle_selected.emit(null)]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		row.add_child(b)
	box.add_child(row)
	UiAnim.attach(self, Vector2(0, -8))
	EventBus.battle_selected.connect(func(r: BattleRecord) -> void:
		if r == null:
			_record = null
			UiAnim.hide(self)
		else:
			show_record(r))
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void:
		_record = null
		visible = false)


func show_record(r: BattleRecord) -> void:
	_record = r
	_steps = BattleReplay.script(r, WorldState.world)
	visible = true
	_restart()


func _restart() -> void:
	_shown = 0
	_timer = STEP_SEC  # первая реплика — сразу
	_refresh()


func _skip() -> void:
	_shown = _steps.size()
	_refresh()


func _focus() -> void:
	if _record != null and _record.cell >= 0:
		EventBus.focus_cell.emit(_record.cell)


func _process(delta: float) -> void:
	if not visible or _record == null or _shown >= _steps.size():
		return
	_timer += delta
	if _timer >= STEP_SEC:
		_timer = 0.0
		_shown += 1
		_refresh()


func _refresh() -> void:
	if _record == null:
		return
	var world := WorldState.world
	_title.text = BattleReplay.title(_record, world)
	var cols := [Color(0.8, 0.8, 0.8), Color(0.6, 0.6, 0.6)]
	for k in 2:
		if k < _record.sides.size():
			var n := int(_record.sides[k].nation)
			if world != null and n >= 0 and n < world.nations.size():
				cols[k] = world.nations[n].color
	_name_a.text = str(_record.sides[0].name) if _record.sides.size() > 0 else ""
	_name_b.text = str(_record.sides[1].name) if _record.sides.size() > 1 else ""
	_bar_a.color = cols[0]
	_bar_b.color = cols[1]
	var step: Dictionary = _steps[_shown - 1] if _shown > 0 and _shown <= _steps.size() else {"a": 1.0, "b": 1.0}
	_bar_a.size.x = 230.0 * float(step.a)
	_bar_b.size.x = 230.0 * float(step.b)
	var lines: Array[String] = []
	for i in mini(_shown, _steps.size()):
		var t: String = _steps[i].text
		lines.append("[b]%s[/b]" % t if i == _shown - 1 else "[color=#b8b0a8]%s[/color]" % t)
	_text.text = "\n".join(lines)
