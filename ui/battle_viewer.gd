class_name BattleViewer
extends PanelContainer
## Просмотр боя, поединка или встречи (этап 12.E): клик по значку столкновения на
## карте открывает окно с полем боя — отдельной картой местности, где бой
## разыгрывается заново (BattleField), полосами сил сторон и репликами
## (data/battle_lines). Пока окно открыто, мир на паузе; при закрытии — прежняя
## скорость. Пересказ детерминирован (BattleReplay, зерно записи), мир не меняется.

## Секунд на шаг пересказа.
const STEP_SEC := 1.6
const BAR_W := 260.0

var _record: BattleRecord
var _steps: Array[Dictionary] = []
var _progress := 0.0
var _playing := true
var _resume_speed := -1
var _title: Label
var _field: BattleField
var _text: RichTextLabel
var _bar_a: ColorRect
var _bar_b: ColorRect
var _name_a: Label
var _name_b: Label
var _play: Button


func _init() -> void:
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -380.0
	offset_right = 380.0
	offset_top = -290.0
	offset_bottom = 290.0
	var box := VBoxContainer.new()
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_field = BattleField.new()
	_field.custom_minimum_size = Vector2(740, 400)
	box.add_child(_field)
	var bars := HBoxContainer.new()
	for k in 2:
		var name := Label.new()
		name.custom_minimum_size = Vector2(100, 0)
		name.clip_text = true
		bars.add_child(name)
		var back := ColorRect.new()
		back.color = Color(0.15, 0.15, 0.18)
		back.custom_minimum_size = Vector2(BAR_W, 10)
		back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bar := ColorRect.new()
		bar.size = Vector2(BAR_W, 10)
		back.add_child(bar)
		bars.add_child(back)
		if k == 0:
			_name_a = name
			_bar_a = bar
		else:
			_name_b = name
			_bar_b = bar
	box.add_child(bars)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(740, 54)
	_text.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_text)
	var row := HBoxContainer.new()
	_play = Button.new()
	_play.focus_mode = Control.FOCUS_NONE
	_play.pressed.connect(func() -> void:
		_playing = not _playing
		_refresh())
	row.add_child(_play)
	for spec in [["◀", func() -> void: _browse(-1)], ["▶", func() -> void: _browse(1)], ["Сначала", _restart], ["В конец", _skip],
			["К месту", _focus], ["Закрыть", func() -> void: EventBus.battle_selected.emit(null)]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		row.add_child(b)
	box.add_child(row)
	UiAnim.attach(self, Vector2(0, -8))
	EventBus.battle_selected.connect(func(r: BattleRecord) -> void:
		if r == null:
			_close()
		else:
			show_record(r))
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void:
		_record = null
		_resume_speed = -1
		visible = false)


func show_record(r: BattleRecord) -> void:
	_record = r
	_steps = BattleReplay.script(r, WorldState.world)
	_field.setup(r, _steps, WorldState.world)
	# Смотрим бой — мир стоит (скорость вернётся при закрытии).
	if _resume_speed < 0 and WorldState.speed_index > 0:
		_resume_speed = WorldState.speed_index
		WorldState.set_speed(0)
	visible = true
	_restart()


## Соседняя запись журнала (World.battle_log): листать все бои, поединки и встречи.
func _browse(step: int) -> void:
	var world := WorldState.world
	if world == null or _record == null or world.battle_log.is_empty():
		return
	var i := world.battle_log.find(_record)
	i = clampi((i if i >= 0 else world.battle_log.size()) + step, 0, world.battle_log.size() - 1)
	show_record(world.battle_log[i])


func _close() -> void:
	_record = null
	UiAnim.hide(self)
	if _resume_speed > 0:
		WorldState.set_speed(_resume_speed)
	_resume_speed = -1


func _restart() -> void:
	_progress = 0.0
	_playing = true
	_refresh()


func _skip() -> void:
	_progress = float(_steps.size()) + 1.0
	_refresh()


func _focus() -> void:
	if _record != null and _record.cell >= 0:
		EventBus.focus_cell.emit(_record.cell)


func _process(delta: float) -> void:
	if not visible or _record == null:
		return
	if _playing and _progress < _steps.size() + 1.0:
		var shown := int(_progress)
		_progress += delta / STEP_SEC
		if int(_progress) != shown:
			_refresh()
	_field.progress = _progress
	_field.queue_redraw()
	_update_bars()


func _update_bars() -> void:
	if _steps.is_empty():
		return
	var i := clampi(int(_progress), 0, _steps.size() - 1)
	_bar_a.size.x = BAR_W * float(_steps[i].a)
	_bar_b.size.x = BAR_W * float(_steps[i].b)


func _refresh() -> void:
	if _record == null:
		return
	var world := WorldState.world
	_title.text = BattleReplay.title(_record, world)
	_play.text = "Пауза" if _playing and _progress < _steps.size() + 1.0 else "Смотреть"
	_name_a.text = str(_record.sides[0].name) if _record.sides.size() > 0 else ""
	_name_b.text = str(_record.sides[1].name) if _record.sides.size() > 1 else ""
	_bar_a.color = _field._cols[0]
	_bar_b.color = _field._cols[1]
	_update_bars()
	# Последние три реплики: текущая — ярко.
	var shown := mini(int(_progress) + 1, _steps.size())
	var lines: Array[String] = []
	for i in range(maxi(0, shown - 3), shown):
		var t: String = _steps[i].text
		lines.append("[b]%s[/b]" % t if i == shown - 1 else "[color=#a8a098]%s[/color]" % t)
	_text.text = "\n".join(lines)
