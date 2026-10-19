class_name HeroWindow
extends Control
## Окно героя: подробности о выбранном герое поверх карты.
## Слева — облик (уровень, возраст, сила, ум, натура, служба, цель, мысли),
## в середине — связи с другими героями, справа — деяния и упоминания в
## летописи. Имена героев и государств кликабельны. «Следить» — камера
## держится за героем, пока окно закрыто (Esc или клик по карте — перестать).

const REFRESH_MS := 1000
const MENTIONS := 40

var _hero_id := -1
var _follow_id := -1
var _follow_cell := -1
var _last_refresh_ms := 0

var _icon: TextureRect
var _title: Label
var _subtitle: Label
var _follow_button: Button
var _stats: GridContainer
var _thought: RichTextLabel
var _relations: RichTextLabel
var _deeds: RichTextLabel
var _mentions: RichTextLabel


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close_window())
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1180, 660)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	# Шапка: значок расы, имя, подзаголовок и кнопки.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(40, 40)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(_icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	names.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_color_override("font_color", Color(0.75, 0.77, 0.85))
	names.add_child(_subtitle)
	header.add_child(names)
	for d in [["◀", "Предыдущий герой", _step.bind(-1)], ["▶", "Следующий герой", _step.bind(1)],
			["Показать на карте", "Закрыть окно и навести камеру на героя", _show_on_map]]:
		var b := Button.new()
		b.text = d[0]
		b.tooltip_text = d[1]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(d[2])
		header.add_child(b)
	_follow_button = Button.new()
	_follow_button.text = "Следить"
	_follow_button.tooltip_text = "Камера будет следовать за героем (Esc — перестать)"
	_follow_button.focus_mode = Control.FOCUS_NONE
	_follow_button.pressed.connect(_follow)
	header.add_child(_follow_button)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_window)
	header.add_child(close)
	box.add_child(header)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	box.add_child(body)

	# Облик.
	var left := _column(body, "Облик", 340)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 10)
	_stats.add_theme_constant_override("v_separation", 6)
	left.add_child(_stats)
	var tl := Label.new()
	tl.text = "Мысли"
	tl.add_theme_font_size_override("font_size", 15)
	left.add_child(tl)
	_thought = _rich(left)
	_thought.fit_content = true

	_relations = _rich(_column(body, "Связи", 330))
	var right := _column(body, "Путь героя", 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deeds = _rich(right)
	var ml := Label.new()
	ml.text = "В летописи мира"
	ml.add_theme_font_size_override("font_size", 15)
	right.add_child(ml)
	_mentions = _rich(right)

	EventBus.hero_window_requested.connect(open_window)
	EventBus.world_generated.connect(func(_w: World, _ms: int) -> void:
		_follow_id = -1
		close_window())
	EventBus.nation_selected.connect(func(id: int) -> void:
		if id < 0:
			_follow_id = -1)
	EventBus.cell_clicked.connect(func(_c: int) -> void: _follow_id = -1)


func _column(parent: Control, title: String, width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0)
	col.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	col.add_child(l)
	parent.add_child(col)
	return col


func _rich(parent: Control) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 13)
	r.meta_clicked.connect(_on_meta)
	parent.add_child(r)
	return r


func open_window(hero_id: int) -> void:
	var world := WorldState.world
	if world == null or hero_id < 0 or hero_id >= world.heroes.size():
		return
	_hero_id = hero_id
	visible = true
	EventBus.hero_selected.emit(hero_id)
	refresh()


func close_window() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.keycode != KEY_ESCAPE:
		return
	if visible:
		close_window()
		get_viewport().set_input_as_handled()
	else:
		_follow_id = -1


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_refresh_ms < REFRESH_MS:
		return
	_last_refresh_ms = now
	if visible:
		refresh()
	elif _follow_id >= 0:
		var world := WorldState.world
		if world == null or _follow_id >= world.heroes.size():
			_follow_id = -1
			return
		var h := world.heroes[_follow_id]
		if not h.alive or h.is_ruler:
			_follow_id = -1
		elif h.cell != _follow_cell:
			_follow_cell = h.cell
			EventBus.focus_cell.emit(h.cell)


