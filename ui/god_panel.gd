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
	[&"spy", "Тайная операция", "Сначала выберите государство-заказчика (обычным кликом), затем включите инструмент и кликните по жертве."],
	[&"society", "Тайное общество", "Клик по региону: в нём тайно собирается культ, братство или заговор."],
	[&"org", "Созвать организацию", "Клик по государству: оно созывает организацию выбранного вида (если найдутся участники)."],
	[&"eruption", "Извержение", "Клик у гор: ближайший вулкан извергается (или гора под курсором становится вулканом)."],
	[&"drought", "Засуха", "Клик: на климатический пояс клетки обрушивается великая сушь."],
	[&"invasion", "Нашествие из глубин", "Клик: из ближайшего логова чудовищ полчища вырываются на поверхность."],
	[&"ruin", "Древние руины", "Клик по суше: из-под земли открывается древнее святилище, полное сокровищ и опасностей."],
	[&"crisis", "Мировой кризис", "Клик по карте: на мир обрушивается выбранный кризис (идущий — заканчивается)."],
	[&"road", "Проложить дорогу", "Клик у города: от него пройдёт дорога (или морской путь) к ближайшему городу."],
	[&"artifact", "Даровать артефакт", "Клик у героя: он получает предмет выбранного вида (нет героя — реликвия в сокровищницу или клад в земле)."],
	[&"bless", "Милость бога", "Клик по государству: выбранный бог дарует ему свою милость на 10 лет."],
	[&"chosen", "Избранник бога", "Клик у героя: выбранный бог избирает его и одаривает."],
	[&"child", "Дитя героев", "Клик у героя: у него (и супруга или героя рядом) родится ребёнок — продолжатель рода."],
	[&"order", "Основать орден", "Клик у героя: он основывает орден или гильдию своего класса."],
	[&"army", "Создать армию", "Клик по государству: в этом регионе собирается войско (+3000 воинов)."],
	[&"fleet", "Спустить флот", "Клик по приморскому государству: в его гавани спускается флот."],
	[&"destroy_army", "Уничтожить армию", "Клик у армии: боги стирают её с лица земли."],
	[&"mutiny", "Бунт армии", "Клик у армии: войско восстаёт, и его край провозглашает свою державу."],
	[&"tribe", "Племя", "Клик по ничейной суше: здесь объявляется племя (вид — по местности)."],
	[&"lair", "Логово чудовищ", "Клик по суше: в этом крае заводится логово чудовищ."],
	[&"great_monster", "Великое чудовище", "Клик по суше: пробуждается великое чудовище — дракон, гидра или песчаный червь."],
	[&"disease", "Поветрие", "Клик по краю: в нём начинается выбранная болезнь и пойдёт по дорогам."],
	[&"dialect", "Новое наречие", "Клик по краю: его жители заговорят на своём наречии."],
	[&"caravan", "Караван", "Клик у города: от него выходит караван с самым выгодным товаром к соседу по дороге."],
	[&"mercs", "Наёмный отряд", "Клик у города: здесь собирается вольный отряд наёмников."],
	[&"gold_rush", "Золотая лихорадка", "Клик по государству: в казну хлынет золото — и цены поползут вверх."],
	[&"slavery", "Рабство: ввести или отменить", "Клик по государству: оно вводит рабство или отменяет его."],
	[&"forgive", "Простить долги", "Клик по государству: все его займы прощены (кредиторы теряют деньги)."],
	[&"persona", "Сменить нрав", "Клик по государству: у его правителей — другой характер."],
	[&"rumor", "Пустить слух", "Клик по государству: по миру ползёт ложный слух о слабости его войска."],
	[&"capital", "Перенести столицу", "Клик по городу: он становится столицей своего государства."],
	[&"deal", "Предложить сделку", "Сначала выберите государство (обычным кликом), затем кликните по партнёру: оно предложит сделку."],
	[&"collector", "Собиратель земель", "Клик по государству-наследнику империи: оно провозглашает себя собирателем её земель."],
	[&"raise", "Поднять землю", "Клик: земля поднимается (вода становится сушей, равнины — холмами и горами)."],
	[&"lower", "Опустить землю", "Клик: земля опускается (может уйти под воду вместе с городами)."],
]

var _buttons: Dictionary[StringName, Button] = {}
var _race: OptionButton
var _event: OptionButton
var _op: OptionButton
var _org: OptionButton
var _crisis: OptionButton
var _disease: OptionButton
var _artifact: OptionButton
var _god: OptionButton
var _radius: HSlider
var _hint: Label
var _tool: StringName = &""


func _init() -> void:
	custom_minimum_size = Vector2(320, 0)
	# Инструментов много — панель прокручивается.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(330, 700)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
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
		elif t[0] == &"spy":
			_op = OptionButton.new()
			for op in OrgDB.ops():
				_op.add_item(op.display_name)
			_op.item_selected.connect(func(_i: int) -> void: _emit())
			box.add_child(_op)
		elif t[0] == &"crisis":
			_crisis = OptionButton.new()
			for c in CrisisDB.all():
				_crisis.add_item(c.display_name)
			_crisis.item_selected.connect(func(_i: int) -> void: _emit())
			box.add_child(_crisis)
		elif t[0] == &"disease":
			_disease = OptionButton.new()
			for dd in DiseaseDB.all():
				_disease.add_item(dd.display_name)
			_disease.item_selected.connect(func(_i: int) -> void: _emit())
			box.add_child(_disease)
		elif t[0] == &"artifact":
			_artifact = OptionButton.new()
			for a in LoreDB.artifacts():
				_artifact.add_item(a.display_name)
			_artifact.item_selected.connect(func(_i: int) -> void: _emit())
			box.add_child(_artifact)
		elif t[0] == &"chosen":
			_god = OptionButton.new()
			for g in LoreDB.gods():
				_god.add_item("%s %s" % [g.symbol, g.display_name])
			_god.item_selected.connect(func(_i: int) -> void: _emit())
			box.add_child(_god)
		elif t[0] == &"org":
			_org = OptionButton.new()
			for o in OrgDB.orgs():
				_org.add_item(o.display_name)
			_org.item_selected.connect(func(_i: int) -> void: _emit())
			box.add_child(_org)
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
		"op": OrgDB.ops()[_op.selected],
		"org": OrgDB.orgs()[_org.selected],
		"crisis": CrisisDB.all()[_crisis.selected],
		"disease": DiseaseDB.all()[_disease.selected],
		"artifact": LoreDB.artifacts()[_artifact.selected],
		"god": LoreDB.gods()[_god.selected],
	}
	EventBus.god_tool_changed.emit(_tool, params)
