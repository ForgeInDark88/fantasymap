class_name ChroniclePanel
extends PanelContainer
## Летопись мира с фильтрами по категориям, по выбранному государству и поиском.
## Клик по записи выбирает государство и показывает его столицу.

const MAX_LINES := 300
## Категории фильтра: название → виды записей (World.log_event kind).
const CATEGORIES := {
	"Войны": [&"war", &"siege", &"conquest", &"peace"],
	"Дипломатия": [&"treaty", &"vassal"],
	"Государства": [&"nation", &"fall", &"collapse", &"rebellion", &"colony", &"settle"],
	"Правители": [&"ruler"],
	"Города": [&"city", &"building"],
	"Бедствия": [&"famine", &"plague", &"disaster", &"monsters"],
	"Герои": [&"hero"],
	"Великое": [&"great", &"fate"],
	"Вера": [&"religion"],
	"Знания": [&"tech", &"culture"],
	"Тайны": [&"intrigue"],
	"Союзы": [&"org", &"legacy"],
	"Торговля": [&"trade"],
	"Климат": [&"climate"],
	"Подземье": [&"underground"],
	"Руины": [&"ruins"],
	"Кризисы и эпохи": [&"crisis", &"era"],
	"Роды и ордена": [&"lineage", &"order"],
	"Битвы, флоты, пираты": [&"battle", &"pirates"],
	"Боги и реликвии": [&"gods", &"artifact"],
	"Дикие земли": [&"tribe", &"lair"],
	"Болезни": [&"disease"],
	"Языки": [&"language"],
	"Рынок и казна": [&"caravan", &"mercs", &"debt"],
	"Общество": [&"society"],
	"Сделки и слухи": [&"deal", &"capital", &"rumor"],
}
const COLORS := {
	&"nation": "#f0d98a", &"city": "#9fd3ff", &"building": "#b8c4d0", &"ruler": "#d6b3ff", &"famine": "#ff9a7a",
	&"war": "#ff6b5b", &"siege": "#ff9580", &"conquest": "#ff8a5c", &"peace": "#9be39b", &"treaty": "#8fd0c8",
	&"vassal": "#c0a0ff", &"rebellion": "#ffb04a", &"collapse": "#ff7070", &"fall": "#d06060", &"colony": "#7fc8ff", &"settle": "#d8c48a",
	&"plague": "#b8d070", &"disaster": "#e0a070", &"monsters": "#e08cc0", &"hero": "#ffe680",
	&"great": "#ffd24a", &"fate": "#e6b3ff", &"religion": "#f2e2a8", &"tech": "#a8e0ff", &"culture": "#ffc8e8",
	&"intrigue": "#c8a0e0", &"org": "#9fd8c0", &"legacy": "#e0c090", &"trade": "#f0c870", &"climate": "#b0d8e8", &"underground": "#c8b090", &"ruins": "#b8a8a0", &"crisis": "#ff8060", &"era": "#ffe9a8", &"lineage": "#f0d0b0", &"battle": "#ff9a6a", &"pirates": "#9ab8d8", &"order": "#a8c8f0", &"gods": "#fff0a0", &"artifact": "#e8c060",
	&"tribe": "#d8b080", &"lair": "#e07a6a", &"disease": "#a8c860", &"language": "#c0c8f0",
	&"caravan": "#e0b878", &"mercs": "#c8c0a8", &"debt": "#e8c070", &"society": "#d8a8c0",
	&"deal": "#a8d8b8", &"capital": "#f0d090", &"rumor": "#b0a8c8",
}

var _checks: Dictionary[String, CheckBox] = {}
var _only_selected: CheckBox
var _search: LineEdit
var _text: RichTextLabel
var _count: Label
var _selected_nation := -1
var _dirty := true
var _last_refresh_ms := 0


func _init() -> void:
	custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "Летопись мира"
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)

	var grid := HFlowContainer.new()
	for name in CATEGORIES:
		var cb := CheckBox.new()
		cb.text = name
		cb.button_pressed = name != "Города"  # стройки и новые деревни — самое «шумное», по умолчанию скрыты
		cb.toggled.connect(func(_on: bool) -> void: _mark_dirty())
		grid.add_child(cb)
		_checks[name] = cb
	box.add_child(grid)

	var row := HBoxContainer.new()
	_only_selected = CheckBox.new()
	_only_selected.text = "Только выбранное государство"
	_only_selected.toggled.connect(func(_on: bool) -> void: _mark_dirty())
	row.add_child(_only_selected)
	_search = LineEdit.new()
	_search.placeholder_text = "поиск…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _mark_dirty())
	row.add_child(_search)
	box.add_child(row)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.custom_minimum_size = Vector2(500, 430)
	_text.scroll_following = false
	_text.meta_underlined = false
	_text.add_theme_font_size_override("normal_font_size", 12)
	_text.meta_clicked.connect(_on_meta)
	box.add_child(_text)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 11)
	_count.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	box.add_child(_count)

	EventBus.nation_selected.connect(func(id: int) -> void:
		_selected_nation = id
		if _only_selected.button_pressed:
			_mark_dirty())
	EventBus.year_passed.connect(func(_y: int) -> void: _dirty = true)
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void: _mark_dirty())
	visibility_changed.connect(_mark_dirty)


func _process(_delta: float) -> void:
	# Пока идёт симуляция — обновляемся не чаще раза в секунду.
	if visible and _dirty and Time.get_ticks_msec() - _last_refresh_ms > 1000:
		_refresh()


func _mark_dirty() -> void:
	_dirty = true
	_last_refresh_ms = 0


func _refresh() -> void:
	_dirty = false
	_last_refresh_ms = Time.get_ticks_msec()
	var world := WorldState.world
	if world == null:
		_text.text = ""
		return
	var kinds := {}
	for name in _checks:
		if _checks[name].button_pressed:
			for k in CATEGORIES[name]:
				kinds[k] = true
	var query := _search.text.strip_edges().to_lower()
	var only := _selected_nation if _only_selected.button_pressed else -1
	var lines: Array[String] = []
	var matched := 0
	for i in range(world.chronicle.size() - 1, -1, -1):
		var e: Dictionary = world.chronicle[i]
		if not kinds.has(e.kind):
			continue
		if only >= 0 and not (e.nations as PackedInt32Array).has(only):
			continue
		if not query.is_empty() and not (e.text as String).to_lower().contains(query):
			continue
		matched += 1
		if lines.size() < MAX_LINES:
			var color: String = COLORS.get(e.kind, "#dddddd")
			var link: int = e.nations[0] if not (e.nations as PackedInt32Array).is_empty() else -1
			var month: String = World.MONTH_NAMES[e.get("month", 0)]
			lines.append("[color=#8a90a0]%d г., %s[/color]  [url=%d][color=%s]%s[/color][/url]" % [e.year, month.to_lower(), link, color, e.text])
	_text.text = "\n".join(lines)
	_count.text = "Записей: %d%s · всего в истории %d" % [matched, " (показаны последние %d)" % MAX_LINES if matched > MAX_LINES else "", world.chronicle_total]


func _on_meta(meta: Variant) -> void:
	var id := int(str(meta))
	var world := WorldState.world
	if world == null or id < 0 or id >= world.nations.size():
		return
	EventBus.nation_selected.emit(id)
	var nation := world.nations[id]
	if nation.capital_city >= 0:
		EventBus.focus_cell.emit(world.cities[nation.capital_city].cell)
	elif nation.label_cell >= 0:
		EventBus.focus_cell.emit(nation.label_cell)