func refresh() -> void:
	var world := WorldState.world
	if world == null or _hero_id < 0 or _hero_id >= world.heroes.size():
		return
	var h := world.heroes[_hero_id]
	_icon.texture = h.race.icon
	_title.text = h.display_name()
	_title.add_theme_color_override("font_color", h.hero_class.color.lightened(0.15) if h.alive else Color(0.6, 0.6, 0.65))
	_subtitle.text = "%s, %s · %s · %s" % [h.race.display_name, h.hero_class.display_name.to_lower(),
		h.hero_class.description, _status(world, h)]
	_follow_button.disabled = not h.alive or h.is_ruler
	_fill_stats(world, h)
	_thought.text = "[i]«%s»[/i]" % _current_thought(world, h)
	_relations.text = _relations_text(world, h)
	var deeds: Array[String] = []
	for i in range(h.deeds.size() - 1, -1, -1):
		deeds.append("• " + h.deeds[i])
	_deeds.text = "\n".join(deeds) if not deeds.is_empty() else "[color=#8a90a0]Пока ничего не совершил.[/color]"
	_mentions.text = _mentions_text(world, h)


func _fill_stats(world: World, h: Hero) -> void:
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	var need := h.level * 1.5
	_stat_bar("Уровень", "%d  (опыт %.1f / %.1f)" % [h.level, h.xp, need], h.xp / need if h.level < 20 else 1.0, Color(1.0, 0.85, 0.4))
	_stat_bar("Возраст", "%d из ~%d лет" % [h.age, h.max_age], float(h.age) / maxf(1.0, h.max_age), Color(0.6, 0.75, 0.9))
	_stat_bar("Ум", "%s (%.2f)" % [h.intellect_name(), h.wits()], h.wits(), Color(0.55, 0.7, 1.0))
	_stat_bar("Натура", "%s (%+.2f)" % [h.alignment_name(), h.karma], (h.karma + 1.0) * 0.5,
		Color(0.5, 0.9, 0.55) if h.karma >= 0.0 else Color(1.0, 0.45, 0.4))
	_stat_text("Сила", "%.0f воинов" % h.power())
	_stat_text("Победы", "%d в поединках, %d чудовищ" % [h.kills, h.monsters_slain])
	if not h.artifact.is_empty():
		_stat_text("Оружие", "%s (×%.1f к силе)" % [h.artifact, h.artifact_mult])
	if h.nation_id >= 0:
		_stat_text("Служит", world.nations[h.nation_id].name)
	if h.ally_nation >= 0:
		_stat_text("Воюет за", "%s (до %d г.)" % [world.nations[h.ally_nation].name, h.ally_until])
	var region := world.region_at(h.cell) if h.cell >= 0 else null
	if h.alive and h.cell >= 0:
		var owner := world.owner[h.cell]
		var where := region.name if region != null and not region.name.is_empty() else "дикие земли"
		_stat_text("Где", where + ((" (%s)" % world.nations[owner].short_name) if owner >= 0 else ""))
	if h.goal_cell >= 0:
		var goal := world.region_at(h.goal_cell)
		_stat_text("Цель", "пустой трон" + ((" в регионе " + goal.name) if goal != null else ""))
	_stat_text("Родился", "%d г.%s" % [h.born_year, (" · возвращён Судьбой %d раз" % h.returns) if h.returns > 0 else ""])


func _stat_text(label: String, value: String) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	l.add_theme_font_size_override("font_size", 13)
	_stats.add_child(l)
	var v := Label.new()
	v.text = value
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size = Vector2(230, 0)
	v.add_theme_font_size_override("font_size", 13)
	_stats.add_child(v)


func _stat_bar(label: String, value: String, ratio: float, color: Color) -> void:
	_stat_text(label, value)
	_stats.add_child(Control.new())
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(230, 6)
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.08)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	_stats.add_child(bar)


## Мысль героя: последнее решение, а если его нет — по тому, чем он занят.
func _current_thought(world: World, h: Hero) -> String:
	if not h.alive:
		match h.fate:
			&"rest":
				return "Покоится с миром."
			&"cursed":
				return "Душа заточена в проклятом оружии."
			_:
				return "Ждёт суда Судьбы."
	if h.is_ruler:
		return "Правлю. Странствия позади."
	if not h.thought.is_empty():
		return h.thought
	if h.vendetta >= 0:
		return "Ищу %s. Месть не ждёт." % world.heroes[h.vendetta].name
	if h.party_leader >= 0:
		return "Иду за %s, вместе мы сильнее." % world.heroes[h.party_leader].name
	if h.nation_id >= 0:
		return "Служу государству %s." % world.nations[h.nation_id].short_name
	return "Брожу по миру в поисках славы." if h.karma >= -0.3 else "Ищу, чем поживиться."


func _relations_text(world: World, h: Hero) -> String:
	var lines: Array[String] = []
	if h.spouse >= 0:
		lines.append("[color=#ffb3d0]Супруг(а):[/color] " + _hero_link(world, h.spouse))
	if h.mentor >= 0:
		lines.append("[color=#a8c8ff]Наставник:[/color] " + _hero_link(world, h.mentor))
	var pupils: Array[String] = []
	var party: Array[String] = []
	for o in world.heroes:
		if o.mentor == h.id:
			pupils.append(_hero_link(world, o.id))
		if o.party_leader == h.id and o.alive:
			party.append(_hero_link(world, o.id))
	if not pupils.is_empty():
		lines.append("[color=#a8c8ff]Ученики:[/color] " + ", ".join(pupils))
	if h.party_leader >= 0:
		lines.append("[color=#ffe680]В отряде героя[/color] " + _hero_link(world, h.party_leader))
	if not party.is_empty():
		lines.append("[color=#ffe680]Ведёт отряд:[/color] " + ", ".join(party))
	if h.vendetta >= 0:
		lines.append("[color=#ff6b5b]Поклялся отомстить:[/color] " + _hero_link(world, h.vendetta))
	if h.killed_by >= 0:
		lines.append("[color=#ff9a7a]Сражён героем[/color] " + _hero_link(world, h.killed_by))
	if not lines.is_empty():
		lines.append("")
	var ids := h.bonds.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return h.bonds[a] > h.bonds[b])
	if ids.is_empty():
		lines.append("[color=#8a90a0]Ни с кем не знаком.[/color]")
	for id in ids:
		var v: float = h.bonds[id]
		var word := "друг" if v > 0.5 else ("приятель" if v > 0.15 else ("враг" if v < -0.4 else ("недруг" if v < -0.15 else "знакомый")))
		var color := "#9be39b" if v > 0.15 else ("#ff9a7a" if v < -0.15 else "#b8c0d0")
		lines.append("%s  [color=%s]%s %s[/color]" % [_hero_link(world, id), color, _bar(v), word])
	return "\n".join(lines)


## Полоска отношения из символов: ▮ — сколько, цвет — знак.
static func _bar(v: float) -> String:
	var n := int(roundf(absf(v) * 5.0))
	return "▮".repeat(n) + "▯".repeat(5 - n)


func _hero_link(world: World, id: int) -> String:
	var o := world.heroes[id]
	return "[url=hero:%d]%s[/url]%s" % [id, o.display_name(), "" if o.alive else " †"]


func _mentions_text(world: World, h: Hero) -> String:
	var lines: Array[String] = []
	for i in range(world.chronicle.size() - 1, -1, -1):
		var e: Dictionary = world.chronicle[i]
		if (e.text as String).contains(h.name):
			lines.append("[color=#8a90a0]%d г.[/color] %s" % [e.year, e.text])
			if lines.size() >= MENTIONS:
				break
	return "\n".join(lines) if not lines.is_empty() else "[color=#8a90a0]Летописцы о нём пока молчат.[/color]"


func _status(world: World, h: Hero) -> String:
	if h.is_ruler:
		return "правитель"
	if not h.alive:
		return "пал"
	if h.nation_id >= 0:
		return "служит государству " + world.nations[h.nation_id].short_name
	return "странствует"


func _on_meta(meta: Variant) -> void:
	var s := str(meta)
	if s.begins_with("hero:"):
		open_window(int(s.substr(5)))


## Листает живых героев (если текущий пал — всех по порядку).
func _step(dir: int) -> void:
	var world := WorldState.world
	if world == null or world.heroes.is_empty():
		return
	var n := world.heroes.size()
	var id := _hero_id
	for i in n:
		id = posmod(id + dir, n)
		var o := world.heroes[id]
		if o.alive and not o.is_ruler:
			open_window(id)
			return


func _show_on_map() -> void:
	var world := WorldState.world
	if world == null or _hero_id < 0:
		return
	var h := world.heroes[_hero_id]
	close_window()
	if h.alive and h.cell >= 0:
		EventBus.focus_cell.emit(h.cell)


func _follow() -> void:
	_follow_id = _hero_id
	_follow_cell = -1
	close_window()
